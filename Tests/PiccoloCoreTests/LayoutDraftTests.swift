import CoreGraphics
import Foundation
import Testing

@testable import PiccoloCore

// The values the presets use for a third and two thirds, which snapping gives back exactly.
private let third = 1.0 / 3.0
private let twoThirds = 2.0 / 3.0

/// The rules of the sheet that creates and edits custom areas and grids: snapping, the drag on the picture
/// of the screen, and the cell picker of a grid. Exact values, on purpose.
@Suite("Layout draft")
struct LayoutDraftTests {
    // MARK: Snapping

    @Test("a fraction snaps to the nearest 0.05", arguments: [
        (0.0, 0.0), (0.01, 0.0), (0.024, 0.0), (0.03, 0.05), (0.05, 0.05), (0.12, 0.1), (0.18, 0.2),
        (0.3, 0.3), (0.31, 0.3), (0.5, 0.5), (0.53, 0.55), (0.6, 0.6), (0.7, 0.7), (0.97, 0.95),
        (0.98, 1.0), (1.0, 1.0),
    ])
    func stepOfFiveHundredths(value: Double, expected: Double) {
        #expect(LayoutDraft.snap(value) == expected)
    }

    @Test("within 0.02 of a third or two thirds it snaps to the third", arguments: [
        (0.32, third), (0.3333, third), (0.34, third), (0.35, third), (0.3533, third),
        (0.65, twoThirds), (0.66, twoThirds), (0.68, twoThirds), (0.6866, twoThirds),
    ])
    func thirds(value: Double, expected: Double) {
        #expect(LayoutDraft.snap(value) == expected)
    }

    @Test("just outside 0.02 of a third it snaps to the nearest 0.05", arguments: [
        (0.3, 0.3), (0.31, 0.3), (0.36, 0.35), (0.3555, 0.35), (0.64, 0.65), (0.69, 0.7), (0.7, 0.7),
    ])
    func outsideThirds(value: Double, expected: Double) {
        #expect(LayoutDraft.snap(value) == expected)
    }

    @Test("the thirds are the same Double values as the presets use")
    func thirdsAreThePresets() {
        #expect(LayoutDraft.snap(0.34) == Preset.centerThird.fractionalRect?.x)
        #expect(LayoutDraft.snap(0.66) == Preset.rightThird.fractionalRect?.x)
    }

    @Test("with the free flag a fraction snaps to the nearest 0.01 and not to the thirds", arguments: [
        (0.334, 0.33), (0.3333, 0.33), (0.338, 0.34), (0.5, 0.5), (0.504, 0.5), (0.506, 0.51), (0.613, 0.61),
        (0.0, 0.0), (0.004, 0.0), (1.0, 1.0), (0.996, 1.0),
    ])
    func free(value: Double, expected: Double) {
        #expect(LayoutDraft.snap(value, free: true) == expected)
    }

    @Test("a fraction outside 0...1 snaps to 0 or 1, and zero is never negative")
    func clamped() {
        #expect(LayoutDraft.snap(-0.4) == 0)
        #expect(LayoutDraft.snap(1.7) == 1)
        #expect(LayoutDraft.snap(-0.4, free: true) == 0)
        #expect(LayoutDraft.snap(1.7, free: true) == 1)
        #expect(LayoutDraft.snap(-0.001, free: true).sign == .plus)
        #expect(LayoutDraft.snap(-0.001).sign == .plus)
    }

    // MARK: Drawing an area

    private static let area = FractionalRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    private func drag(
        from start: (Double, Double), to current: (Double, Double), area: FractionalRect = LayoutDraftTests.area,
        free: Bool = false
    ) -> FractionalRect? {
        LayoutDraft.areaAfterDrag(
            from: CGPoint(x: start.0, y: start.1), to: CGPoint(x: current.0, y: current.1),
            startingWith: area, free: free)
    }

    @Test("a drag that starts outside the area draws a new one from the snapped start to the snapped point")
    func drawsANewArea() {
        #expect(drag(from: (0.05, 0.05), to: (0.18, 0.31)) == FractionalRect(x: 0.05, y: 0.05, width: 0.15, height: 0.25))
        #expect(drag(from: (0.01, 0.01), to: (0.34, 0.66)) == FractionalRect(x: 0, y: 0, width: third, height: twoThirds))
    }

    @Test("an area can be drawn in any direction")
    func anyDirection() {
        // Right to left and bottom to top.
        #expect(drag(from: (0.9, 0.9), to: (0.8, 0.7)) == FractionalRect(x: 0.8, y: 0.7, width: 0.1, height: 0.2))
        // Right to left, top to bottom.
        #expect(drag(from: (0.95, 0.1), to: (0.8, 0.2)) == FractionalRect(x: 0.8, y: 0.1, width: 0.15, height: 0.1))
        // Left to right, bottom to top.
        #expect(drag(from: (0.1, 0.95), to: (0.2, 0.8)) == FractionalRect(x: 0.1, y: 0.8, width: 0.1, height: 0.15))
    }

    @Test("the sides are exact decimals, not the noise of subtracting two snapped points")
    func noNoise() {
        let rect = drag(from: (0.05, 0.3), to: (0.2, 0.55))
        #expect(rect?.width == 0.15)
        #expect(rect?.height == 0.25)
        #expect(rect?.x == 0.05)
        #expect(rect?.y == 0.3)
    }

    @Test("points outside the picture count as its edge")
    func pointsAreClamped() {
        #expect(drag(from: (-0.3, -2), to: (1.5, 3)) == FractionalRect(x: 0, y: 0, width: 1, height: 1))
        #expect(drag(from: (0.9, 0.9), to: (1.4, 1.2)) == FractionalRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1))
    }

    @Test("a drawn area is ignored while a side is under 0.05")
    func tooSmall() {
        // Both points snap to 0.05.
        #expect(drag(from: (0.05, 0.05), to: (0.07, 0.5)) == nil)
        #expect(drag(from: (0.05, 0.05), to: (0.5, 0.06)) == nil)
        #expect(drag(from: (0.05, 0.05), to: (0.05, 0.05)) == nil)
        // Free: 0.03 is under the limit, 0.05 is not.
        #expect(drag(from: (0.05, 0.05), to: (0.08, 0.5), free: true) == nil)
        #expect(drag(from: (0.05, 0.05), to: (0.5, 0.08), free: true) == nil)
        #expect(drag(from: (0.05, 0.05), to: (0.10, 0.5), free: true) == FractionalRect(x: 0.05, y: 0.05, width: 0.05, height: 0.45))
    }

    @Test("a side of exactly 0.05 is big enough, whatever the rounding of the subtraction says")
    func exactlyTheLimit() {
        // 0.35 - 0.30 is 0.04999999999999999 in floating point.
        let rect = drag(from: (0.3, 0.05), to: (0.35, 0.5), free: true)
        #expect(rect == FractionalRect(x: 0.3, y: 0.05, width: 0.05, height: 0.45))
        #expect(drag(from: (0.05, 0.3), to: (0.5, 0.35), free: true) == FractionalRect(x: 0.05, y: 0.3, width: 0.45, height: 0.05))
        // Without the flag, 0.35 snaps to a third, which is only 0.0333 from 0.3.
        #expect(drag(from: (0.3, 0.05), to: (0.35, 0.5)) == nil)
    }

    @Test("a drag that ends where it began draws nothing")
    func noDrag() {
        #expect(drag(from: (0.9, 0.9), to: (0.9, 0.9)) == nil)
    }

    // MARK: Moving the area

    @Test("a drag that starts inside the area moves it, keeping its size, snapped")
    func movesTheArea() {
        // 0.25 + 0.22 = 0.47 -> 0.45; 0.25 - 0.05 = 0.2.
        #expect(drag(from: (0.5, 0.5), to: (0.72, 0.45)) == FractionalRect(x: 0.45, y: 0.2, width: 0.5, height: 0.5))
        // 0.25 + 0.1 = 0.35 is within 0.02 of a third.
        #expect(drag(from: (0.5, 0.5), to: (0.6, 0.5)) == FractionalRect(x: third, y: 0.25, width: 0.5, height: 0.5))
        #expect(drag(from: (0.5, 0.5), to: (0.5, 0.7)) == FractionalRect(x: 0.25, y: 0.45, width: 0.5, height: 0.5))
    }

    @Test("moving with the free flag snaps to 0.01")
    func movesFree() {
        let moved = drag(from: (0.5, 0.5), to: (0.613, 0.5), free: true)
        #expect(moved == FractionalRect(x: 0.36, y: 0.25, width: 0.5, height: 0.5))
    }

    @Test("a moved area stays inside the screen")
    func movedAreaIsClamped() {
        #expect(drag(from: (0.5, 0.5), to: (1, 1)) == FractionalRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        #expect(drag(from: (0.5, 0.5), to: (0, 0)) == FractionalRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(drag(from: (0.5, 0.5), to: (3, -3)) == FractionalRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        let tall = FractionalRect(x: 0, y: 0, width: third, height: 1)
        let moved = drag(from: (0.1, 0.5), to: (0.9, 0.9), area: tall)
        #expect(moved?.y == 0)
        #expect(moved?.height == 1)
        #expect(moved?.width == third)
        let x = moved?.x ?? -1
        #expect(abs(x - twoThirds) < 1e-12)
        #expect(x + third <= 1 + 1e-12)
    }

    @Test("the edge of the area is inside it")
    func edgeIsInside() {
        // The corner (0.25, 0.25) and the far corner (0.75, 0.75) are on the area: the drag moves it.
        #expect(drag(from: (0.25, 0.25), to: (0.35, 0.25)) == FractionalRect(x: third, y: 0.25, width: 0.5, height: 0.5))
        #expect(drag(from: (0.75, 0.75), to: (0.75, 0.85)) == FractionalRect(x: 0.25, y: third, width: 0.5, height: 0.5))
    }

    @Test("the start of the drag decides between drawing and moving, not the point it is now at")
    func startDecides() {
        // Starts outside, ends inside the old area: draws.
        #expect(drag(from: (0.05, 0.05), to: (0.5, 0.5)) == FractionalRect(x: 0.05, y: 0.05, width: 0.45, height: 0.45))
        // Starts inside, ends outside it: moves.
        #expect(drag(from: (0.5, 0.5), to: (0.05, 0.05)) == FractionalRect(x: 0, y: 0, width: 0.5, height: 0.5))
    }

    @Test("an area with no size has no inside, so a drag draws")
    func emptyAreaHasNoInside() {
        let empty = FractionalRect(x: 0.25, y: 0.25, width: 0, height: 0)
        #expect(drag(from: (0.25, 0.25), to: (0.5, 0.5), area: empty) == FractionalRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
        let negative = FractionalRect(x: 0.25, y: 0.25, width: -0.1, height: 0.5)
        #expect(drag(from: (0.2, 0.3), to: (0.5, 0.6), area: negative) == FractionalRect(x: 0.2, y: 0.3, width: 0.3, height: 0.3))
    }

    // MARK: The grid picker

    @Test("picking a cell sets rows, columns and windows")
    func picking() {
        #expect(LayoutDraft.grid(pickingRow: 0, column: 0) == GridSpec(count: 1, rows: 1, columns: 1))
        #expect(LayoutDraft.grid(pickingRow: 1, column: 1) == GridSpec(count: 4, rows: 2, columns: 2))
        #expect(LayoutDraft.grid(pickingRow: 2, column: 3) == GridSpec(count: 12, rows: 3, columns: 4))
        #expect(LayoutDraft.grid(pickingRow: 0, column: 7) == GridSpec(count: 8, rows: 1, columns: 8))
        #expect(LayoutDraft.grid(pickingRow: 7, column: 7) == GridSpec(count: 64, rows: 8, columns: 8))
    }

    @Test("the windows of a grid are between 1 and rows times columns")
    func windowRange() {
        #expect(LayoutDraft.windowRange(rows: 2, columns: 2) == 1...4)
        #expect(LayoutDraft.windowRange(rows: 1, columns: 1) == 1...1)
        #expect(LayoutDraft.windowRange(rows: 8, columns: 8) == 1...64)
        // A grid that cannot be, so the stepper has nothing to do.
        #expect(LayoutDraft.windowRange(rows: 0, columns: 3) == 1...1)
        #expect(LayoutDraft.windowRange(rows: Int.max, columns: Int.max) == 1...Int.max)
    }

    @Test("the stepper moves the windows by one and stays within the range")
    func stepper() {
        let grid = GridSpec(count: 3, rows: 2, columns: 2)
        #expect(LayoutDraft.grid(grid, windowsBy: 1) == GridSpec(count: 4, rows: 2, columns: 2))
        #expect(LayoutDraft.grid(grid, windowsBy: -1) == GridSpec(count: 2, rows: 2, columns: 2))
        #expect(LayoutDraft.grid(GridSpec(count: 4, rows: 2, columns: 2), windowsBy: 1) == GridSpec(count: 4, rows: 2, columns: 2))
        #expect(LayoutDraft.grid(GridSpec(count: 1, rows: 2, columns: 2), windowsBy: -1) == GridSpec(count: 1, rows: 2, columns: 2))
        #expect(LayoutDraft.grid(grid, windowsBy: 100) == GridSpec(count: 4, rows: 2, columns: 2))
        #expect(LayoutDraft.grid(grid, windowsBy: -100) == GridSpec(count: 1, rows: 2, columns: 2))
    }

    // MARK: A new layout

    @Test("a new custom area is 25%, 25%, 50% by 50% and a new grid is 4 windows in 2 by 2")
    func newLayouts() {
        #expect(LayoutDraft.newArea == FractionalRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(LayoutDraft.newGrid == GridSpec(count: 4, rows: 2, columns: 2))
    }
}
