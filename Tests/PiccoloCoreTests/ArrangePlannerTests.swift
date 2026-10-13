import CoreGraphics
import Testing

@testable import PiccoloCore

@Suite("Arrange planner")
struct ArrangePlannerTests {
    typealias Support = ArrangePlannerSupport

    /// A candidate that must never be assigned, described for the test output.
    struct Excluded: Sendable, CustomTestStringConvertible {
        let name: String
        let standard: Bool
        let minimized: Bool
        let fullScreen: Bool

        var testDescription: String { name }
    }

    static let excluded: [Excluded] = [
        Excluded(name: "minimized", standard: true, minimized: true, fullScreen: false),
        Excluded(name: "full screen", standard: true, minimized: false, fullScreen: true),
        Excluded(name: "non-standard", standard: false, minimized: false, fullScreen: false),
    ]

    // MARK: Order and frames

    @Test("four eligible windows fill a 2x2 grid in focus order")
    func focusOrderFillsGrid() throws {
        // Front to back: 1, 2, 3, 4. Most recently focused first: 3, 1, 4, 2.
        let plan = try Support.planned(
            candidates: [Support.window(1), Support.window(2), Support.window(3), Support.window(4)],
            history: Support.history([3, 1, 4, 2]))

        #expect(plan.displayIndex == 0)
        #expect(plan.assignments.map(\.window) == Support.ids([3, 1, 4, 2]))
        #expect(plan.assignments.map(\.frame) == Support.gridFrames(4, on: Support.primary.visibleFrame))
        #expect(plan.layout == TileLayout.grid(windowCount: 4, rows: 2, columns: 2))
    }

    @Test("frames written out on the visible frame (0, 25, 1440, 875)")
    func literalFrames() throws {
        #expect(Support.primary.visibleFrame == CGRect(x: 0, y: 25, width: 1440, height: 875))

        let four = try Support.planned(candidates: Support.windows(4), history: Support.history([1, 2, 3, 4]))
        #expect(four.assignments.map(\.frame) == [
            CGRect(x: 0, y: 25, width: 720, height: 438),
            CGRect(x: 720, y: 25, width: 720, height: 438),
            CGRect(x: 0, y: 463, width: 720, height: 437),
            CGRect(x: 720, y: 463, width: 720, height: 437),
        ])

        let three = try Support.planned(candidates: Support.windows(3), history: Support.history([1, 2, 3]))
        #expect(three.assignments.map(\.frame) == [
            CGRect(x: 0, y: 25, width: 720, height: 438),
            CGRect(x: 720, y: 25, width: 720, height: 438),
            CGRect(x: 0, y: 463, width: 1440, height: 437),
        ])
    }

    @Test("a single cell takes the whole visible frame")
    func singleCell() throws {
        let plan = try Support.planned(
            grid: GridSpec(count: 1, rows: 1, columns: 1),
            candidates: Support.windows(1))
        #expect(plan.assignments.map(\.frame) == [CGRect(x: 0, y: 25, width: 1440, height: 875)])
    }

    @Test("more eligible windows than the count: only the most recent count are assigned")
    func moreWindowsThanCount() throws {
        // Front to back: 1 to 5. Most recently focused first: 5, 2, 4, 1, 3.
        let plan = try Support.planned(
            candidates: Support.windows(5),
            history: Support.history([5, 2, 4, 1, 3]))

        #expect(plan.assignments.map(\.window) == Support.ids([5, 2, 4, 1]))
        #expect(plan.assignments.map(\.frame) == Support.gridFrames(4, on: Support.primary.visibleFrame))
        #expect(plan.layout.windowCount == 4)
    }

    @Test("fewer eligible windows than cells: the layout shrinks as TileLayout.grid defines", arguments: [3, 2, 1])
    func fewerWindowsThanCells(count: Int) throws {
        let raw = (1...count).map(UInt32.init)
        // Most recently focused first: count, ..., 1.
        let plan = try Support.planned(
            candidates: Support.windows(count),
            history: Support.history(Array(raw.reversed())))

        #expect(plan.layout == TileLayout.grid(windowCount: count, rows: 2, columns: 2))
        #expect(plan.assignments.map(\.window) == Support.ids(Array(raw.reversed())))
        #expect(plan.assignments.map(\.frame) == Support.gridFrames(count, on: Support.primary.visibleFrame))
    }

    @Test("the layout has one cell per assignment", arguments: 1...7)
    func layoutMatchesAssignments(eligible: Int) throws {
        let plan = try Support.planned(
            grid: GridSpec(count: 6, rows: 2, columns: 3),
            candidates: Support.windows(eligible))

        #expect(plan.assignments.count == min(eligible, 6))
        #expect(plan.layout.windowCount == plan.assignments.count)
        #expect(plan.layout == TileLayout.grid(windowCount: min(eligible, 6), rows: 2, columns: 3))
    }

    @Test("a window listed twice is arranged once")
    func duplicateCandidate() throws {
        let plan = try Support.planned(candidates: [
            Support.window(1), Support.window(2), Support.window(1),
        ])
        #expect(plan.assignments.map(\.window) == Support.ids([1, 2]))
        #expect(plan.layout.windowCount == 2)
    }

    // MARK: Focus history and order of unknown windows

    @Test("windows unknown to the history follow the known ones, in front-to-back order")
    func unknownWindowsFollowKnown() throws {
        // Front to back: 10, 11, 12, 13. History: 12, then 99, which is not a candidate.
        let candidates = [10, 11, 12, 13].map { Support.window(UInt32($0)) }
        let plan = try Support.planned(candidates: candidates, history: Support.history([12, 99]))

        #expect(plan.assignments.map(\.window) == Support.ids([12, 10, 11, 13]))
    }

    @Test("with an empty history the front-to-back order decides")
    func emptyHistoryIsFrontToBack() throws {
        let candidates = [7, 3, 9, 1].map { Support.window(UInt32($0)) }

        let four = try Support.planned(candidates: candidates)
        #expect(four.assignments.map(\.window) == Support.ids([7, 3, 9, 1]))

        let two = try Support.planned(grid: GridSpec(count: 2, rows: 2, columns: 2), candidates: candidates)
        #expect(two.assignments.map(\.window) == Support.ids([7, 3]))
    }

    // MARK: Eligibility

    @Test("a minimized, full-screen or non-standard window is never assigned", arguments: excluded)
    func excludedWindowsNeverAssigned(kind: Excluded) throws {
        // Window 1 is the most recently focused, so it would be chosen if it were eligible.
        let hidden = Support.window(
            1, standard: kind.standard, minimized: kind.minimized, fullScreen: kind.fullScreen)
        let plan = try Support.planned(
            candidates: [hidden, Support.window(2), Support.window(3)],
            history: Support.history([1, 2, 3]))

        #expect(plan.assignments.map(\.window) == Support.ids([2, 3]))
    }

    @Test("excluded windows do not use up the count")
    func excludedWindowsDoNotUseCount() throws {
        // Front to back: 1 (minimized), 2 (full screen), 3 (non-standard), 4, 5, 6.
        // Most recently focused first: 1 to 6.
        let candidates = [
            Support.window(1, minimized: true),
            Support.window(2, fullScreen: true),
            Support.window(3, standard: false),
            Support.window(4),
            Support.window(5),
            Support.window(6),
        ]
        let plan = try Support.planned(
            grid: GridSpec(count: 2, rows: 1, columns: 2),
            candidates: candidates,
            history: Support.history([1, 2, 3, 4, 5, 6]))

        #expect(plan.assignments.map(\.window) == Support.ids([4, 5]))
        #expect(plan.layout == TileLayout.grid(windowCount: 2, rows: 1, columns: 2))
    }

    @Test("with two displays only the windows on displayIndex are assigned, on that display's visible frame")
    func onlyDisplayIndex() throws {
        // Front to back: 1 (primary), 2 (right), 3 (primary), 4 (right).
        // Most recently focused first: 2, 1, 4, 3.
        let candidates = [
            Support.window(1, frame: Support.onPrimary),
            Support.window(2, frame: Support.onRight),
            Support.window(3, frame: Support.onPrimary),
            Support.window(4, frame: Support.onRight),
        ]
        let history = Support.history([2, 1, 4, 3])

        let onPrimary = try Support.planned(displayIndex: 0, candidates: candidates, history: history)
        #expect(onPrimary.displayIndex == 0)
        #expect(onPrimary.assignments.map(\.window) == Support.ids([1, 3]))
        #expect(onPrimary.assignments.map(\.frame) == Support.gridFrames(2, on: Support.primary.visibleFrame))

        let onRight = try Support.planned(displayIndex: 1, candidates: candidates, history: history)
        #expect(onRight.displayIndex == 1)
        #expect(onRight.assignments.map(\.window) == Support.ids([2, 4]))
        #expect(onRight.assignments.map(\.frame) == Support.gridFrames(2, on: Support.right.visibleFrame))
    }

    @Test("a window straddling two displays belongs to the display holding its larger part")
    func straddlingWindow() throws {
        // Window 1 overlaps the primary by 140 pt and the right display by 160 pt: right.
        // Window 2 overlaps the primary by 140 pt and the right display by 60 pt: primary.
        let candidates = [
            Support.window(1, frame: CGRect(x: 1300, y: 100, width: 300, height: 200)),
            Support.window(2, frame: CGRect(x: 1300, y: 100, width: 200, height: 200)),
        ]

        let onPrimary = try Support.planned(displayIndex: 0, candidates: candidates)
        #expect(onPrimary.assignments.map(\.window) == Support.ids([2]))

        let onRight = try Support.planned(displayIndex: 1, candidates: candidates)
        #expect(onRight.assignments.map(\.window) == Support.ids([1]))
    }

    @Test("no eligible window gives nil")
    func noEligibleWindow() throws {
        let none = try Support.plan(candidates: [])
        #expect(none == nil)

        let allMinimized = try Support.plan(candidates: [
            Support.window(1, minimized: true),
            Support.window(2, minimized: true),
        ])
        #expect(allMinimized == nil)

        let allOnRight = try Support.plan(displayIndex: 0, candidates: [
            Support.window(1, frame: Support.onRight),
            Support.window(2, frame: Support.onRight),
        ])
        #expect(allOnRight == nil)
    }

    @Test("the minimum cell side is 100 points")
    func minimumCellSide() {
        #expect(ArrangePlanner.minimumCellSide == 100)
    }
}
