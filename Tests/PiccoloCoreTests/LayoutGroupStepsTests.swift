import CoreGraphics
import Testing

@testable import PiccoloCore

/// `LayoutGroup.steps(from:to:current:)`: which windows are sent to a new frame, and in what order.
/// The order is what keeps windows from overlapping while a divider moves.
@Suite("Layout group: steps of a divider move")
struct LayoutGroupStepsTests {
    private static let visible = LinkedResizeSupport.visible
    private static let step = LinkedResizeSupport.step

    private static func group(windowCount: Int, rows: Int, columns: Int) -> LayoutGroup {
        let layout = TileLayout.grid(windowCount: windowCount, rows: rows, columns: columns)
        return LayoutGroup(
            layout: layout, windows: LinkedResizeSupport.windows(windowCount), visibleFrame: visible,
            frames: layout.frames(in: visible))
    }

    /// The steps of moving the divider from the focused cell in `direction`.
    private static func steps(
        of group: LayoutGroup, cell: Int, _ direction: Direction
    ) throws -> [LayoutGroup.Step] {
        let layout = try #require(
            DividerMove.plan(layout: group.layout, focusedCell: cell, direction: direction, step: step))
        return group.steps(
            from: group.targetFrames(for: group.layout), to: group.targetFrames(for: layout),
            current: group.frames)
    }

    private static func cells(_ steps: [LayoutGroup.Step]) -> [Int] { steps.map(\.cell) }

    // MARK: Side by side

    @Test("moving the divider of two windows right: B shrinks and is sent first, then A grows")
    func rightShrinksTheRightWindowFirst() throws {
        let group = Self.group(windowCount: 2, rows: 1, columns: 2)
        let steps = try Self.steps(of: group, cell: 0, .right)

        #expect(Self.cells(steps) == [1, 0])
        let targets = group.targetFrames(for: try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .right, step: Self.step)))
        #expect(steps.map(\.target) == [targets[1], targets[0]])
        #expect(steps.map(\.window) == [LinkedResizeSupport.windows(2)[1], LinkedResizeSupport.windows(2)[0]])
    }

    @Test("moving it left: A shrinks and is sent first, then B grows")
    func leftShrinksTheLeftWindowFirst() throws {
        let group = Self.group(windowCount: 2, rows: 1, columns: 2)
        #expect(Self.cells(try Self.steps(of: group, cell: 1, .left)) == [0, 1])
    }

    @Test("a window whose cell did not change is not a step")
    func untouchedWindowsAreSkipped() throws {
        let group = Self.group(windowCount: 3, rows: 1, columns: 3)

        // The divider between B and C: A stays.
        #expect(Set(Self.cells(try Self.steps(of: group, cell: 2, .left))) == [1, 2])
        // The divider between A and B: C stays.
        #expect(Set(Self.cells(try Self.steps(of: group, cell: 0, .right))) == [0, 1])
    }

    @Test("the shrinking window comes first whichever way the divider goes in a row of three")
    func threeInARow() throws {
        let group = Self.group(windowCount: 3, rows: 1, columns: 3)

        // B|C moves left: C grows to the left, B shrinks.
        #expect(Self.cells(try Self.steps(of: group, cell: 2, .left)) == [1, 2])
        // B|C moves right: B grows, C shrinks.
        #expect(Self.cells(try Self.steps(of: group, cell: 1, .right)) == [2, 1])
        // A|B moves left: B grows to the left, A shrinks.
        #expect(Self.cells(try Self.steps(of: group, cell: 1, .left)) == [0, 1])
        // A|B moves right: A grows, B shrinks.
        #expect(Self.cells(try Self.steps(of: group, cell: 0, .right)) == [1, 0])
    }

    // MARK: Stacked

    @Test("stacked: the window that shrinks is sent first, up or down")
    func stacked() throws {
        let group = Self.group(windowCount: 3, rows: 3, columns: 1)

        #expect(Self.cells(try Self.steps(of: group, cell: 0, .down)) == [1, 0])
        #expect(Self.cells(try Self.steps(of: group, cell: 1, .up)) == [0, 1])
        #expect(Self.cells(try Self.steps(of: group, cell: 1, .down)) == [2, 1])
        #expect(Self.cells(try Self.steps(of: group, cell: 2, .up)) == [1, 2])
    }

    // MARK: Grid

    @Test("2×2, vertical divider moved right: both right windows shrink first, then both left windows grow, each pair in cell order")
    func twoByTwoRight() throws {
        let group = Self.group(windowCount: 4, rows: 2, columns: 2)
        #expect(Self.cells(try Self.steps(of: group, cell: 0, .right)) == [1, 3, 0, 2])
    }

    @Test("2×2, vertical divider moved left: both left windows shrink first")
    func twoByTwoLeft() throws {
        let group = Self.group(windowCount: 4, rows: 2, columns: 2)
        #expect(Self.cells(try Self.steps(of: group, cell: 1, .left)) == [0, 2, 1, 3])
    }

    @Test("2×2, horizontal divider moved down: the bottom row shrinks first")
    func twoByTwoDown() throws {
        let group = Self.group(windowCount: 4, rows: 2, columns: 2)
        #expect(Self.cells(try Self.steps(of: group, cell: 0, .down)) == [2, 3, 0, 1])
    }

    @Test("three windows in 2×2: a vertical move leaves the wide bottom window alone")
    func threeInTwoByTwo() throws {
        let group = Self.group(windowCount: 3, rows: 2, columns: 2)

        #expect(Self.cells(try Self.steps(of: group, cell: 0, .right)) == [1, 0])
        // The wide window grows or shrinks with a horizontal move.
        #expect(Self.cells(try Self.steps(of: group, cell: 2, .up)) == [0, 1, 2])
    }

    // MARK: Compensation

    @Test("a window that is already at its target is not sent again")
    func alreadyThere() {
        let group = Self.group(windowCount: 2, rows: 1, columns: 2)
        let previous = group.targetFrames(for: group.layout)
        let targets = [
            CGRect(x: 0, y: 0, width: 550, height: 500), CGRect(x: 550, y: 0, width: 450, height: 500),
        ]
        // B refused and sits at 520…1000, A did reach its target.
        let current = [targets[0], CGRect(x: 520, y: 0, width: 480, height: 500)]

        let steps = group.steps(from: previous, to: targets, current: current)

        #expect(Self.cells(steps) == [1])
    }

    @Test("a difference of half a point or less is the same frame")
    func halfAPoint() {
        let group = Self.group(windowCount: 2, rows: 1, columns: 2)
        let previous = group.targetFrames(for: group.layout)
        let targets = previous.map { $0.offsetBy(dx: 0.4, dy: 0) }

        #expect(group.steps(from: previous, to: targets, current: group.frames).isEmpty)
    }

    @Test("windows that do not grow come first even when they only move")
    func movingOnlyCountsAsNotGrowing() {
        let group = Self.group(windowCount: 3, rows: 1, columns: 3)
        let previous = group.targetFrames(for: group.layout)
        // A grows by 100 points, B only shifts right by 100 points, C shrinks by 100 points.
        let targets = [
            CGRect(x: 0, y: 0, width: previous[0].width + 100, height: 500),
            previous[1].offsetBy(dx: 100, dy: 0),
            CGRect(x: previous[2].minX + 100, y: 0, width: previous[2].width - 100, height: 500),
        ]

        let steps = group.steps(from: previous, to: targets, current: group.frames)

        #expect(Self.cells(steps) == [1, 2, 0])
    }
}
