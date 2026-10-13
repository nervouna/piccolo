import CoreGraphics
import Testing

@testable import PiccoloCore

/// Frames worked out by hand from the rounding rule. Each boundary is the cumulative
/// fraction scaled to the visible frame, rounded on its own, with the outer edges taken
/// from the visible frame.
///
/// Odd-frame worked values: the x boundary of a 2-column row is -1728 + 863.5 = -864.5,
/// which rounds away from zero to -865. The y boundary of a 2-row grid is 355 + 542.5 = 897.5,
/// which rounds to 898. The 3-row grid's boundaries are 355 + 361.67 = 716.67 -> 717 and
/// 355 + 723.33 = 1078.33 -> 1078. The hand-built layout's boundary is 355 + 325.5 -> 681.
@Suite("TileLayout frames")
struct TileLayoutFramesTests {
    struct Expectation: Sendable, CustomTestStringConvertible {
        let name: String
        let layout: TileLayout
        let visible: CGRect
        let frames: [CGRect]

        var testDescription: String { name }
    }

    private static let primary = TileLayoutSupport.primaryVisible
    private static let odd = TileLayoutSupport.oddVisible

    static let expectations: [Expectation] = [
        Expectation(
            name: "4 in 2x2 on the primary frame",
            layout: TileLayout.grid(windowCount: 4, rows: 2, columns: 2),
            visible: primary,
            frames: [
                CGRect(x: 0, y: 25, width: 720, height: 438),
                CGRect(x: 720, y: 25, width: 720, height: 438),
                CGRect(x: 0, y: 463, width: 720, height: 437),
                CGRect(x: 720, y: 463, width: 720, height: 437),
            ]),
        Expectation(
            name: "4 in 2x2 on the odd frame",
            layout: TileLayout.grid(windowCount: 4, rows: 2, columns: 2),
            visible: odd,
            frames: [
                CGRect(x: -1728, y: 355, width: 863, height: 543),
                CGRect(x: -865, y: 355, width: 864, height: 543),
                CGRect(x: -1728, y: 898, width: 863, height: 542),
                CGRect(x: -865, y: 898, width: 864, height: 542),
            ]),
        Expectation(
            name: "3 in 2x2 on the primary frame",
            layout: TileLayout.grid(windowCount: 3, rows: 2, columns: 2),
            visible: primary,
            frames: [
                CGRect(x: 0, y: 25, width: 720, height: 438),
                CGRect(x: 720, y: 25, width: 720, height: 438),
                CGRect(x: 0, y: 463, width: 1440, height: 437),
            ]),
        Expectation(
            name: "3 in 2x2 on the odd frame",
            layout: TileLayout.grid(windowCount: 3, rows: 2, columns: 2),
            visible: odd,
            frames: [
                CGRect(x: -1728, y: 355, width: 863, height: 543),
                CGRect(x: -865, y: 355, width: 864, height: 543),
                CGRect(x: -1728, y: 898, width: 1727, height: 542),
            ]),
        Expectation(
            name: "5 in 2x3 on the primary frame",
            layout: TileLayout.grid(windowCount: 5, rows: 2, columns: 3),
            visible: primary,
            frames: [
                CGRect(x: 0, y: 25, width: 480, height: 438),
                CGRect(x: 480, y: 25, width: 480, height: 438),
                CGRect(x: 960, y: 25, width: 480, height: 438),
                CGRect(x: 0, y: 463, width: 720, height: 437),
                CGRect(x: 720, y: 463, width: 720, height: 437),
            ]),
        Expectation(
            name: "5 in 2x3 on the odd frame",
            layout: TileLayout.grid(windowCount: 5, rows: 2, columns: 3),
            visible: odd,
            frames: [
                CGRect(x: -1728, y: 355, width: 576, height: 543),
                CGRect(x: -1152, y: 355, width: 575, height: 543),
                CGRect(x: -577, y: 355, width: 576, height: 543),
                CGRect(x: -1728, y: 898, width: 863, height: 542),
                CGRect(x: -865, y: 898, width: 864, height: 542),
            ]),
        Expectation(
            name: "3 in 1x3 on the primary frame",
            layout: TileLayout.grid(windowCount: 3, rows: 1, columns: 3),
            visible: primary,
            frames: [
                CGRect(x: 0, y: 25, width: 480, height: 875),
                CGRect(x: 480, y: 25, width: 480, height: 875),
                CGRect(x: 960, y: 25, width: 480, height: 875),
            ]),
        Expectation(
            name: "3 in 1x3 on the odd frame",
            layout: TileLayout.grid(windowCount: 3, rows: 1, columns: 3),
            visible: odd,
            frames: [
                CGRect(x: -1728, y: 355, width: 576, height: 1085),
                CGRect(x: -1152, y: 355, width: 575, height: 1085),
                CGRect(x: -577, y: 355, width: 576, height: 1085),
            ]),
        Expectation(
            name: "3 in 3x1 on the primary frame",
            layout: TileLayout.grid(windowCount: 3, rows: 3, columns: 1),
            visible: primary,
            frames: [
                CGRect(x: 0, y: 25, width: 1440, height: 292),
                CGRect(x: 0, y: 317, width: 1440, height: 291),
                CGRect(x: 0, y: 608, width: 1440, height: 292),
            ]),
        Expectation(
            name: "3 in 3x1 on the odd frame",
            layout: TileLayout.grid(windowCount: 3, rows: 3, columns: 1),
            visible: odd,
            frames: [
                CGRect(x: -1728, y: 355, width: 1727, height: 362),
                CGRect(x: -1728, y: 717, width: 1727, height: 361),
                CGRect(x: -1728, y: 1078, width: 1727, height: 362),
            ]),
        Expectation(
            name: "hand-built layout on the primary frame",
            layout: TileLayoutSupport.handBuilt,
            visible: primary,
            frames: [
                CGRect(x: 0, y: 25, width: 360, height: 263),
                CGRect(x: 360, y: 25, width: 1080, height: 263),
                CGRect(x: 0, y: 288, width: 1440, height: 612),
            ]),
        Expectation(
            name: "hand-built layout on the odd frame",
            layout: TileLayoutSupport.handBuilt,
            visible: odd,
            frames: [
                CGRect(x: -1728, y: 355, width: 432, height: 326),
                CGRect(x: -1296, y: 355, width: 1295, height: 326),
                CGRect(x: -1728, y: 681, width: 1727, height: 759),
            ]),
    ]

    @Test("frames match the values worked out by hand", arguments: expectations)
    func expectedFrames(expectation: Expectation) {
        #expect(expectation.layout.frames(in: expectation.visible) == expectation.frames)
    }

    @Test("every layout tiles its visible frame exactly", arguments: TileLayoutSupport.scenes)
    func tilesExactly(scene: TileLayoutSupport.Scene) {
        let frames = scene.layout.frames(in: scene.visible)
        let cellsPerRow = scene.layout.rows.map { $0.widths.count }
        let violations = TileLayoutSupport.tilingViolations(
            frames, cellsPerRow: cellsPerRow, visible: scene.visible)
        #expect(violations.isEmpty, "\(violations)")
        #expect(frames.count == scene.layout.windowCount)
    }

    @Test("the tiling checks reject gaps, overlaps, fractional edges and wrong order")
    func checksCatchBrokenTilings() {
        let visible = CGRect(x: 0, y: 0, width: 10, height: 10)
        let good = [CGRect(x: 0, y: 0, width: 4, height: 10), CGRect(x: 4, y: 0, width: 6, height: 10)]
        #expect(TileLayoutSupport.tilingViolations(good, cellsPerRow: [2], visible: visible).isEmpty)

        let gap = [CGRect(x: 0, y: 0, width: 4, height: 10), CGRect(x: 5, y: 0, width: 5, height: 10)]
        #expect(!TileLayoutSupport.tilingViolations(gap, cellsPerRow: [2], visible: visible).isEmpty)

        let overlap = [CGRect(x: 0, y: 0, width: 6, height: 10), CGRect(x: 4, y: 0, width: 6, height: 10)]
        #expect(!TileLayoutSupport.tilingViolations(overlap, cellsPerRow: [2], visible: visible).isEmpty)

        let fractional = [
            CGRect(x: 0, y: 0, width: 4.5, height: 10),
            CGRect(x: 4.5, y: 0, width: 5.5, height: 10),
        ]
        #expect(!TileLayoutSupport.tilingViolations(fractional, cellsPerRow: [2], visible: visible).isEmpty)

        let reversed = [good[1], good[0]]
        #expect(!TileLayoutSupport.tilingViolations(reversed, cellsPerRow: [2], visible: visible).isEmpty)
    }
}
