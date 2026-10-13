import CoreGraphics
import Testing

@testable import PiccoloCore

/// Displays for the index and neighbour tests, in canonical space.
///
/// `primary` is 1440x900 at the origin, `right` is 1920x1080 to its right, and `above` is 1920x1080
/// directly above the primary, which gives it a negative y.
private enum Screens {
    static let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))
    static let right = Display(
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
    static let above = Display(
        frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    /// 1727x1085 at (-1728, 355), to the left of the primary. Odd sizes, so that rounding matters.
    static let oddLeft = Display(
        frame: CGRect(x: -1728, y: 355, width: 1727, height: 1085),
        visibleFrame: CGRect(x: -1728, y: 355, width: 1727, height: 1085))
    /// A copy of the primary's visible size, to the right of the primary: its visible frame is 1440x875 at (1440, 0).
    static let equalRight = Display(
        frame: CGRect(x: 1440, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1440, height: 875))
}

@Suite("DisplayLayout.index(containing:in:)")
struct DisplayIndexTests {
    private let displays = [Screens.primary, Screens.right]

    @Test("a window fully inside one display belongs to that display")
    func fullyInside() {
        #expect(DisplayLayout.index(containing: CGRect(x: 100, y: 100, width: 200, height: 200), in: displays) == 0)
        #expect(DisplayLayout.index(containing: CGRect(x: 1500, y: 100, width: 200, height: 200), in: displays) == 1)
    }

    @Test("a window straddling two displays belongs to the one holding the larger part")
    func straddling() {
        // Overlaps: primary 140 wide, right 160 wide.
        #expect(DisplayLayout.index(containing: CGRect(x: 1300, y: 100, width: 300, height: 200), in: displays) == 1)
        // Overlaps: primary 140 wide, right 60 wide.
        #expect(DisplayLayout.index(containing: CGRect(x: 1300, y: 100, width: 200, height: 200), in: displays) == 0)
    }

    @Test("an exact tie goes to the lower index")
    func exactTie() {
        // Overlaps: 100 wide on each display.
        let window = CGRect(x: 1340, y: 100, width: 200, height: 200)
        #expect(DisplayLayout.index(containing: window, in: displays) == 0)
        #expect(DisplayLayout.index(containing: window, in: [Screens.right, Screens.primary]) == 0)
    }

    @Test("a window outside every display goes to the display whose centre is nearest")
    func outsideAll() {
        // Window centre (-450, 150) is nearest to the primary's centre (720, 450).
        #expect(DisplayLayout.index(containing: CGRect(x: -500, y: 100, width: 100, height: 100), in: displays) == 0)
        // Window centre (3050, 150) is nearest to the right display's centre (2400, 540).
        #expect(DisplayLayout.index(containing: CGRect(x: 3000, y: 100, width: 100, height: 100), in: displays) == 1)
    }

    @Test("an equidistant centre goes to the lower index")
    func nearestTie() {
        // Display centres (100, 50) and (300, 50). The window centre (200, 310) is equidistant
        // from both, and it intersects neither.
        let left = CGRect(x: 0, y: 0, width: 200, height: 100)
        let right = CGRect(x: 200, y: 0, width: 200, height: 100)
        let pair = [
            Display(frame: left, visibleFrame: left),
            Display(frame: right, visibleFrame: right),
        ]
        let window = CGRect(x: 190, y: 300, width: 20, height: 20)
        #expect(DisplayLayout.index(containing: window, in: pair) == 0)
        #expect(DisplayLayout.index(containing: window, in: Array(pair.reversed())) == 0)
    }

    @Test("an empty list has no display")
    func emptyList() {
        #expect(DisplayLayout.index(containing: CGRect(x: 0, y: 0, width: 100, height: 100), in: []) == nil)
    }
}

@Suite("DisplayLayout.neighbor(of:_:in:)")
struct DisplayNeighborTests {
    @Test("with two displays, the second to the left comes first in position order")
    func twoDisplaysSecondLeft() {
        // Index 0 is at x = 0, index 1 at x = -1728, so the order is [1, 0].
        let displays = [Screens.primary, Screens.oddLeft]
        #expect(DisplayLayout.neighbor(of: 0, .next, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 0, .previous, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 1, .next, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 1, .previous, in: displays) == 0)
    }

    @Test(
        "with three displays out of index order, next and previous wrap around",
        arguments: [
            (0, DisplayDirection.next, 1),
            (0, DisplayDirection.previous, 2),
            (1, DisplayDirection.next, 2),
            (1, DisplayDirection.previous, 0),
            (2, DisplayDirection.next, 0),
            (2, DisplayDirection.previous, 1),
        ])
    func threeDisplaysWrap(index: Int, direction: DisplayDirection, expected: Int) {
        // Positions by minX: index 1 (-1728), index 2 (0), index 0 (1440). Order: [1, 2, 0].
        let displays = [
            Display(
                frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055)),
            Display(
                frame: CGRect(x: -1728, y: 355, width: 1727, height: 1085),
                visibleFrame: CGRect(x: -1728, y: 355, width: 1727, height: 1085)),
            Display(
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875)),
        ]
        #expect(DisplayLayout.neighbor(of: index, direction, in: displays) == expected)
    }

    @Test("displays with the same minX are ordered by minY")
    func sameMinXOrderedByMinY() {
        // minX 0: index 1 (minY -1080) before index 0 (minY 0). Then index 2 at minX 1440.
        // Order: [1, 0, 2].
        let displays = [Screens.primary, Screens.above, Screens.right]
        #expect(DisplayLayout.neighbor(of: 1, .next, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 0, .next, in: displays) == 2)
        #expect(DisplayLayout.neighbor(of: 2, .next, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 1, .previous, in: displays) == 2)
        #expect(DisplayLayout.neighbor(of: 0, .previous, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 2, .previous, in: displays) == 0)
    }

    @Test("displays with identical frames are ordered by index")
    func identicalFramesOrderedByIndex() {
        let displays = [Screens.primary, Screens.primary]
        #expect(DisplayLayout.neighbor(of: 0, .next, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 1, .next, in: displays) == 0)
    }

    @Test("a single display is its own neighbour in both directions")
    func singleDisplay() {
        #expect(DisplayLayout.neighbor(of: 0, .next, in: [Screens.primary]) == 0)
        #expect(DisplayLayout.neighbor(of: 0, .previous, in: [Screens.primary]) == 0)
    }
}

@Suite("DisplayLayout.frame(moving:from:to:)")
struct DisplayMoveTests {
    @Test("a maximized window lands exactly on the target's visible frame")
    func maximizedWindow() {
        let plain = Screens.primary.visibleFrame
        let odd = Screens.oddLeft.visibleFrame
        #expect(DisplayLayout.frame(moving: plain, from: Screens.primary, to: Screens.oddLeft) == odd)
        #expect(DisplayLayout.frame(moving: odd, from: Screens.oddLeft, to: Screens.primary) == plain)
    }

    @Test("a left-half window lands on the frame leftHalf resolves to on the target")
    func leftHalfWindow() {
        // leftHalf on the primary's visible frame (0, 25, 1440, 875) is (0, 25, 720, 875).
        let leftHalfOnPrimary = CGRect(x: 0, y: 25, width: 720, height: 875)
        // Scaled to the odd frame: x = -1728 + 0.5 * 1727 = -864.5, which rounds to -865 for the
        // right edge; the window keeps the left edge at -1728.
        let moved = DisplayLayout.frame(moving: leftHalfOnPrimary, from: Screens.primary, to: Screens.oddLeft)
        #expect(moved == CGRect(x: -1728, y: 355, width: 863, height: 1085))
        #expect(moved == FrameResolver.frame(
            for: .preset(.leftHalf), visibleFrame: Screens.oddLeft.visibleFrame, currentFrame: .zero))
    }

    @Test("a left-half window moved from the odd frame to the primary lands on the primary's leftHalf")
    func leftHalfWindowBack() {
        let leftHalfOnOdd = CGRect(x: -1728, y: 355, width: 863, height: 1085)
        let moved = DisplayLayout.frame(moving: leftHalfOnOdd, from: Screens.oddLeft, to: Screens.primary)
        #expect(moved == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(moved == FrameResolver.frame(
            for: .preset(.leftHalf), visibleFrame: Screens.primary.visibleFrame, currentFrame: .zero))
    }

    @Test("a right-half window lands on the frame rightHalf resolves to on the target")
    func rightHalfWindow() {
        let rightHalfOnPrimary = CGRect(x: 720, y: 25, width: 720, height: 875)
        let moved = DisplayLayout.frame(moving: rightHalfOnPrimary, from: Screens.primary, to: Screens.oddLeft)
        #expect(moved == CGRect(x: -865, y: 355, width: 864, height: 1085))
        #expect(moved == FrameResolver.frame(
            for: .preset(.rightHalf), visibleFrame: Screens.oddLeft.visibleFrame, currentFrame: .zero))
    }

    @Test("a window larger than the target is capped to the target and stays inside it")
    func largerThanTarget() {
        // The window is 1200 wide on an 800 wide source, so it is 1.5 times the source width and
        // starts 0.25 source widths to the left. Scaled to the primary, it is 2160 wide, capped to
        // 1440. Its origin, -360, is shifted to 0.
        let source = Display(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let window = CGRect(x: -200, y: 0, width: 1200, height: 600)
        let moved = DisplayLayout.frame(moving: window, from: source, to: Screens.primary)
        #expect(moved == Screens.primary.visibleFrame)
        #expect(Screens.primary.visibleFrame.contains(moved))
    }

    @Test("a window that would stick out on the target is shifted inside it")
    func shiftedInside() {
        // Fractions on a 1920x1080 source: x 0.9375, width 0.15625. On the primary (visible
        // 1440x875): x 1350, width 225, so the right edge would be 1575. Shifted to 1440 - 225 = 1215.
        let source = Display(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let window = CGRect(x: 1800, y: 0, width: 300, height: 1080)
        let moved = DisplayLayout.frame(moving: window, from: source, to: Screens.primary)
        #expect(moved == CGRect(x: 1215, y: 25, width: 225, height: 875))
        #expect(Screens.primary.visibleFrame.contains(moved))
    }

    /// A copy of the odd display at the origin: the same visible size, so the same odd fractions.
    private static let oddCopy = Display(
        frame: CGRect(x: 0, y: 0, width: 1727, height: 1085),
        visibleFrame: CGRect(x: 0, y: 0, width: 1727, height: 1085))

    @Test(
        "moving there and back between the primary and an equal-sized display returns the original",
        arguments: [
            CGRect(x: 100, y: 200, width: 333, height: 444),
            CGRect(x: 0, y: 25, width: 720, height: 875),
            CGRect(x: 1000, y: 400, width: 301, height: 277),
        ])
    func roundTripPrimary(_ window: CGRect) {
        let there = DisplayLayout.frame(moving: window, from: Screens.primary, to: Screens.equalRight)
        let back = DisplayLayout.frame(moving: there, from: Screens.equalRight, to: Screens.primary)
        #expect(back == window)
    }

    @Test(
        "moving there and back between the odd display and an equal-sized copy returns the original",
        arguments: [
            CGRect(x: -1728, y: 355, width: 863, height: 1085),
            CGRect(x: -1000, y: 400, width: 301, height: 277),
            CGRect(x: -1500, y: 1000, width: 333, height: 333),
        ])
    func roundTripOdd(_ window: CGRect) {
        let there = DisplayLayout.frame(moving: window, from: Screens.oddLeft, to: Self.oddCopy)
        let back = DisplayLayout.frame(moving: there, from: Self.oddCopy, to: Screens.oddLeft)
        #expect(back == window)
    }
}
