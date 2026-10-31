import CoreGraphics
import Testing

@testable import PiccoloCore

/// `LayoutGroup.swappingCells(_:_:)`: the group after two windows trade cells.
@Suite("Layout group: swapping cells")
struct LayoutGroupSwapTests {
    private static let visible = LinkedResizeSupport.visible

    private static func id(_ number: UInt32) -> WindowID { WindowID(rawValue: number) }

    @Test("two cells exchange their windows and the frames those windows were measured at")
    func exchangesWindowsAndFrames() {
        let group = LayoutGroupTests.twoByTwo()

        let swapped = group.swappingCells(0, 2)

        #expect(swapped.windows == [Self.id(3), Self.id(2), Self.id(1), Self.id(4)])
        #expect(swapped.frames == [group.frames[2], group.frames[1], group.frames[0], group.frames[3]])
    }

    @Test("the layout and the visible frame stay as they were")
    func keepsTheLayout() {
        let layout = TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.6, 0.4]),
            TileLayout.Row(height: 0.5, widths: [0.5, 0.5]),
        ])
        let group = LayoutGroup(
            layout: layout, windows: LinkedResizeSupport.windows(4), visibleFrame: Self.visible,
            frames: layout.frames(in: Self.visible))

        let swapped = group.swappingCells(1, 3)

        #expect(swapped.layout == layout)
        #expect(swapped.visibleFrame == Self.visible)
    }

    @Test("the order of the arguments does not matter")
    func symmetric() {
        let group = LayoutGroupTests.twoByTwo()
        #expect(group.swappingCells(1, 2) == group.swappingCells(2, 1))
    }

    @Test("swapping a cell with itself changes nothing")
    func sameCell() {
        let group = LayoutGroupTests.twoByTwo()
        #expect(group.swappingCells(3, 3) == group)
    }

    @Test("swapping twice gives the group back")
    func involution() {
        let group = LayoutGroupTests.twoByTwo()
        #expect(group.swappingCells(0, 3).swappingCells(0, 3) == group)
    }

    @Test("the windows are found in their new cells")
    func cellsFollow() {
        let swapped = LayoutGroupTests.twoByTwo().swappingCells(0, 1)

        #expect(swapped.cell(of: Self.id(1)) == 1)
        #expect(swapped.cell(of: Self.id(2)) == 0)
        #expect(swapped.cell(of: Self.id(3)) == 2)
    }

    @Test("a swapped group, recorded with its own layout, keeps the layout and takes the achieved frames")
    func recordAchievedAfterASwap() {
        // 60% | 40%: the windows trade cells and both reach their new cells.
        let layout = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.6, 0.4])])
        let group = LayoutGroup(
            layout: layout, windows: LinkedResizeSupport.windows(2), visibleFrame: Self.visible,
            frames: layout.frames(in: Self.visible))
        var swapped = group.swappingCells(0, 1)
        let cells = swapped.targetFrames(for: swapped.layout)

        swapped.recordAchieved(requested: swapped.layout, achieved: cells)

        #expect(swapped.windows == [Self.id(2), Self.id(1)])
        #expect(swapped.frames == cells)
        #expect(LinkedResizeSupport.isClose(swapped.layout, layout))
    }

    @Test("a window that refused the size of its new cell moves the divider to where it ended")
    func refusedSize() {
        let layout = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.6, 0.4])])
        let group = LayoutGroup(
            layout: layout, windows: LinkedResizeSupport.windows(2), visibleFrame: Self.visible,
            frames: layout.frames(in: Self.visible))
        var swapped = group.swappingCells(0, 1)
        var achieved = swapped.targetFrames(for: swapped.layout)
        // Window 1 is now in the 400 point cell on the right and cannot be narrower than 500: it is
        // shifted back to x = 500.
        achieved[1] = CGRect(x: 500, y: 0, width: 500, height: 500)

        swapped.recordAchieved(requested: swapped.layout, achieved: achieved)

        #expect(abs(swapped.layout.rows[0].widths[0] - 0.5) < 1e-9)
        #expect(swapped.frames == achieved)
    }
}
