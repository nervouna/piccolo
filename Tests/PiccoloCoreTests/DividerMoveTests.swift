import Testing

@testable import PiccoloCore

/// One move of a table: the focused cell, the key, and the fractions the move gives.
struct DividerMoveCase: Sendable, CustomTestStringConvertible {
    let name: String
    let focusedCell: Int
    let direction: Direction
    /// Widths (for left and right) or heights (for up and down) after the move.
    let fractions: [Double]

    var testDescription: String { name }
}

@Suite("Divider move")
struct DividerMoveTests {
    typealias Example = DividerMoveCase

    private static let step = LinkedResizeSupport.step

    // MARK: Side by side, left and right

    /// Three windows side by side, A | B | C, from three equal columns of 1/3 each, with a step
    /// of 0.05. The divider each key moves is the one the design in issue #8 gives:
    ///
    ///     focused  key    divider moved       widths after
    ///     A        left   A|B by -0.05        [1/3 - 0.05, 1/3 + 0.05, 1/3]
    ///     A        right  A|B by +0.05        [1/3 + 0.05, 1/3 - 0.05, 1/3]
    ///     B        left   A|B by -0.05        [1/3 - 0.05, 1/3 + 0.05, 1/3]
    ///     B        right  B|C by +0.05        [1/3, 1/3 + 0.05, 1/3 - 0.05]
    ///     C        left   B|C by -0.05        [1/3, 1/3 - 0.05, 1/3 + 0.05]
    ///     C        right  B|C by +0.05        [1/3, 1/3 + 0.05, 1/3 - 0.05]
    ///
    /// The expected widths are written out by hand below, not computed by the code under test.
    static let threeAcross: [Example] = [
        Example(
            name: "A left", focusedCell: 0, direction: .left,
            fractions: [1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05, 1.0 / 3.0]),
        Example(
            name: "A right", focusedCell: 0, direction: .right,
            fractions: [1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05, 1.0 / 3.0]),
        Example(
            name: "B left", focusedCell: 1, direction: .left,
            fractions: [1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05, 1.0 / 3.0]),
        Example(
            name: "B right", focusedCell: 1, direction: .right,
            fractions: [1.0 / 3.0, 1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05]),
        Example(
            name: "C left", focusedCell: 2, direction: .left,
            fractions: [1.0 / 3.0, 1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05]),
        Example(
            name: "C right", focusedCell: 2, direction: .right,
            fractions: [1.0 / 3.0, 1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05]),
    ]

    @Test("three windows side by side move the divider the design table gives", arguments: threeAcross)
    func threeAcrossTable(example: Example) throws {
        let layout = TileLayout(rows: [
            TileLayout.Row(height: 1, widths: [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
        ])
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: example.focusedCell,
            direction: example.direction, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved.rows[0].widths, example.fractions))
        #expect(moved.rows[0].height == 1)
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test(
        "two windows side by side: either window moves the one divider the same way",
        arguments: [
            Example(name: "first left", focusedCell: 0, direction: .left,
                    fractions: [0.5 - 0.05, 0.5 + 0.05]),
            Example(name: "first right", focusedCell: 0, direction: .right,
                    fractions: [0.5 + 0.05, 0.5 - 0.05]),
            Example(name: "second left", focusedCell: 1, direction: .left,
                    fractions: [0.5 - 0.05, 0.5 + 0.05]),
            Example(name: "second right", focusedCell: 1, direction: .right,
                    fractions: [0.5 + 0.05, 0.5 - 0.05]),
        ])
    func twoAcross(example: Example) throws {
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2)
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: example.focusedCell,
            direction: example.direction, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved.rows[0].widths, example.fractions))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    // MARK: Stacked, up and down

    /// Two windows stacked, one row each. Each key moves the one divider between the rows, in
    /// the key's direction, exactly as in the side by side case.
    static let twoStacked: [Example] = [
        Example(name: "top up", focusedCell: 0, direction: .up,
                fractions: [0.5 - 0.05, 0.5 + 0.05]),
        Example(name: "top down", focusedCell: 0, direction: .down,
                fractions: [0.5 + 0.05, 0.5 - 0.05]),
        Example(name: "bottom up", focusedCell: 1, direction: .up,
                fractions: [0.5 - 0.05, 0.5 + 0.05]),
        Example(name: "bottom down", focusedCell: 1, direction: .down,
                fractions: [0.5 + 0.05, 0.5 - 0.05]),
    ]

    @Test("two windows stacked: the top and bottom row move the divider in the key's direction",
          arguments: twoStacked)
    func twoStackedTable(example: Example) throws {
        let layout = TileLayout.grid(windowCount: 2, rows: 2, columns: 1)
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: example.focusedCell,
            direction: example.direction, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved.rows.map(\.height), example.fractions))
        #expect(moved.rows.allSatisfy { $0.widths == [1] })
        #expect(LinkedResizeSupport.isValid(moved))
    }

    /// Three windows stacked. The top row has no row above, so `up` moves its bottom edge; the
    /// bottom row has no row below, so `down` moves its top edge. Both give the table of the
    /// side by side case, with heights in place of widths.
    static let threeStacked: [Example] = [
        Example(name: "top up", focusedCell: 0, direction: .up,
                fractions: [1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05, 1.0 / 3.0]),
        Example(name: "top down", focusedCell: 0, direction: .down,
                fractions: [1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05, 1.0 / 3.0]),
        Example(name: "middle up", focusedCell: 1, direction: .up,
                fractions: [1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05, 1.0 / 3.0]),
        Example(name: "middle down", focusedCell: 1, direction: .down,
                fractions: [1.0 / 3.0, 1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05]),
        Example(name: "bottom up", focusedCell: 2, direction: .up,
                fractions: [1.0 / 3.0, 1.0 / 3.0 - 0.05, 1.0 / 3.0 + 0.05]),
        Example(name: "bottom down", focusedCell: 2, direction: .down,
                fractions: [1.0 / 3.0, 1.0 / 3.0 + 0.05, 1.0 / 3.0 - 0.05]),
    ]

    @Test("three windows stacked: the top and the bottom row move their edges", arguments: threeStacked)
    func threeStackedTable(example: Example) throws {
        let layout = TileLayout.grid(windowCount: 3, rows: 3, columns: 1)
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: example.focusedCell,
            direction: example.direction, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved.rows.map(\.height), example.fractions))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("up and down leave every width alone, and the rows of a grid keep their own widths")
    func verticalMovesKeepWidths() throws {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2)
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .down, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.55, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.45, widths: [0.5, 0.5]),
        ])))
    }

    // MARK: Grids and alignment

    @Test("2x2: the vertical divider of the top-left cell moves the bottom row's divider too")
    func twoByTwoAlignedDivider() throws {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2)
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.55, 0.45]),
            TileLayout.Row(height: 0.5, widths: [0.55, 0.45]),
        ])))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("2x2: a key from the bottom-right cell moves the aligned divider of both rows left")
    func twoByTwoAlignedFromBottomRight() throws {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2)
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 3, direction: .left, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.45, 0.55]),
            TileLayout.Row(height: 0.5, widths: [0.45, 0.55]),
        ])))
    }

    @Test("3 in 2x2: the bottom row has no divider, so it does not move")
    func threeInTwoByTwoBottomRowStays() throws {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2)
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.55, 0.45]),
            TileLayout.Row(height: 0.5, widths: [1]),
        ])))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("an aligned divider in another row moves even when it has a different index there")
    func alignedDividerAtOtherIndex() throws {
        // The top divider sits at 0.5. In the bottom row the same position is its second divider.
        let layout = TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.5, widths: [0.25, 0.25, 0.5]),
        ])
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.55, 0.45]),
            TileLayout.Row(height: 0.5, widths: [0.25, 0.3, 0.45]),
        ])))
    }

    @Test("a divider counts as aligned when its position matches within 1e-9, not exactly")
    func alignedWithinTolerance() throws {
        // 0.1 + 0.2 is 0.30000000000000004 in floating point, not 0.3.
        let layout = TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.3, 0.7]),
            TileLayout.Row(height: 0.5, widths: [0.1, 0.2, 0.7]),
        ])
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.35, 0.65]),
            TileLayout.Row(height: 0.5, widths: [0.1, 0.25, 0.65]),
        ])))
    }

    @Test("a divider that differs by more than 1e-9 is not aligned, and the row does not move")
    func notAlignedBeyondTolerance() throws {
        let layout = TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.5, widths: [0.500001, 0.499999]),
        ])
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.55, 0.45]),
            TileLayout.Row(height: 0.5, widths: [0.500001, 0.499999]),
        ])))
    }

    @Test("a row with no aligned divider does not limit the move, even when it is narrow")
    func unalignedRowDoesNotLimit() throws {
        // The bottom row's narrow cell is 0.12 wide, but its dividers sit at 0.42 and 0.54, not at 0.5.
        let layout = TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.5, widths: [0.42, 0.12, 0.46]),
        ])
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.55, 0.45]),
            TileLayout.Row(height: 0.5, widths: [0.42, 0.12, 0.46]),
        ])))
    }

    // MARK: Nothing moves

    @Test("a single cell moves nothing in any direction", arguments: Direction.allCases)
    func singleCell(direction: Direction) {
        let layout = TileLayout.grid(windowCount: 1, rows: 1, columns: 1)
        #expect(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: direction, step: Self.step) == nil)
    }

    @Test("a single row moves nothing up or down", arguments: [Direction.up, .down])
    func singleRowVertical(direction: Direction) {
        let layout = TileLayout.grid(windowCount: 3, rows: 1, columns: 3)
        #expect(DividerMove.plan(
            layout: layout, focusedCell: 1, direction: direction, step: Self.step) == nil)
    }

    @Test("a single column moves nothing left or right", arguments: [Direction.left, .right])
    func singleColumnHorizontal(direction: Direction) {
        let layout = TileLayout.grid(windowCount: 3, rows: 3, columns: 1)
        #expect(DividerMove.plan(
            layout: layout, focusedCell: 1, direction: direction, step: Self.step) == nil)
    }

    @Test("a window alone in its row has no vertical divider to move")
    func aloneInRowHasNoVerticalDivider() throws {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2)
        #expect(DividerMove.plan(
            layout: layout, focusedCell: 2, direction: .left, step: Self.step) == nil)
        #expect(DividerMove.plan(
            layout: layout, focusedCell: 2, direction: .right, step: Self.step) == nil)
        // Its row still has a horizontal divider above it.
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 2, direction: .up, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved.rows.map(\.height), [0.45, 0.55]))
    }

    @Test("a focused cell outside the layout moves nothing")
    func cellOutsideLayout() {
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2)
        #expect(DividerMove.plan(layout: layout, focusedCell: 2, direction: .right, step: Self.step) == nil)
        #expect(DividerMove.plan(layout: layout, focusedCell: -1, direction: .left, step: Self.step) == nil)
    }

    // MARK: Limits

    @Test("a move that would take a cell below the minimum is shortened to the room left")
    func shortenedToRoom() throws {
        // B is 0.12 wide. Shrinking it by the full step would leave 0.07, below 0.1.
        let layout = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.88, 0.12])])
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved.rows[0].widths, [0.88 + 0.02, 0.12 - 0.02]))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("a shortened move on the other side, and in the other direction")
    func shortenedLeft() throws {
        let layout = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.12, 0.88])])
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 1, direction: .left, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved.rows[0].widths, [0.12 - 0.02, 0.88 + 0.02]))
    }

    @Test("a move that has no room at all is nil")
    func blockedSideBySide() {
        let right = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.9, 0.1])])
        #expect(DividerMove.plan(layout: right, focusedCell: 0, direction: .right, step: Self.step) == nil)
        let left = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.1, 0.9])])
        #expect(DividerMove.plan(layout: left, focusedCell: 1, direction: .left, step: Self.step) == nil)
    }

    @Test("a stacked move shortened by the row it shrinks, and blocked when that row is at the minimum")
    func stackedLimits() throws {
        let shortened = TileLayout(rows: [
            TileLayout.Row(height: 0.12, widths: [1]),
            TileLayout.Row(height: 0.88, widths: [1]),
        ])
        let moved = try #require(DividerMove.plan(
            layout: shortened, focusedCell: 1, direction: .up, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved.rows.map(\.height), [0.12 - 0.02, 0.88 + 0.02]))

        let blocked = TileLayout(rows: [
            TileLayout.Row(height: 0.9, widths: [1]),
            TileLayout.Row(height: 0.1, widths: [1]),
        ])
        #expect(DividerMove.plan(layout: blocked, focusedCell: 0, direction: .down, step: Self.step) == nil)
    }

    @Test("an aligned row limits the move of the focused row")
    func alignedRowLimitsFocusedRow() throws {
        // The top divider at 0.5 is aligned with the bottom row's divider at 0.5. The bottom
        // row's right-hand cell is 0.12 wide, so the whole move is shortened to 0.02.
        let layout = TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.5, widths: [0.5, 0.12, 0.38]),
        ])
        let moved = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        #expect(LinkedResizeSupport.isClose(moved, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.52, 0.48]),
            TileLayout.Row(height: 0.5, widths: [0.52, 0.10, 0.38]),
        ])))
        #expect(LinkedResizeSupport.isValid(moved))
    }

    @Test("an aligned row at the minimum blocks the move of the focused row")
    func alignedRowBlocksMove() {
        let layout = TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.5, widths: [0.5, 0.1, 0.4]),
        ])
        #expect(DividerMove.plan(layout: layout, focusedCell: 0, direction: .right, step: Self.step) == nil)
    }

    // MARK: Preconditions

    @Test("a step of zero is a precondition failure")
    func stepPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = DividerMove.plan(
                layout: TileLayout.grid(windowCount: 2, rows: 1, columns: 2),
                focusedCell: 0, direction: .right, step: 0)
        }
    }

    @Test("a minimum of zero is a precondition failure")
    func minimumPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = DividerMove.plan(
                layout: TileLayout.grid(windowCount: 2, rows: 1, columns: 2),
                focusedCell: 0, direction: .right, step: 0.05, minimumFraction: 0)
        }
    }
}
