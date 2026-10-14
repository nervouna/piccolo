import Testing

@testable import PiccoloCore

/// `DividerMove.plan` on column layouts: the transposed counterpart of every test in
/// `DividerMoveTests`. A column layout is the transpose of a row layout, so `left` and `right` move
/// the vertical divider between columns (what `up` and `down` do between rows), `up` and `down` move
/// a horizontal divider inside the focused column (what `left` and `right` do inside a row), and
/// cells are numbered column by column.
///
/// The expected fractions are written out by hand, not computed by the code under test.
@Suite("Divider move on column layouts")
struct DividerMoveColumnTests {
    typealias Example = DividerMoveCase

    private static let step = LinkedResizeSupport.step

    private static func column(_ width: Double, _ heights: [Double]) -> TileLayout.Column {
        TileLayout.Column(width: width, heights: heights)
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

    private static func plan(
        _ layout: TileLayout, cell: Int, _ direction: Direction
    ) -> TileLayout? {
        DividerMove.plan(layout: layout, focusedCell: cell, direction: direction, step: step)
    }

    // MARK: Stacked in one column, up and down

    /// Three windows stacked in one column, from equal cells of 1/3 each, with a step of 0.05:
    /// the table of `DividerMoveTests.threeAcross`, with `up` for `left` and `down` for `right`.
    static let threeInAColumn: [Example] = [
        Example(
            name: "top up", focusedCell: 0, direction: .up,
            fractions: [1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05, 1.0 / 3.0]),
        Example(
            name: "top down", focusedCell: 0, direction: .down,
            fractions: [1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05, 1.0 / 3.0]),
        Example(
            name: "middle up", focusedCell: 1, direction: .up,
            fractions: [1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05, 1.0 / 3.0]),
        Example(
            name: "middle down", focusedCell: 1, direction: .down,
            fractions: [1.0 / 3.0, 1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05]),
        Example(
            name: "bottom up", focusedCell: 2, direction: .up,
            fractions: [1.0 / 3.0, 1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05]),
        Example(
            name: "bottom down", focusedCell: 2, direction: .down,
            fractions: [1.0 / 3.0, 1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05]),
    ]

    @Test("three windows in one column move the divider the transposed design table gives", arguments: threeInAColumn)
    func threeInAColumnTable(example: Example) throws {
        let layout = TileLayout(columns: [Self.column(1, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])])
        let moved = try #require(Self.plan(layout, cell: example.focusedCell, example.direction))
        #expect(moved.orientation == .columns)
        #expect(LinkedResizeSupport.isClose(moved.columns[0].heights, example.fractions))
        #expect(moved.columns[0].width == 1)
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test(
        "two windows in one column: either window moves the one divider the same way",
        arguments: [
            Example(name: "first up", focusedCell: 0, direction: .up,
                    fractions: [0.5 - 0.05, 0.5 + 0.05]),
            Example(name: "first down", focusedCell: 0, direction: .down,
                    fractions: [0.5 + 0.05, 0.5 - 0.05]),
            Example(name: "second up", focusedCell: 1, direction: .up,
                    fractions: [0.5 - 0.05, 0.5 + 0.05]),
            Example(name: "second down", focusedCell: 1, direction: .down,
                    fractions: [0.5 + 0.05, 0.5 - 0.05]),
        ])
    func twoInAColumn(example: Example) throws {
        let layout = TileLayout.grid(windowCount: 2, rows: 2, columns: 1, fillOrder: .columns)
        let moved = try #require(Self.plan(layout, cell: example.focusedCell, example.direction))
        #expect(LinkedResizeSupport.isClose(moved.columns[0].heights, example.fractions))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    // MARK: Side by side, one window per column, left and right

    static let twoSideBySide: [Example] = [
        Example(name: "left left", focusedCell: 0, direction: .left,
                fractions: [0.5 - 0.05, 0.5 + 0.05]),
        Example(name: "left right", focusedCell: 0, direction: .right,
                fractions: [0.5 + 0.05, 0.5 - 0.05]),
        Example(name: "right left", focusedCell: 1, direction: .left,
                fractions: [0.5 - 0.05, 0.5 + 0.05]),
        Example(name: "right right", focusedCell: 1, direction: .right,
                fractions: [0.5 + 0.05, 0.5 - 0.05]),
    ]

    @Test("two windows side by side, one per column: the left and right window move the divider in the key's direction",
          arguments: twoSideBySide)
    func twoSideBySideTable(example: Example) throws {
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2, fillOrder: .columns)
        let moved = try #require(Self.plan(layout, cell: example.focusedCell, example.direction))
        #expect(LinkedResizeSupport.isClose(moved.columns.map(\.width), example.fractions))
        #expect(moved.columns.allSatisfy { $0.heights == [1] })
        #expect(LinkedResizeSupport.isValid(moved))
    }

    /// Three windows side by side. The left column has no column to its left, so `left` moves its
    /// right edge; the right column has none to its right, so `right` moves its left edge.
    static let threeSideBySide: [Example] = [
        Example(name: "left left", focusedCell: 0, direction: .left,
                fractions: [1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05, 1.0 / 3.0]),
        Example(name: "left right", focusedCell: 0, direction: .right,
                fractions: [1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05, 1.0 / 3.0]),
        Example(name: "middle left", focusedCell: 1, direction: .left,
                fractions: [1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05, 1.0 / 3.0]),
        Example(name: "middle right", focusedCell: 1, direction: .right,
                fractions: [1.0 / 3.0, 1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05]),
        Example(name: "right left", focusedCell: 2, direction: .left,
                fractions: [1.0 / 3.0, 1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05]),
        Example(name: "right right", focusedCell: 2, direction: .right,
                fractions: [1.0 / 3.0, 1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05]),
    ]

    @Test("three windows side by side, one per column: the outer columns move their inner edges", arguments: threeSideBySide)
    func threeSideBySideTable(example: Example) throws {
        let layout = TileLayout.grid(windowCount: 3, rows: 1, columns: 3, fillOrder: .columns)
        let moved = try #require(Self.plan(layout, cell: example.focusedCell, example.direction))
        #expect(LinkedResizeSupport.isClose(moved.columns.map(\.width), example.fractions))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("left and right leave every cell height alone, and the columns of a grid keep their own heights")
    func horizontalMovesKeepHeights() throws {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2, fillOrder: .columns)
        let moved = try #require(Self.plan(layout, cell: 0, .right))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.55, [0.5, 0.5]),
            Self.column(0.45, [0.5, 0.5]),
        ])))
    }

    // MARK: Grids and alignment

    @Test("2x2: the horizontal divider of the top-left cell moves the right column's divider too")
    func twoByTwoAlignedDivider() throws {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2, fillOrder: .columns)
        let moved = try #require(Self.plan(layout, cell: 0, .down))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.5, [0.55, 0.45]),
            Self.column(0.5, [0.55, 0.45]),
        ])))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("2x2: a key from the bottom-right cell moves the aligned divider of both columns up")
    func twoByTwoAlignedFromBottomRight() throws {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2, fillOrder: .columns)
        // Column-major: cell 3 is the bottom cell of the right column.
        let moved = try #require(Self.plan(layout, cell: 3, .up))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.5, [0.45, 0.55]),
            Self.column(0.5, [0.45, 0.55]),
        ])))
    }

    @Test("3 in 2x2 columns first: the right column has no horizontal divider, so it does not move")
    func threeInTwoByTwoRightColumnStays() throws {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns)
        let moved = try #require(Self.plan(layout, cell: 0, .down))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.5, [0.55, 0.45]),
            Self.column(0.5, [1]),
        ])))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("3 in 2x2 columns first: right from a left window moves the divider between the columns, and every cell follows")
    func threeInTwoByTwoColumnDivider() throws {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns)
        for cell in [0, 1] {
            let moved = try #require(Self.plan(layout, cell: cell, .right))
            #expect(Self.isClose(moved, TileLayout(columns: [
                Self.column(0.55, [0.5, 0.5]),
                Self.column(0.45, [1]),
            ])), "from cell \(cell)")
        }
        // From the right column's window, left moves the same divider.
        let moved = try #require(Self.plan(layout, cell: 2, .left))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.45, [0.5, 0.5]),
            Self.column(0.55, [1]),
        ])))
    }

    @Test("an aligned divider in another column moves even when it has a different index there")
    func alignedDividerAtOtherIndex() throws {
        // The first column's divider sits at 0.5. In the second column the same position is its
        // second divider.
        let layout = TileLayout(columns: [
            Self.column(0.5, [0.5, 0.5]),
            Self.column(0.5, [0.25, 0.25, 0.5]),
        ])
        let moved = try #require(Self.plan(layout, cell: 0, .down))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.5, [0.55, 0.45]),
            Self.column(0.5, [0.25, 0.3, 0.45]),
        ])))
    }

    @Test("a divider counts as aligned when its position matches within 1e-9, not exactly")
    func alignedWithinTolerance() throws {
        // 0.1 + 0.2 is 0.30000000000000004 in floating point, not 0.3.
        let layout = TileLayout(columns: [
            Self.column(0.5, [0.3, 0.7]),
            Self.column(0.5, [0.1, 0.2, 0.7]),
        ])
        let moved = try #require(Self.plan(layout, cell: 0, .down))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.5, [0.35, 0.65]),
            Self.column(0.5, [0.1, 0.25, 0.65]),
        ])))
    }

    @Test("a divider that differs by more than 1e-9 is not aligned, and the column does not move")
    func notAlignedBeyondTolerance() throws {
        let layout = TileLayout(columns: [
            Self.column(0.5, [0.5, 0.5]),
            Self.column(0.5, [0.500001, 0.499999]),
        ])
        let moved = try #require(Self.plan(layout, cell: 0, .down))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.5, [0.55, 0.45]),
            Self.column(0.5, [0.500001, 0.499999]),
        ])))
    }

    @Test("a column with no aligned divider does not limit the move, even when it is low")
    func unalignedColumnDoesNotLimit() throws {
        // The second column's low cell is 0.12 high, but its dividers sit at 0.42 and 0.54, not at 0.5.
        let layout = TileLayout(columns: [
            Self.column(0.5, [0.5, 0.5]),
            Self.column(0.5, [0.42, 0.12, 0.46]),
        ])
        let moved = try #require(Self.plan(layout, cell: 0, .down))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.5, [0.55, 0.45]),
            Self.column(0.5, [0.42, 0.12, 0.46]),
        ])))
    }

    // MARK: Nothing moves

    @Test("a single cell moves nothing in any direction", arguments: Direction.allCases)
    func singleCell(direction: Direction) {
        let layout = TileLayout.grid(windowCount: 1, rows: 1, columns: 1, fillOrder: .columns)
        #expect(Self.plan(layout, cell: 0, direction) == nil)
    }

    @Test("a single column moves nothing left or right", arguments: [Direction.left, .right])
    func singleColumnHorizontal(direction: Direction) {
        let layout = TileLayout.grid(windowCount: 3, rows: 3, columns: 1, fillOrder: .columns)
        #expect(layout.columns.count == 1)
        #expect(Self.plan(layout, cell: 1, direction) == nil)
    }

    @Test("a single row of columns moves nothing up or down", arguments: [Direction.up, .down])
    func singleRowVertical(direction: Direction) {
        let layout = TileLayout.grid(windowCount: 3, rows: 1, columns: 3, fillOrder: .columns)
        #expect(layout.columns.count == 3)
        #expect(Self.plan(layout, cell: 1, direction) == nil)
    }

    @Test("a window alone in its column has no horizontal divider to move")
    func aloneInColumnHasNoHorizontalDivider() throws {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns)
        #expect(Self.plan(layout, cell: 2, .up) == nil)
        #expect(Self.plan(layout, cell: 2, .down) == nil)
        // Its column still has a vertical divider on its left.
        let moved = try #require(Self.plan(layout, cell: 2, .left))
        #expect(LinkedResizeSupport.isClose(moved.columns.map(\.width), [0.45, 0.55]))
    }

    @Test("a focused cell outside the layout moves nothing")
    func cellOutsideLayout() {
        let layout = TileLayout.grid(windowCount: 2, rows: 2, columns: 1, fillOrder: .columns)
        #expect(Self.plan(layout, cell: 2, .down) == nil)
        #expect(Self.plan(layout, cell: -1, .up) == nil)
    }

    // MARK: Limits

    @Test("a move that would take a cell below the minimum is shortened to the room left")
    func shortenedToRoom() throws {
        // The lower cell is 0.12 high. Shrinking it by the full step would leave 0.07, below 0.1.
        let layout = TileLayout(columns: [Self.column(1, [0.88, 0.12])])
        let moved = try #require(Self.plan(layout, cell: 0, .down))
        #expect(LinkedResizeSupport.isClose(moved.columns[0].heights, [0.88 + 0.02, 0.12 - 0.02]))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("a shortened move on the other side, and in the other direction")
    func shortenedUp() throws {
        let layout = TileLayout(columns: [Self.column(1, [0.12, 0.88])])
        let moved = try #require(Self.plan(layout, cell: 1, .up))
        #expect(LinkedResizeSupport.isClose(moved.columns[0].heights, [0.12 - 0.02, 0.88 + 0.02]))
    }

    @Test("a move that has no room at all is nil")
    func blockedStacked() {
        let down = TileLayout(columns: [Self.column(1, [0.9, 0.1])])
        #expect(Self.plan(down, cell: 0, .down) == nil)
        let up = TileLayout(columns: [Self.column(1, [0.1, 0.9])])
        #expect(Self.plan(up, cell: 1, .up) == nil)
    }

    @Test("a move between columns shortened by the column it shrinks, and blocked when that column is at the minimum")
    func columnLimits() throws {
        let shortened = TileLayout(columns: [
            Self.column(0.12, [1]),
            Self.column(0.88, [1]),
        ])
        let moved = try #require(Self.plan(shortened, cell: 1, .left))
        #expect(LinkedResizeSupport.isClose(moved.columns.map(\.width), [0.12 - 0.02, 0.88 + 0.02]))

        let blocked = TileLayout(columns: [
            Self.column(0.9, [1]),
            Self.column(0.1, [1]),
        ])
        #expect(Self.plan(blocked, cell: 0, .right) == nil)
    }

    @Test("an aligned column limits the move of the focused column")
    func alignedColumnLimitsFocusedColumn() throws {
        // The first column's divider at 0.5 is aligned with the second column's divider at 0.5.
        // The second column's lower cell is 0.12 high, so the whole move is shortened to 0.02.
        let layout = TileLayout(columns: [
            Self.column(0.5, [0.5, 0.5]),
            Self.column(0.5, [0.5, 0.12, 0.38]),
        ])
        let moved = try #require(Self.plan(layout, cell: 0, .down))
        #expect(Self.isClose(moved, TileLayout(columns: [
            Self.column(0.5, [0.52, 0.48]),
            Self.column(0.5, [0.52, 0.10, 0.38]),
        ])))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("an aligned column at the minimum blocks the move of the focused column")
    func alignedColumnBlocksMove() {
        let layout = TileLayout(columns: [
            Self.column(0.5, [0.5, 0.5]),
            Self.column(0.5, [0.5, 0.1, 0.4]),
        ])
        #expect(Self.plan(layout, cell: 0, .down) == nil)
    }

    // MARK: Transposition

    /// Layouts for the property below: column-first grids and hand-built column layouts.
    static let layouts: [TileLayout] = ColumnLayoutSupport.gridExamples.map(\.layout) + [
        ColumnLayoutSupport.handBuilt,
        TileLayout(columns: [
            TileLayout.Column(width: 0.5, heights: [0.5, 0.5]),
            TileLayout.Column(width: 0.5, heights: [0.25, 0.25, 0.5]),
        ]),
        TileLayout(columns: [
            TileLayout.Column(width: 0.88, heights: [0.12, 0.88]),
            TileLayout.Column(width: 0.12, heights: [1]),
        ]),
    ]

    /// `left` and `up` swap, and `right` and `down` swap.
    private static func transposed(_ direction: Direction) -> Direction {
        switch direction {
        case .left: .up
        case .up: .left
        case .right: .down
        case .down: .right
        }
    }

    @Test("every move on a column layout is the transposed move on its transposed row layout", arguments: layouts)
    func planIsTheTransposedPlan(layout: TileLayout) {
        for cell in -1...layout.windowCount {
            for direction in Direction.allCases {
                let direct = DividerMove.plan(
                    layout: layout, focusedCell: cell, direction: direction, step: Self.step)
                let viaRows = DividerMove.plan(
                    layout: layout.transposed, focusedCell: cell,
                    direction: Self.transposed(direction), step: Self.step)?.transposed
                #expect(direct == viaRows, "cell \(cell), \(direction)")
                if let direct {
                    #expect(direct.orientation == .columns)
                    #expect(LinkedResizeSupport.isValid(direct))
                }
            }
        }
    }

    // MARK: Preconditions

    @Test("a step of zero is a precondition failure")
    func stepPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = DividerMove.plan(
                layout: TileLayout.grid(windowCount: 2, rows: 2, columns: 1, fillOrder: .columns),
                focusedCell: 0, direction: .down, step: 0)
        }
    }

    @Test("a minimum of zero is a precondition failure")
    func minimumPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = DividerMove.plan(
                layout: TileLayout.grid(windowCount: 2, rows: 2, columns: 1, fillOrder: .columns),
                focusedCell: 0, direction: .down, step: 0.05, minimumFraction: 0)
        }
    }
}
