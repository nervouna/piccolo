import CoreGraphics
import Testing

@testable import PiccoloCore

@Suite("AnimationEligibility")
struct AnimationEligibilityTests {
    private static let left = Display(
        frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 970))
    private static let right = Display(
        frame: CGRect(x: 1600, y: 0, width: 1200, height: 800),
        visibleFrame: CGRect(x: 1600, y: 30, width: 1200, height: 770))
    private let displays = [left, right]

    private let start = CGRect(x: 100, y: 100, width: 600, height: 400)

    @Test("a window that moves is animated")
    func movingWindow() {
        let target = CGRect(x: 400, y: 100, width: 600, height: 400)
        #expect(AnimationEligibility.isAnimated(from: start, to: target, displays: displays))
    }

    @Test("a window that only changes its size is animated")
    func resizingWindow() {
        let target = CGRect(x: 100, y: 100, width: 800, height: 400)
        #expect(AnimationEligibility.isAnimated(from: start, to: target, displays: displays))
    }

    @Test("equal frames are not animated")
    func equalFrames() {
        #expect(!AnimationEligibility.isAnimated(from: start, to: start, displays: displays))
    }

    @Test("a frame within a point on every edge is not animated, also when each edge differs")
    func withinAPoint() {
        let target = CGRect(x: 101, y: 99, width: 600, height: 400)  // edges 1 pt away at most
        let allEdges = CGRect(x: 101, y: 101, width: 598, height: 398)  // minX/minY +1, maxX/maxY -1
        #expect(!AnimationEligibility.isAnimated(from: start, to: target, displays: displays))
        #expect(!AnimationEligibility.isAnimated(from: start, to: allEdges, displays: displays))
    }

    @Test(
        "an edge more than a point away is enough to animate",
        arguments: [
            CGRect(x: 101.5, y: 100, width: 598.5, height: 400),  // minX
            CGRect(x: 100, y: 98.5, width: 600, height: 401.5),  // minY
            CGRect(x: 100, y: 100, width: 601.5, height: 400),  // maxX
            CGRect(x: 100, y: 100, width: 600, height: 398.5),  // maxY
        ])
    func oneEdgeFar(target: CGRect) {
        #expect(AnimationEligibility.isAnimated(from: start, to: target, displays: displays))
    }

    @Test("a window sent to the other display is not animated")
    func differentDisplays() {
        let target = CGRect(x: 1800, y: 100, width: 600, height: 400)
        #expect(!AnimationEligibility.isAnimated(from: start, to: target, displays: displays))
        #expect(!AnimationEligibility.isAnimated(from: target, to: start, displays: displays))
    }

    @Test("a window is on the display that holds the larger part of it, at either end")
    func largestShare() {
        // 700 wide: 500 on the left display, 200 on the right one.
        let mostlyLeft = CGRect(x: 1100, y: 100, width: 700, height: 400)
        // 700 wide: 200 on the left display, 500 on the right one.
        let mostlyRight = CGRect(x: 1400, y: 100, width: 700, height: 400)
        let insideLeft = CGRect(x: 100, y: 100, width: 600, height: 400)
        let insideRight = CGRect(x: 1800, y: 100, width: 600, height: 400)

        #expect(AnimationEligibility.isAnimated(from: mostlyLeft, to: insideLeft, displays: displays))
        #expect(AnimationEligibility.isAnimated(from: insideRight, to: mostlyRight, displays: displays))
        #expect(!AnimationEligibility.isAnimated(from: mostlyLeft, to: mostlyRight, displays: displays))
        #expect(!AnimationEligibility.isAnimated(from: mostlyRight, to: insideLeft, displays: displays))
    }

    @Test("with one display everything on it is animated")
    func singleDisplay() {
        let target = CGRect(x: 800, y: 300, width: 400, height: 300)
        #expect(AnimationEligibility.isAnimated(from: start, to: target, displays: [Self.left]))
    }

    @Test("without a display there is nothing to compare, so the window is not animated")
    func noDisplays() {
        let target = CGRect(x: 800, y: 300, width: 400, height: 300)
        #expect(!AnimationEligibility.isAnimated(from: start, to: target, displays: []))
    }

    @Test("the tolerance is one point")
    func tolerance() {
        #expect(AnimationEligibility.sameFrameTolerance == 1)
    }
}
