import Testing

@testable import PiccoloCore

/// `SwapNeighbor.neighbor(of:direction:in:)`: the cell a swap trades places with.
@Suite("Swap neighbour")
struct SwapNeighborTests {
    private typealias Row = TileLayout.Row

    private static func neighbor(_ cell: Int, _ direction: Direction, _ layout: TileLayout) -> Int? {
        SwapNeighbor.neighbor(of: cell, direction: direction, in: layout)
    }

    // MARK: Side by side and stacked

    @Test("1 × 2: left and right swap, up and down have no neighbour")
    func oneByTwo() {
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2)

        #expect(Self.neighbor(0, .right, layout) == 1)
        #expect(Self.neighbor(1, .left, layout) == 0)
        #expect(Self.neighbor(0, .left, layout) == nil)
        #expect(Self.neighbor(1, .right, layout) == nil)
        for cell in 0...1 {
            #expect(Self.neighbor(cell, .up, layout) == nil)
            #expect(Self.neighbor(cell, .down, layout) == nil)
        }
    }

    @Test("1 × 3: the middle window has a neighbour on both sides")
    func oneByThree() {
        let layout = TileLayout.grid(windowCount: 3, rows: 1, columns: 3)

        #expect(Self.neighbor(1, .left, layout) == 0)
        #expect(Self.neighbor(1, .right, layout) == 2)
        #expect(Self.neighbor(0, .left, layout) == nil)
        #expect(Self.neighbor(2, .right, layout) == nil)
        #expect(Self.neighbor(0, .right, layout) == 1)
        #expect(Self.neighbor(2, .left, layout) == 1)
    }

    @Test("2 × 1 and 3 × 1: stacked windows swap up and down")
    func stacked() {
        let two = TileLayout.grid(windowCount: 2, rows: 2, columns: 1)
        #expect(Self.neighbor(0, .down, two) == 1)
        #expect(Self.neighbor(1, .up, two) == 0)
        #expect(Self.neighbor(0, .up, two) == nil)
        #expect(Self.neighbor(0, .left, two) == nil)
        #expect(Self.neighbor(1, .right, two) == nil)

        let three = TileLayout.grid(windowCount: 3, rows: 3, columns: 1)
        #expect(Self.neighbor(1, .up, three) == 0)
        #expect(Self.neighbor(1, .down, three) == 2)
    }

    // MARK: Grids

    @Test("2 × 2: every direction from every cell")
    func twoByTwo() {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2)
        // Cells: 0 1 / 2 3. For each cell: left, right, up, down.
        let expected: [[Direction: Int?]] = [
            [.left: nil, .right: 1, .up: nil, .down: 2],
            [.left: 0, .right: nil, .up: nil, .down: 3],
            [.left: nil, .right: 3, .up: 0, .down: nil],
            [.left: 2, .right: nil, .up: 1, .down: nil],
        ]
        for (cell, row) in expected.enumerated() {
            for direction in Direction.allCases {
                #expect(
                    Self.neighbor(cell, direction, layout) == row[direction]!,
                    "cell \(cell) \(direction)")
            }
        }
    }

    @Test("3 windows in 2 × 2, rows first: the wide bottom cell goes up to cell 0 by the tie rule")
    func threeRowsFirst() {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2)

        #expect(Self.neighbor(2, .up, layout) == 0)
        #expect(Self.neighbor(1, .down, layout) == 2)
        #expect(Self.neighbor(0, .down, layout) == 2)
        #expect(Self.neighbor(2, .left, layout) == nil)
        #expect(Self.neighbor(2, .right, layout) == nil)
        #expect(Self.neighbor(2, .down, layout) == nil)
        #expect(Self.neighbor(0, .right, layout) == 1)
        #expect(Self.neighbor(1, .left, layout) == 0)
    }

    @Test("3 windows in 2 × 2, columns first: the tall right cell goes left to cell 0 by the tie rule")
    func threeColumnsFirst() {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns)

        #expect(Self.neighbor(0, .right, layout) == 2)
        #expect(Self.neighbor(1, .right, layout) == 2)
        #expect(Self.neighbor(2, .left, layout) == 0)
        #expect(Self.neighbor(0, .down, layout) == 1)
        #expect(Self.neighbor(1, .up, layout) == 0)
        #expect(Self.neighbor(2, .up, layout) == nil)
        #expect(Self.neighbor(2, .down, layout) == nil)
        #expect(Self.neighbor(0, .left, layout) == nil)
    }

    @Test("2 × 2 columns first: cells are numbered column by column, and the directions are the screen's")
    func twoByTwoColumnsFirst() {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2, fillOrder: .columns)
        // Cells: 0 2 / 1 3.
        #expect(Self.neighbor(0, .right, layout) == 2)
        #expect(Self.neighbor(0, .down, layout) == 1)
        #expect(Self.neighbor(3, .left, layout) == 1)
        #expect(Self.neighbor(3, .up, layout) == 2)
        #expect(Self.neighbor(1, .right, layout) == 3)
        #expect(Self.neighbor(2, .down, layout) == 3)
    }

    // MARK: Dividers that no longer line up

    @Test("a 2 × 2 row layout after a divider move: the longest shared stretch of the edge wins")
    func unalignedDividers() {
        // The top row is split at 0.6 / 0.4, the bottom row at 0.5 / 0.5.
        let layout = TileLayout(rows: [
            Row(height: 0.5, widths: [0.6, 0.4]),
            Row(height: 0.5, widths: [0.5, 0.5]),
        ])

        // Cell 1 (0.6 to 1.0) sits over cell 3 (0.5 to 1.0) and shares nothing with cell 2 (0 to 0.5).
        #expect(Self.neighbor(1, .down, layout) == 3)
        // Cell 2 (0 to 0.5) is under cell 0 (0 to 0.6) only.
        #expect(Self.neighbor(2, .up, layout) == 0)
        // Cell 3 (0.5 to 1.0) shares 0.4 with cell 1 and 0.1 with cell 0.
        #expect(Self.neighbor(3, .up, layout) == 1)
        // Cell 0 (0 to 0.6) shares 0.5 with cell 2 and 0.1 with cell 3.
        #expect(Self.neighbor(0, .down, layout) == 2)
    }

    @Test("left and right do not skip over a window: a cell with a different row is no neighbour")
    func differentRows() {
        // Row 0 has three cells, row 1 has one. Cell 3 (the wide one) has no left or right neighbour.
        let layout = TileLayout(rows: [
            Row(height: 0.5, widths: [0.2, 0.3, 0.5]),
            Row(height: 0.5, widths: [1]),
        ])
        #expect(Self.neighbor(3, .left, layout) == nil)
        #expect(Self.neighbor(3, .right, layout) == nil)
        // Going up from the wide cell: the widest cell above (cell 2, half the width).
        #expect(Self.neighbor(3, .up, layout) == 2)
        #expect(Self.neighbor(1, .right, layout) == 2)
    }

    // MARK: Out of range

    @Test("a cell outside the layout has no neighbour")
    func outOfRange() {
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2)
        for direction in Direction.allCases {
            #expect(Self.neighbor(2, direction, layout) == nil)
            #expect(Self.neighbor(99, direction, layout) == nil)
            #expect(Self.neighbor(-1, direction, layout) == nil)
        }
    }

    @Test("a single window has no neighbour")
    func singleWindow() {
        let layout = TileLayout.grid(windowCount: 1, rows: 1, columns: 1)
        for direction in Direction.allCases {
            #expect(Self.neighbor(0, direction, layout) == nil)
        }
    }

    @Test("the answer does not depend on the display: it is the same for any layout the fractions describe")
    func fractionsOnly() {
        // 0.7 / 0.3 and 0.3 / 0.7 rows: whole points do not matter, the order of the edges does.
        let layout = TileLayout(rows: [
            Row(height: 1.0 / 3, widths: [0.7, 0.3]),
            Row(height: 2.0 / 3, widths: [0.3, 0.7]),
        ])
        // Cell 0 is 0 to 0.7 and cell 3 is 0.3 to 1.0: they share 0.4. Cell 2 is 0 to 0.3: it shares 0.3.
        #expect(Self.neighbor(0, .down, layout) == 3)
        // Cell 1 (0.7 to 1.0) is over cell 3 only.
        #expect(Self.neighbor(1, .down, layout) == 3)
        // Cell 2 (0 to 0.3) is under cell 0 only.
        #expect(Self.neighbor(2, .up, layout) == 0)
    }
}
