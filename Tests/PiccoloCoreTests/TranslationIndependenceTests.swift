import CoreGraphics
import Testing

@testable import PiccoloCore

/// Moving the visible frame by a whole-point offset must move every resolved frame by exactly
/// that offset. A rounding rule that depends on the sign of a coordinate breaks this at
/// half-point boundaries, so the sizes below are the ones whose edges fall on halves.
@Suite("Translation independence")
struct TranslationIndependenceTests {
    /// 1727x1085 has half-point edges in both directions. 1440x875 is the primary display's
    /// visible size, which also has them vertically.
    static let sizes = [CGSize(width: 1727, height: 1085), CGSize(width: 1440, height: 875)]

    /// Whole-point offsets. The last two move the visible frame to negative coordinates.
    static let offsets = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: -1728, y: 355),
        CGPoint(x: 1440, y: -900),
        CGPoint(x: -3001, y: -777),
    ]

    /// Every preset, and custom rects with edges on half points.
    static let specs: [FrameSpec] = Preset.allCases.map { FrameSpec.preset($0) } + [
        .custom(FractionalRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
        .custom(FractionalRect(x: 0.125, y: 0.25, width: 0.5, height: 0.375)),
        .custom(FractionalRect(x: 0.2, y: 0.1, width: 0.45, height: 0.6)),
    ]

    /// Only `.center` reads the current frame, and only its size.
    static let currentFrame = CGRect(x: 0, y: 0, width: 800, height: 600)

    static let grids = [
        TileLayout.grid(windowCount: 4, rows: 2, columns: 2),
        TileLayout.grid(windowCount: 3, rows: 2, columns: 2),
        TileLayout.grid(windowCount: 5, rows: 2, columns: 3),
    ]

    @Test("every preset and custom rect moves with the visible frame", arguments: sizes, offsets)
    func specsShift(size: CGSize, offset: CGPoint) {
        let base = CGRect(origin: .zero, size: size)
        let moved = base.offsetBy(dx: offset.x, dy: offset.y)
        for spec in Self.specs {
            let expected = FrameResolver
                .frame(for: spec, visibleFrame: base, currentFrame: Self.currentFrame)
                .offsetBy(dx: offset.x, dy: offset.y)
            let actual = FrameResolver.frame(for: spec, visibleFrame: moved, currentFrame: Self.currentFrame)
            #expect(actual == expected, "\(spec) on \(size) moved by \(offset)")
        }
    }

    @Test("every grid cell moves with the visible frame", arguments: sizes, offsets)
    func gridCellsShift(size: CGSize, offset: CGPoint) {
        let base = CGRect(origin: .zero, size: size)
        let moved = base.offsetBy(dx: offset.x, dy: offset.y)
        for grid in Self.grids {
            let expected = grid.frames(in: base).map { $0.offsetBy(dx: offset.x, dy: offset.y) }
            let actual = grid.frames(in: moved)
            #expect(actual == expected, "grid of \(grid.windowCount) on \(size) moved by \(offset)")
        }
    }
}
