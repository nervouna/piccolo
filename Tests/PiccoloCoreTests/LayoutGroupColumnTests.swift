import CoreGraphics
import Testing

@testable import PiccoloCore

/// `LayoutGroup` on a column layout: cell lookup, target frames, breakage, the order of the steps of
/// a divider move and `recordAchieved`. The cells are numbered column by column. The record tests are
/// the transposed counterparts of `LayoutGroupRecordTests`: the visible frame is the transpose of
/// the one used there (500 by 1000 points instead of 1000 by 500), and every achieved frame is the
/// transpose of the frame in the row test, so that the numbers are the same and only the axis
/// differs.
@Suite("Layout group on a column layout")
struct LayoutGroupColumnTests {
    /// 500 by 1000 points, the transpose of `LinkedResizeSupport.visible`.
    private static let visible = CGRect(x: 0, y: 0, width: 500, height: 1000)
    private static let step = LinkedResizeSupport.step

    /// The transpose of a frame of the row tests, written out independently of the code under test.
    private static func t(_ rect: CGRect) -> CGRect {
        ColumnLayoutSupport.transposed(rect)
    }

    private static func column(_ width: Double, _ heights: [Double]) -> TileLayout.Column {
        TileLayout.Column(width: width, heights: heights)
    }

    private static func group(
        windowCount: Int, rows: Int, columns: Int, visible: CGRect = LinkedResizeSupport.visible
    ) -> LayoutGroup {
        let layout = TileLayout.grid(
            windowCount: windowCount, rows: rows, columns: columns, fillOrder: .columns)
        return LayoutGroup(
            layout: layout, windows: LinkedResizeSupport.windows(windowCount), visibleFrame: visible,
            frames: layout.frames(in: visible))
    }

    /// Whether `actual` is a column layout with the same columns and cells per column as
    /// `expected`, and fractions that agree within `tolerance`.
    private static func isClose(
        _ actual: TileLayout, _ expected: TileLayout, tolerance: Double = 1e-9
    ) -> Bool {
        actual.orientation == .columns && expected.orientation == .columns
            && actual.columns.count == expected.columns.count
            && zip(actual.columns, expected.columns).allSatisfy { a, e in
                abs(a.width - e.width) <= tolerance
                    && LinkedResizeSupport.isClose(a.heights, e.heights, tolerance: tolerance)
            }
    }

    // MARK: cell(of:), targetFrames(for:), breakage

    @Test("cell(of:) numbers the cells column by column")
    func cellOf() {
        // Three windows in 2x2, columns first: 1 top left, 2 bottom left, 3 the whole right column.
        let group = Self.group(windowCount: 3, rows: 2, columns: 2)
        #expect(group.cell(of: WindowID(rawValue: 1)) == 0)
        #expect(group.cell(of: WindowID(rawValue: 2)) == 1)
        #expect(group.cell(of: WindowID(rawValue: 3)) == 2)
        #expect(group.cell(of: WindowID(rawValue: 99)) == nil)
    }

    @Test("the frames recorded for the windows are the cells, in column-major order")
    func recordedFramesFollowTheCells() {
        let group = Self.group(windowCount: 3, rows: 2, columns: 2)
        #expect(group.frames == [
            CGRect(x: 0, y: 0, width: 500, height: 250),
            CGRect(x: 0, y: 250, width: 500, height: 250),
            CGRect(x: 500, y: 0, width: 500, height: 500),
        ])
    }

    @Test("targetFrames(for:) frames a column layout in the group's visible frame, column by column")
    func targetFramesUseVisibleFrame() {
        let group = Self.group(windowCount: 3, rows: 2, columns: 2)
        let layout = TileLayout(columns: [
            Self.column(0.25, [1]),
            Self.column(0.75, [0.4, 0.6]),
        ])
        #expect(group.targetFrames(for: layout) == [
            CGRect(x: 0, y: 0, width: 250, height: 500),
            CGRect(x: 250, y: 0, width: 750, height: 200),
            CGRect(x: 250, y: 200, width: 750, height: 300),
        ])
    }

    @Test("a group of a column layout is intact until a window is missing or moved, and names the first one in cell order")
    func breakage() {
        let group = Self.group(windowCount: 4, rows: 2, columns: 2)
        var current = Dictionary(uniqueKeysWithValues: zip(group.windows, group.frames))
        #expect(group.breakage(currentFrames: current) == nil)
        #expect(group.isIntact(currentFrames: current))

        // Window 3 is the top of the right column, window 2 the bottom of the left one.
        current[WindowID(rawValue: 3)] = nil
        current[WindowID(rawValue: 2)] = current[WindowID(rawValue: 2)]!.offsetBy(dx: 0, dy: 10)
        #expect(group.breakage(currentFrames: current) == .moved(WindowID(rawValue: 2)))
        #expect(!group.isIntact(currentFrames: current))

        current[WindowID(rawValue: 1)] = nil
        #expect(group.breakage(currentFrames: current) == .missing(WindowID(rawValue: 1)))
    }

    // MARK: steps(from:to:current:)

    /// The cells of the steps of moving the divider from the focused cell in `direction`.
    private static func stepCells(
        of group: LayoutGroup, cell: Int, _ direction: Direction
    ) throws -> [Int] {
        let layout = try #require(
            DividerMove.plan(layout: group.layout, focusedCell: cell, direction: direction, step: step))
        return group.steps(
            from: group.targetFrames(for: group.layout), to: group.targetFrames(for: layout),
            current: group.frames
        ).map(\.cell)
    }

    @Test("two windows in a column: the window that shrinks is sent first, then the one that grows")
    func twoInAColumn() throws {
        let group = Self.group(windowCount: 2, rows: 2, columns: 1)
        #expect(try Self.stepCells(of: group, cell: 0, .down) == [1, 0])
        #expect(try Self.stepCells(of: group, cell: 1, .up) == [0, 1])
    }

    @Test("a window whose cell did not change is not a step")
    func untouchedWindowsAreSkipped() throws {
        let group = Self.group(windowCount: 3, rows: 3, columns: 1)
        // The divider between the middle and the bottom window: the top window stays.
        #expect(Set(try Self.stepCells(of: group, cell: 2, .up)) == [1, 2])
        // The divider between the top and the middle window: the bottom window stays.
        #expect(Set(try Self.stepCells(of: group, cell: 0, .down)) == [0, 1])
    }

    @Test("2×2 columns first, vertical divider moved right: the right column shrinks first, then the left one grows, each in cell order")
    func twoByTwoRight() throws {
        let group = Self.group(windowCount: 4, rows: 2, columns: 2)
        #expect(try Self.stepCells(of: group, cell: 0, .right) == [2, 3, 0, 1])
    }

    @Test("2×2 columns first, vertical divider moved left: the left column shrinks first")
    func twoByTwoLeft() throws {
        let group = Self.group(windowCount: 4, rows: 2, columns: 2)
        #expect(try Self.stepCells(of: group, cell: 2, .left) == [0, 1, 2, 3])
    }

    @Test("2×2 columns first, horizontal divider moved down: the lower window of each column shrinks first")
    func twoByTwoDown() throws {
        let group = Self.group(windowCount: 4, rows: 2, columns: 2)
        #expect(try Self.stepCells(of: group, cell: 0, .down) == [1, 3, 0, 2])
    }

    @Test("three windows in 2×2 columns first: a horizontal move leaves the tall right window alone")
    func threeInTwoByTwo() throws {
        let group = Self.group(windowCount: 3, rows: 2, columns: 2)
        #expect(try Self.stepCells(of: group, cell: 0, .down) == [1, 0])
        // The tall window grows or shrinks with a vertical move, with the two it shares the divider with.
        #expect(try Self.stepCells(of: group, cell: 2, .left) == [0, 1, 2])
    }

    // MARK: recordAchieved

    /// Two windows stacked in one column, the transpose of `LayoutGroupRecordTests.sideBySide()`.
    private static func stackedInAColumn() -> LayoutGroup {
        group(windowCount: 2, rows: 2, columns: 1, visible: visible)
    }

    /// Two windows side by side, one per column, the transpose of `LayoutGroupRecordTests.stacked()`.
    private static func sideBySideColumns() -> LayoutGroup {
        group(windowCount: 2, rows: 1, columns: 2, visible: visible)
    }

    @Test("when every window reached its frame, the layout is the requested one and the frames are the achieved ones")
    func allReached() throws {
        var group = Self.stackedInAColumn()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .down, step: Self.step))
        let achieved = requested.frames(in: Self.visible)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(Self.isClose(group.layout, requested))
        #expect(group.frames == achieved)
        #expect(LinkedResizeSupport.isValid(group.layout))
    }

    @Test("a deviation of one point or less is not recorded")
    func withinOnePoint() throws {
        var group = Self.stackedInAColumn()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .down, step: Self.step))
        let achieved = [
            CGRect(x: 0, y: 0, width: 551, height: 500), CGRect(x: 551, y: 0, width: 449, height: 500),
        ].map(Self.t)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(Self.isClose(group.layout, requested))
        #expect(group.frames == achieved)
    }

    @Test("a lower window that could not get lower pulls the divider back to where it ended up")
    func lowerWindowStoppedByMinimumHeight() throws {
        var group = Self.stackedInAColumn()
        // The move asks for A 550 and B 450. B needs 500 points, so it is placed at 550, sticks out
        // of the display at the bottom, and is shifted back to y = 500.
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .down, step: Self.step))
        let achieved = [
            CGRect(x: 0, y: 0, width: 550, height: 500), CGRect(x: 500, y: 0, width: 500, height: 500),
        ].map(Self.t)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(Self.isClose(group.layout, TileLayout(columns: [Self.column(1, [0.5, 0.5])])))
        #expect(group.frames == achieved)
        #expect(LinkedResizeSupport.isValid(group.layout))
    }

    @Test("an upper window that could not grow leaves a gap, and the divider stops at its bottom edge")
    func upperWindowStoppedByMaximumHeight() throws {
        var group = Self.stackedInAColumn()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .down, step: Self.step))
        // A asked for 550 points and stopped at 500. B was placed at 550, so there is a gap.
        let achieved = [
            CGRect(x: 0, y: 0, width: 500, height: 500), CGRect(x: 550, y: 0, width: 450, height: 500),
        ].map(Self.t)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(Self.isClose(group.layout, TileLayout(columns: [Self.column(1, [0.5, 0.5])])))
        #expect(group.frames == achieved)
    }

    @Test("a middle window that could not reach its bottom edge moves that divider to its edge")
    func middleWindowStopped() throws {
        let visible = Self.t(CGRect(x: 0, y: 0, width: 900, height: 300))
        let layout = TileLayout.grid(windowCount: 3, rows: 3, columns: 1, fillOrder: .columns)
        var group = LayoutGroup(
            layout: layout, windows: LinkedResizeSupport.windows(3), visibleFrame: visible,
            frames: layout.frames(in: visible))
        // Nothing moves, so the requested layout is the current one. B asked for 600 and stopped at
        // 540, so the divider between B and C moves to 0.6 and C fills the rest.
        let achieved = [
            CGRect(x: 0, y: 0, width: 300, height: 300),
            CGRect(x: 300, y: 0, width: 240, height: 300),
            CGRect(x: 600, y: 0, width: 300, height: 300),
        ].map(Self.t)

        group.recordAchieved(requested: layout, achieved: achieved)

        #expect(Self.isClose(group.layout, TileLayout(columns: [
            Self.column(1, [1.0 / 3.0, 0.6 - 1.0 / 3.0, 0.4])
        ])))
        #expect(LinkedResizeSupport.isValid(group.layout))
    }

    @Test("a left window that could not reach its right edge moves the divider to where it ended")
    func leftWindowStoppedByMaximumWidth() throws {
        var group = Self.sideBySideColumns()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .right, step: Self.step))
        // The left window asked for 275 points and stopped at 260. The right one fills from 260.
        let achieved = [
            CGRect(x: 0, y: 0, width: 1000, height: 260), CGRect(x: 0, y: 275, width: 1000, height: 225),
        ].map(Self.t)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(Self.isClose(group.layout, TileLayout(columns: [
            Self.column(0.52, [1]),
            Self.column(0.48, [1]),
        ])))
        #expect(group.frames == achieved)
    }

    @Test("a right window pushed left by the right edge of the display moves the divider back")
    func rightWindowShiftedLeft() throws {
        var group = Self.sideBySideColumns()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .right, step: Self.step))
        // The right window asked for 225 points at x = 275 but needs 250. It sticks out at the right
        // and is shifted left to x = 250.
        let achieved = [
            CGRect(x: 0, y: 0, width: 1000, height: 275), CGRect(x: 0, y: 250, width: 1000, height: 250),
        ].map(Self.t)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(Self.isClose(group.layout, TileLayout(columns: [
            Self.column(0.5, [1]),
            Self.column(0.5, [1]),
        ])))
    }

    @Test("2x2 columns first: a window that could not reach its width moves the divider of the whole grid")
    func gridColumnStopped() throws {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2, fillOrder: .columns)
        var group = LayoutGroup(
            layout: layout, windows: LinkedResizeSupport.windows(4), visibleFrame: Self.visible,
            frames: layout.frames(in: Self.visible))
        let requested = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        // Only the top-left window stops, at 260 wide instead of 275. The other three are as asked.
        // Cells are numbered column by column, so the cell order of the row test carries over.
        let achieved = [
            CGRect(x: 0, y: 0, width: 500, height: 260),
            CGRect(x: 500, y: 0, width: 500, height: 275),
            CGRect(x: 0, y: 275, width: 500, height: 225),
            CGRect(x: 500, y: 275, width: 500, height: 225),
        ].map(Self.t)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(Self.isClose(group.layout, TileLayout(columns: [
            Self.column(0.52, [0.5, 0.5]),
            Self.column(0.48, [0.5, 0.5]),
        ])))
        #expect(group.frames == achieved)
    }

    @Test("a window that runs past the next divider keeps the requested fractions of its column")
    func overflowPastNextDividerKeepsRequested() throws {
        let visible = Self.t(CGRect(x: 0, y: 0, width: 900, height: 300))
        let layout = TileLayout.grid(windowCount: 3, rows: 3, columns: 1, fillOrder: .columns)
        var group = LayoutGroup(
            layout: layout, windows: LinkedResizeSupport.windows(3), visibleFrame: visible,
            frames: layout.frames(in: visible))
        let requested = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .down, step: Self.step))
        // A needs 700 points, so its bottom edge would pass the divider between B and C. The
        // positions would then be out of order, so the column keeps the requested heights.
        let achieved = [
            CGRect(x: 0, y: 0, width: 700, height: 300),
            CGRect(x: 345, y: 0, width: 210, height: 300),
            CGRect(x: 555, y: 0, width: 345, height: 300),
        ].map(Self.t)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(Self.isClose(group.layout, requested))
        #expect(LinkedResizeSupport.isValid(group.layout))
        #expect(group.frames == achieved)
    }

    @Test("a requested layout of the other orientation is a precondition failure")
    func orientationPrecondition() async {
        await #expect(processExitsWith: .failure) {
            var group = LayoutGroup(
                layout: TileLayout.grid(windowCount: 2, rows: 2, columns: 1, fillOrder: .columns),
                windows: LinkedResizeSupport.windows(2),
                visibleFrame: LinkedResizeSupport.visible,
                frames: [CGRect(x: 0, y: 0, width: 1000, height: 250), CGRect(x: 0, y: 250, width: 1000, height: 250)])
            let rows = TileLayout.grid(windowCount: 2, rows: 2, columns: 1)
            group.recordAchieved(
                requested: rows, achieved: [CGRect(x: 0, y: 0, width: 1000, height: 250), CGRect(x: 0, y: 250, width: 1000, height: 250)])
        }
    }
}
