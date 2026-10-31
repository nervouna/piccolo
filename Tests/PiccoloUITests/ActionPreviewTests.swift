import CoreGraphics
import Testing

import PiccoloCore

@testable import PiccoloUI

@Suite("Action preview")
struct ActionPreviewTests {
    private func rects(_ action: Action) -> [CGRect] {
        ActionPreview.rects(for: action) ?? []
    }

    @Test("a preset is drawn at its frame")
    func preset() {
        #expect(rects(.placeWindow(.preset(.leftHalf))) == [CGRect(x: 0, y: 0, width: 0.5, height: 1)])
        #expect(rects(.placeWindow(.preset(.bottomRight))) == [CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)])
        #expect(rects(.placeWindow(.preset(.maximize))) == [CGRect(x: 0, y: 0, width: 1, height: 1)])
    }

    @Test("every preset has a picture inside the screen")
    func allPresets() {
        for preset in Preset.allCases {
            let drawn = rects(.placeWindow(.preset(preset)))
            #expect(drawn.count == 1, "\(preset)")
            for rect in drawn {
                #expect(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -1e-9, dy: -1e-9).contains(rect), "\(preset)")
            }
        }
    }

    @Test("center keeps the window's size, so it is drawn as a centered half-size window")
    func center() {
        #expect(rects(.placeWindow(.preset(.center))) == [CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)])
    }

    @Test("a custom frame is drawn as it is")
    func custom() {
        let frame = FractionalRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(rects(.placeWindow(.custom(frame))) == [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)])
    }

    @Test("4 windows in 2 × 2 are four quarters, row by row")
    func fullGrid() {
        #expect(
            rects(.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))) == [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ])
    }

    @Test("3 windows in 2 × 2: the short last row stretches to the full width")
    func shortLastRow() {
        #expect(
            rects(.arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2))) == [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
            ])
    }

    @Test("3 windows in 2 × 2, columns first: the short last column stretches to the full height")
    func shortLastColumn() {
        #expect(
            ActionPreview.rects(for: .arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2)), fillOrder: .columns) == [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            ])
    }

    @Test("a full grid has the same cells in either fill order, and rows first is the default")
    func fillOrderOfAFullGrid() {
        let grid = Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))
        let rowsFirst = Set((ActionPreview.rects(for: grid, fillOrder: .rows) ?? []).map(\.debugDescription))
        let columnsFirst = Set((ActionPreview.rects(for: grid, fillOrder: .columns) ?? []).map(\.debugDescription))
        #expect(rowsFirst.count == 4)
        #expect(rowsFirst == columnsFirst)
        #expect(ActionPreview.rects(for: grid) == ActionPreview.rects(for: grid, fillOrder: .rows))
    }

    @Test("columns first with spare columns gives their width to the used ones")
    func spareColumns() {
        #expect(
            ActionPreview.rects(for: .arrangeGrid(GridSpec(count: 2, rows: 2, columns: 3)), fillOrder: .columns) == [
                CGRect(x: 0, y: 0, width: 1, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
            ])
    }

    @Test("a fill order changes nothing for a frame")
    func fillOrderOfAFrame() {
        let frame = Action.placeWindow(.preset(.topRight))
        #expect(ActionPreview.rects(for: frame, fillOrder: .columns) == ActionPreview.rects(for: frame, fillOrder: .rows))
    }

    @Test("a grid with spare rows gives their height to the used ones")
    func spareRows() {
        #expect(
            rects(.arrangeGrid(GridSpec(count: 2, rows: 3, columns: 2))) == [
                CGRect(x: 0, y: 0, width: 0.5, height: 1),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            ])
    }

    @Test("an impossible grid has no picture instead of crashing")
    func impossibleGrid() {
        #expect(ActionPreview.rects(for: .arrangeGrid(GridSpec(count: 0, rows: 2, columns: 2))) == nil)
        #expect(ActionPreview.rects(for: .arrangeGrid(GridSpec(count: 2, rows: 0, columns: 2))) == nil)
        #expect(ActionPreview.rects(for: .arrangeGrid(GridSpec(count: 2, rows: 2, columns: 0))) == nil)
    }

    @Test("display moves, divider moves and swaps have no picture")
    func noPicture() {
        #expect(ActionPreview.rects(for: .moveToDisplay(.next)) == nil)
        #expect(ActionPreview.rects(for: .moveDivider(.left)) == nil)
        #expect(ActionPreview.rects(for: .swapWindow(.left)) == nil)
    }
}
