import CoreGraphics
import Testing

@testable import PiccoloCore

/// `ArrangePlanner` with both fill orders. Rows first is what the planner always did; columns first
/// numbers the cells column by column, so the most recently focused window still takes the
/// top-left cell and the second most recent one the cell below it.
@Suite("Arrange planner fill order")
struct ArrangePlannerFillOrderTests {
    typealias Support = ArrangePlannerSupport

    private static let visible = Support.primary.visibleFrame

    private static func plan(
        grid: GridSpec = Support.last4In2x2,
        fillOrder: GridFillOrder,
        candidates: [WindowCandidate],
        history: FocusHistory = FocusHistory(),
        displayIndex: Int = 0
    ) throws -> ArrangePlan? {
        try ArrangePlanner.plan(
            grid: grid, fillOrder: fillOrder, displayIndex: displayIndex, candidates: candidates,
            history: history, displays: Support.twoDisplays)
    }

    private static func planned(
        grid: GridSpec = Support.last4In2x2,
        fillOrder: GridFillOrder,
        candidates: [WindowCandidate],
        history: FocusHistory = FocusHistory()
    ) throws -> ArrangePlan {
        try #require(try plan(grid: grid, fillOrder: fillOrder, candidates: candidates, history: history))
    }

    // MARK: Rows first

    @Test("the fill order defaults to rows first")
    func defaultIsRowsFirst() throws {
        let candidates = Support.windows(3)
        let history = Support.history([1, 2, 3])
        let omitted = try Support.planned(candidates: candidates, history: history)
        let explicit = try Self.planned(fillOrder: .rows, candidates: candidates, history: history)
        #expect(omitted == explicit)
        #expect(explicit.layout.orientation == .rows)
    }

    @Test("rows first: three windows in 2x2 are two on top and one across the full width below")
    func rowsFirstThree() throws {
        let plan = try Self.planned(fillOrder: .rows, candidates: Support.windows(3), history: Support.history([1, 2, 3]))
        #expect(plan.assignments.map(\.frame) == [
            CGRect(x: 0, y: 25, width: 720, height: 438),
            CGRect(x: 720, y: 25, width: 720, height: 438),
            CGRect(x: 0, y: 463, width: 1440, height: 437),
        ])
    }

    // MARK: Columns first

    @Test("columns first: three windows in 2x2 are two stacked on the left and one at full height on the right")
    func columnsFirstThree() throws {
        // Most recently focused first: 2, 3, 1.
        let plan = try Self.planned(
            fillOrder: .columns, candidates: Support.windows(3), history: Support.history([2, 3, 1]))

        #expect(plan.displayIndex == 0)
        #expect(plan.assignments.map(\.window) == Support.ids([2, 3, 1]))
        #expect(plan.assignments.map(\.frame) == [
            CGRect(x: 0, y: 25, width: 720, height: 438),
            CGRect(x: 0, y: 463, width: 720, height: 437),
            CGRect(x: 720, y: 25, width: 720, height: 875),
        ])
        #expect(plan.layout == TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns))
        #expect(plan.layout.orientation == .columns)
        #expect(plan.layout.windowCount == plan.assignments.count)
    }

    @Test("columns first: four windows in 2x2 have the cells of rows first, with the second window at the bottom left")
    func columnsFirstFour() throws {
        let history = Support.history([1, 2, 3, 4])
        let columns = try Self.planned(fillOrder: .columns, candidates: Support.windows(4), history: history)
        let rows = try Self.planned(fillOrder: .rows, candidates: Support.windows(4), history: history)

        #expect(columns.assignments.map(\.window) == rows.assignments.map(\.window))
        #expect(columns.assignments.map(\.frame) == [
            CGRect(x: 0, y: 25, width: 720, height: 438),
            CGRect(x: 0, y: 463, width: 720, height: 437),
            CGRect(x: 720, y: 25, width: 720, height: 438),
            CGRect(x: 720, y: 463, width: 720, height: 437),
        ])
        #expect(columns.assignments.map(\.frame) == [
            rows.assignments[0].frame, rows.assignments[2].frame,
            rows.assignments[1].frame, rows.assignments[3].frame,
        ])
    }

    @Test("columns first: two windows in 2x2 are stacked top and bottom at full width")
    func columnsFirstTwo() throws {
        let plan = try Self.planned(
            fillOrder: .columns, candidates: Support.windows(2), history: Support.history([1, 2]))
        #expect(plan.assignments.map(\.frame) == [
            CGRect(x: 0, y: 25, width: 1440, height: 438),
            CGRect(x: 0, y: 463, width: 1440, height: 437),
        ])
    }

    @Test("columns first: five windows in 2x3 fill two full columns and a short third one")
    func columnsFirstFiveInTwoByThree() throws {
        let plan = try Self.planned(
            grid: GridSpec(count: 5, rows: 2, columns: 3),
            fillOrder: .columns, candidates: Support.windows(5), history: Support.history([1, 2, 3, 4, 5]))
        #expect(plan.layout.columns.map { $0.heights.count } == [2, 2, 1])
        #expect(plan.assignments.map(\.frame) == [
            CGRect(x: 0, y: 25, width: 480, height: 438),
            CGRect(x: 0, y: 463, width: 480, height: 437),
            CGRect(x: 480, y: 25, width: 480, height: 438),
            CGRect(x: 480, y: 463, width: 480, height: 437),
            CGRect(x: 960, y: 25, width: 480, height: 875),
        ])
    }

    @Test("columns first on the second display uses that display's visible frame")
    func columnsFirstOnSecondDisplay() throws {
        let onRight = [Support.window(1, frame: Support.onRight), Support.window(2, frame: Support.onRight),
                       Support.window(3, frame: Support.onRight)]
        let plan = try #require(try Self.plan(
            fillOrder: .columns, candidates: onRight, history: Support.history([1, 2, 3]), displayIndex: 1))
        #expect(plan.displayIndex == 1)
        #expect(plan.assignments.map(\.frame) == [
            CGRect(x: 1440, y: 0, width: 960, height: 528),
            CGRect(x: 1440, y: 528, width: 960, height: 527),
            CGRect(x: 2400, y: 0, width: 960, height: 1055),
        ])
    }

    @Test("the frames tile the visible frame in either order", arguments: GridFillOrder.allCases)
    func framesTileTheVisibleFrame(fillOrder: GridFillOrder) throws {
        for count in 1...6 {
            let plan = try Self.planned(
                grid: GridSpec(count: 6, rows: 2, columns: 3),
                fillOrder: fillOrder, candidates: Support.windows(count),
                history: Support.history((1...UInt32(count)).map { $0 }))
            let frames = plan.assignments.map(\.frame)
            #expect(TileLayoutSupport.overlapViolations(frames).isEmpty, "\(count) windows")
            #expect(
                TileLayoutSupport.coverageViolations(frames, visible: Self.visible).isEmpty,
                "\(count) windows")
        }
    }

    // MARK: Checks that do not depend on the order

    @Test("a cell below the minimum side is refused in either order", arguments: GridFillOrder.allCases)
    func cellTooSmall(fillOrder: GridFillOrder) throws {
        // Ten windows in one column of the 875 pt tall display: 87.5 pt each.
        #expect(throws: ArrangePlannerError.cellTooSmall) {
            _ = try Self.plan(
                grid: GridSpec(count: 10, rows: 10, columns: 1),
                fillOrder: fillOrder, candidates: Support.windows(10),
                history: Support.history((1...10).map { $0 }))
        }
    }

    @Test("an invalid grid is refused in either order, even with nothing to arrange", arguments: GridFillOrder.allCases)
    func invalidGrid(fillOrder: GridFillOrder) {
        do {
            _ = try Self.plan(
                grid: GridSpec(count: 4, rows: 0, columns: 2), fillOrder: fillOrder, candidates: [])
            Issue.record("the planner accepted a grid with no rows")
        } catch {
            guard case .invalidGrid = error as? ArrangePlannerError else {
                Issue.record("expected invalidGrid, got \(error)")
                return
            }
        }
    }

    @Test("without eligible windows there is nothing to arrange in either order", arguments: GridFillOrder.allCases)
    func nothingToArrange(fillOrder: GridFillOrder) throws {
        let plan = try Self.plan(fillOrder: fillOrder, candidates: [Support.window(1, minimized: true)])
        #expect(plan == nil)
    }
}
