import Foundation
import Testing

@testable import PiccoloCore

@Suite("TileLayout grid")
struct TileLayoutGridTests {
    typealias Example = TileLayoutSupport.GridExample

    @Test("cells per row follow the fill rule", arguments: TileLayoutSupport.gridExamples)
    func cellsPerRow(example: Example) {
        let layout = example.layout
        #expect(layout.rows.map { $0.widths.count } == example.cellsPerRow)
        #expect(layout.rows.count == example.cellsPerRow.count)
    }

    @Test("the layout holds one window per cell", arguments: TileLayoutSupport.gridExamples)
    func windowCount(example: Example) {
        #expect(example.layout.windowCount == example.cellsPerRow.reduce(0, +))
    }

    @Test(
        "used rows have equal heights, and the cells in a row have equal widths",
        arguments: TileLayoutSupport.gridExamples)
    func equalFractions(example: Example) {
        let layout = example.layout
        let usedRows = example.cellsPerRow.count
        for row in layout.rows {
            #expect(row.height == 1 / Double(usedRows))
            for width in row.widths {
                #expect(width == 1 / Double(row.widths.count))
            }
        }
    }

    @Test("a grid that is smaller than its capacity fills only the first cells")
    func partialGridUsesFirstCells() {
        // 3 windows in a 2x2 grid: the second row holds one window, which takes the full width.
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2)
        #expect(layout.rows == [
            TileLayout.Row(height: 0.5, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.5, widths: [1]),
        ])
    }

    @Test("a huge grid does not overflow when computing its capacity")
    func hugeGrid() {
        let layout = TileLayout.grid(windowCount: 5, rows: Int.max, columns: Int.max)
        #expect(layout.rows == [TileLayout.Row(height: 1, widths: [0.2, 0.2, 0.2, 0.2, 0.2])])
    }

    @Test("windowCount below 1 is a precondition failure")
    func windowCountPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = TileLayout.grid(windowCount: 0, rows: 2, columns: 2)
        }
    }

    @Test("rows below 1 is a precondition failure")
    func rowsPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = TileLayout.grid(windowCount: 1, rows: 0, columns: 2)
        }
    }

    @Test("columns below 1 is a precondition failure")
    func columnsPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = TileLayout.grid(windowCount: 1, rows: 2, columns: 0)
        }
    }
}

@Suite("TileLayout coding")
struct TileLayoutCodingTests {
    private func roundTrip(_ layout: TileLayout) throws -> TileLayout {
        try JSONDecoder().decode(TileLayout.self, from: JSONEncoder().encode(layout))
    }

    @Test("a built grid survives a round trip", arguments: TileLayoutSupport.gridExamples)
    func gridRoundTrip(example: TileLayoutSupport.GridExample) throws {
        #expect(try roundTrip(example.layout) == example.layout)
    }

    @Test("a hand-built layout with unequal fractions survives a round trip")
    func handBuiltRoundTrip() throws {
        #expect(try roundTrip(TileLayoutSupport.handBuilt) == TileLayoutSupport.handBuilt)
    }
}
