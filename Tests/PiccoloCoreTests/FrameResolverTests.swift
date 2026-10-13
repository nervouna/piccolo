import CoreGraphics
import Testing

@testable import PiccoloCore

/// The two visible frames the geometry is checked on.
///
/// `plain` is 1440x900 with a 25 point menu bar: its halves, thirds and quarters are whole
/// numbers. `odd` is 1727x1085 at (-1728, 355): every half and third has a fractional edge,
/// so the rounding rule decides the expected values. Those values were worked out by hand,
/// with ties rounded away from zero.
private enum VisibleFrame {
    static let plain = CGRect(x: 0, y: 25, width: 1440, height: 875)
    static let odd = CGRect(x: -1728, y: 355, width: 1727, height: 1085)
}

/// Presets ignore the current frame. Only `.center` reads it.
private func resolve(_ spec: FrameSpec, on visible: CGRect, current: CGRect = .zero) -> CGRect {
    FrameResolver.frame(for: spec, visibleFrame: visible, currentFrame: current)
}

/// Every preset that has a fraction, in declaration order.
private let fractionalPresets = Preset.allCases.filter { $0 != .center }

/// Expected frames on the plain visible frame, worked out by hand.
///
/// Top and bottom halves: 25 + 0.5 * 875 = 462.5 rounds to 463, so the heights are 438 and 437.
private let expectedOnPlain: [Preset: CGRect] = [
    .leftHalf: CGRect(x: 0, y: 25, width: 720, height: 875),
    .rightHalf: CGRect(x: 720, y: 25, width: 720, height: 875),
    .topHalf: CGRect(x: 0, y: 25, width: 1440, height: 438),
    .bottomHalf: CGRect(x: 0, y: 463, width: 1440, height: 437),
    .topLeft: CGRect(x: 0, y: 25, width: 720, height: 438),
    .topRight: CGRect(x: 720, y: 25, width: 720, height: 438),
    .bottomLeft: CGRect(x: 0, y: 463, width: 720, height: 437),
    .bottomRight: CGRect(x: 720, y: 463, width: 720, height: 437),
    .leftThird: CGRect(x: 0, y: 25, width: 480, height: 875),
    .centerThird: CGRect(x: 480, y: 25, width: 480, height: 875),
    .rightThird: CGRect(x: 960, y: 25, width: 480, height: 875),
    .leftTwoThirds: CGRect(x: 0, y: 25, width: 960, height: 875),
    .rightTwoThirds: CGRect(x: 480, y: 25, width: 960, height: 875),
    .maximize: CGRect(x: 0, y: 25, width: 1440, height: 875),
]

/// Expected frames on the odd visible frame, worked out by hand.
///
/// Horizontal edges: -1728 + 0.5 * 1727 = -864.5 rounds to -865; -1728 + 1727 = -1.
/// Thirds: -1728 + 1727/3 = -1152.33 rounds to -1152; -1728 + 2 * 1727/3 = -576.67 rounds to -577.
/// Vertical edges: 355 + 0.5 * 1085 = 897.5 rounds to 898; 355 + 1085 = 1440.
private let expectedOnOdd: [Preset: CGRect] = [
    .leftHalf: CGRect(x: -1728, y: 355, width: 863, height: 1085),
    .rightHalf: CGRect(x: -865, y: 355, width: 864, height: 1085),
    .topHalf: CGRect(x: -1728, y: 355, width: 1727, height: 543),
    .bottomHalf: CGRect(x: -1728, y: 898, width: 1727, height: 542),
    .topLeft: CGRect(x: -1728, y: 355, width: 863, height: 543),
    .topRight: CGRect(x: -865, y: 355, width: 864, height: 543),
    .bottomLeft: CGRect(x: -1728, y: 898, width: 863, height: 542),
    .bottomRight: CGRect(x: -865, y: 898, width: 864, height: 542),
    .leftThird: CGRect(x: -1728, y: 355, width: 576, height: 1085),
    .centerThird: CGRect(x: -1152, y: 355, width: 575, height: 1085),
    .rightThird: CGRect(x: -577, y: 355, width: 576, height: 1085),
    .leftTwoThirds: CGRect(x: -1728, y: 355, width: 1151, height: 1085),
    .rightTwoThirds: CGRect(x: -1152, y: 355, width: 1151, height: 1085),
    .maximize: CGRect(x: -1728, y: 355, width: 1727, height: 1085),
]

@Suite("Preset fractions")
struct PresetFractionTests {
    @Test("center has no fraction, every other preset has a valid one", arguments: Preset.allCases)
    func fractionalRects(_ preset: Preset) throws {
        guard preset != .center else {
            #expect(preset.fractionalRect == nil)
            return
        }
        let rect = try #require(preset.fractionalRect)
        try rect.validate()
    }

    @Test("the written-out tables cover exactly the presets with a fraction")
    func tablesCoverFractionalPresets() {
        #expect(Set(expectedOnPlain.keys) == Set(fractionalPresets))
        #expect(Set(expectedOnOdd.keys) == Set(fractionalPresets))
    }
}

@Suite("FrameResolver presets")
struct PresetFrameTests {
    @Test(
        "each preset resolves to its written-out frame on the plain visible frame",
        arguments: fractionalPresets)
    func plainVisibleFrame(_ preset: Preset) throws {
        let expected = try #require(expectedOnPlain[preset])
        #expect(resolve(.preset(preset), on: VisibleFrame.plain) == expected)
    }

    @Test(
        "each preset resolves to its written-out frame on the odd visible frame",
        arguments: fractionalPresets)
    func oddVisibleFrame(_ preset: Preset) throws {
        let expected = try #require(expectedOnOdd[preset])
        #expect(resolve(.preset(preset), on: VisibleFrame.odd) == expected)
    }

    @Test(
        "every preset is integral and inside the visible frame on both visible frames",
        arguments: [VisibleFrame.plain, VisibleFrame.odd])
    func integralAndInside(_ visible: CGRect) {
        for preset in fractionalPresets {
            let frame = resolve(.preset(preset), on: visible)
            #expect(frame == frame.integral, "\(preset)")
            #expect(visible.contains(frame), "\(preset)")
        }
    }

    @Test(
        "maximize equals the visible frame when the visible frame is integral",
        arguments: [VisibleFrame.plain, VisibleFrame.odd])
    func maximizeIsVisibleFrame(_ visible: CGRect) {
        #expect(resolve(.preset(.maximize), on: visible) == visible)
    }
}

@Suite("Preset tiling")
struct PresetTilingTests {
    @Test(
        "left and right halves meet at one edge and cover the visible frame",
        arguments: [VisibleFrame.plain, VisibleFrame.odd])
    func halvesTileWidth(_ visible: CGRect) {
        let left = resolve(.preset(.leftHalf), on: visible)
        let right = resolve(.preset(.rightHalf), on: visible)
        #expect(left.maxX == right.minX)
        #expect(left.minX == visible.minX)
        #expect(right.maxX == visible.maxX)
        #expect(left.minY == visible.minY && left.maxY == visible.maxY)
        #expect(right.minY == visible.minY && right.maxY == visible.maxY)
    }

    @Test(
        "top and bottom halves meet at one edge and cover the visible frame",
        arguments: [VisibleFrame.plain, VisibleFrame.odd])
    func halvesTileHeight(_ visible: CGRect) {
        let top = resolve(.preset(.topHalf), on: visible)
        let bottom = resolve(.preset(.bottomHalf), on: visible)
        #expect(top.maxY == bottom.minY)
        #expect(top.minY == visible.minY)
        #expect(bottom.maxY == visible.maxY)
        #expect(top.minX == visible.minX && top.maxX == visible.maxX)
        #expect(bottom.minX == visible.minX && bottom.maxX == visible.maxX)
    }

    @Test("the three thirds tile the width exactly", arguments: [VisibleFrame.plain, VisibleFrame.odd])
    func thirdsTileWidth(_ visible: CGRect) {
        let left = resolve(.preset(.leftThird), on: visible)
        let center = resolve(.preset(.centerThird), on: visible)
        let right = resolve(.preset(.rightThird), on: visible)
        #expect(left.maxX == center.minX)
        #expect(center.maxX == right.minX)
        #expect(left.minX == visible.minX)
        #expect(right.maxX == visible.maxX)
        #expect(left.width + center.width + right.width == visible.width)
        for third in [left, center, right] {
            #expect(third.minY == visible.minY && third.maxY == visible.maxY)
        }
    }

    @Test("two-thirds and one-third presets share their middle edge", arguments: [VisibleFrame.plain, VisibleFrame.odd])
    func twoThirdsShareEdge(_ visible: CGRect) {
        let leftTwo = resolve(.preset(.leftTwoThirds), on: visible)
        let rightTwo = resolve(.preset(.rightTwoThirds), on: visible)
        let leftOne = resolve(.preset(.leftThird), on: visible)
        let rightOne = resolve(.preset(.rightThird), on: visible)
        #expect(leftTwo.maxX == rightOne.minX)
        #expect(rightTwo.minX == leftOne.maxX)
        #expect(leftTwo.minX == visible.minX)
        #expect(rightTwo.maxX == visible.maxX)
    }

    @Test("the four quarters tile maximize exactly", arguments: [VisibleFrame.plain, VisibleFrame.odd])
    func quartersTileMaximize(_ visible: CGRect) {
        let topLeft = resolve(.preset(.topLeft), on: visible)
        let topRight = resolve(.preset(.topRight), on: visible)
        let bottomLeft = resolve(.preset(.bottomLeft), on: visible)
        let bottomRight = resolve(.preset(.bottomRight), on: visible)
        let whole = resolve(.preset(.maximize), on: visible)

        #expect(topLeft.maxX == topRight.minX)
        #expect(bottomLeft.maxX == bottomRight.minX)
        #expect(topLeft.maxY == bottomLeft.minY)
        #expect(topRight.maxY == bottomRight.minY)

        #expect(topLeft.minX == whole.minX && topLeft.minY == whole.minY)
        #expect(topRight.maxX == whole.maxX && topRight.minY == whole.minY)
        #expect(bottomLeft.minX == whole.minX && bottomLeft.maxY == whole.maxY)
        #expect(bottomRight.maxX == whole.maxX && bottomRight.maxY == whole.maxY)

        let quarterArea = [topLeft, topRight, bottomLeft, bottomRight].reduce(0) { $0 + $1.width * $1.height }
        #expect(quarterArea == whole.width * whole.height)
    }
}

@Suite("FrameResolver center")
struct CenterFrameTests {
    @Test("a smaller window is centred and keeps its size, on the plain visible frame")
    func smallerWindowPlain() {
        // x: (1440 - 800) / 2 = 320. y: 25 + (875 - 600) / 2 = 162.5, which rounds to 163.
        let current = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(resolve(.preset(.center), on: VisibleFrame.plain, current: current)
            == CGRect(x: 320, y: 163, width: 800, height: 600))
    }

    @Test("a smaller window is centred and keeps its size, on the odd visible frame")
    func smallerWindowOdd() {
        // x: -1728 + (1727 - 800) / 2 = -1264.5, which rounds away from zero to -1265.
        // y: 355 + (1085 - 600) / 2 = 597.5, which rounds to 598.
        let current = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(resolve(.preset(.center), on: VisibleFrame.odd, current: current)
            == CGRect(x: -1265, y: 598, width: 800, height: 600))
    }

    @Test("a window wider than the visible frame is capped in width only")
    func cappedWidth() {
        // Width capped to 1440. y: 25 + (875 - 300) / 2 = 312.5, which rounds to 313.
        let current = CGRect(x: 0, y: 0, width: 2000, height: 300)
        #expect(resolve(.preset(.center), on: VisibleFrame.plain, current: current)
            == CGRect(x: 0, y: 313, width: 1440, height: 300))
    }

    @Test("a window taller than the visible frame is capped in height only")
    func cappedHeight() {
        // Height capped to 875. x: (1440 - 500) / 2 = 470.
        let current = CGRect(x: 50, y: 50, width: 500, height: 1000)
        #expect(resolve(.preset(.center), on: VisibleFrame.plain, current: current)
            == CGRect(x: 470, y: 25, width: 500, height: 875))
    }

    @Test("a window larger than the visible frame in both dimensions becomes the visible frame")
    func cappedBoth() {
        let current = CGRect(x: 0, y: 0, width: 3000, height: 3000)
        #expect(resolve(.preset(.center), on: VisibleFrame.plain, current: current) == VisibleFrame.plain)
        #expect(resolve(.preset(.center), on: VisibleFrame.odd, current: current) == VisibleFrame.odd)
    }

    @Test(
        "the result is integral and inside the visible frame for every size",
        arguments: [
            CGSize(width: 800, height: 600),
            CGSize(width: 2000, height: 300),
            CGSize(width: 500, height: 1000),
            CGSize(width: 3000, height: 3000),
            CGSize(width: 1, height: 1),
            CGSize(width: 1727, height: 1085),
        ])
    func integralAndInside(_ size: CGSize) {
        let current = CGRect(origin: .zero, size: size)
        for visible in [VisibleFrame.plain, VisibleFrame.odd] {
            let frame = resolve(.preset(.center), on: visible, current: current)
            #expect(frame == frame.integral)
            #expect(visible.contains(frame))
        }
    }
}

@Suite("FrameResolver custom rects")
struct CustomFrameTests {
    @Test("a custom rect is resolved by the rounding rule on the visible frame")
    func customRect() {
        // x: 0.25 * 1440 = 360 to 0.75 * 1440 = 1080. Full height.
        let spec = FrameSpec.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1))
        #expect(resolve(spec, on: VisibleFrame.plain) == CGRect(x: 360, y: 25, width: 720, height: 875))
    }

    @Test("a custom rect at fractional positions rounds each edge")
    func fractionalPositions() {
        // x: 180 to 900. y: 25 + 0.25 * 875 = 243.75 rounds to 244, and 25 + 0.625 * 875 = 571.875 rounds to 572.
        let spec = FrameSpec.custom(FractionalRect(x: 0.125, y: 0.25, width: 0.5, height: 0.375))
        #expect(resolve(spec, on: VisibleFrame.plain) == CGRect(x: 180, y: 244, width: 720, height: 328))
    }

    @Test("the width is the difference of the rounded edges, not the rounded width")
    func widthFromRoundedEdges() {
        // Left edge -1728, right edge round(-864.5) = -865, so the width is 863, not round(863.5) = 864.
        let spec = FrameSpec.custom(FractionalRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(resolve(spec, on: VisibleFrame.odd).width == 863)
    }

    @Test(
        "a custom rect that touches the right and bottom edges ends exactly on them",
        arguments: [VisibleFrame.plain, VisibleFrame.odd])
    func touchesRightAndBottom(_ visible: CGRect) {
        let spec = FrameSpec.custom(FractionalRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let frame = resolve(spec, on: visible)
        #expect(frame.maxX == visible.maxX)
        #expect(frame.maxY == visible.maxY)
    }

    @Test("a custom rect touching the right and bottom edges, written out")
    func touchesRightAndBottomValues() {
        // Plain: x 720 to 1440, y 25 + 437.5 rounds to 463, then 900.
        let spec = FrameSpec.custom(FractionalRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        #expect(resolve(spec, on: VisibleFrame.plain) == CGRect(x: 720, y: 463, width: 720, height: 437))
        // Odd: x -865 to -1, y 898 to 1440.
        #expect(resolve(spec, on: VisibleFrame.odd) == CGRect(x: -865, y: 898, width: 864, height: 542))
    }

    @Test("a custom rect equal to a preset resolves to the same frame")
    func matchesPreset() {
        let custom = FrameSpec.custom(FractionalRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(resolve(custom, on: VisibleFrame.odd) == resolve(.preset(.leftHalf), on: VisibleFrame.odd))
    }

    @Test("a custom rect covering the whole visible frame equals the visible frame")
    func wholeFrame() {
        let spec = FrameSpec.custom(FractionalRect(x: 0, y: 0, width: 1, height: 1))
        #expect(resolve(spec, on: VisibleFrame.odd) == VisibleFrame.odd)
    }
}
