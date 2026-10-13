import CoreGraphics
import Testing

@testable import PiccoloSystem

@Suite("FrameSetter")
struct FrameSetterTests {
    private let small = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let large = CGRect(x: 1000, y: 0, width: 2000, height: 1200)

    @Test("applies size, then position, then size, and returns the frame read back")
    func order() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), displays: [small, large])
        let target = CGRect(x: 200, y: 200, width: 900, height: 600)

        let achieved = try FrameSetter.apply(target, to: window)

        #expect(window.calls == ["size", "position", "size"])
        #expect(achieved == target)
    }

    @Test("a move to a larger display reaches the full size only thanks to the second size step")
    func moveToLargerDisplay() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), displays: [small, large])
        let target = CGRect(x: 1100, y: 100, width: 1800, height: 1000)

        let achieved = try FrameSetter.apply(target, to: window)

        // The first size step was clamped to the small display; the last one is not.
        #expect(achieved == target)
    }

    @Test("a move to a smaller display ends up at the requested size")
    func moveToSmallerDisplay() throws {
        let window = FakeWindow(
            frame: CGRect(x: 1100, y: 100, width: 1800, height: 1000), displays: [small, large])
        let target = CGRect(x: 100, y: 100, width: 700, height: 500)

        let achieved = try FrameSetter.apply(target, to: window)

        #expect(achieved == target)
    }

    @Test("returns what the window actually achieved when it refuses the requested size")
    func achievedDiffersFromRequested() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 400, height: 400), displays: [small, large])
        window.minimumSize = CGSize(width: 500, height: 450)
        window.maximumSize = CGSize(width: 800, height: 600)

        let tooSmall = try FrameSetter.apply(CGRect(x: 10, y: 20, width: 200, height: 200), to: window)
        #expect(tooSmall == CGRect(x: 10, y: 20, width: 500, height: 450))

        let tooLarge = try FrameSetter.apply(CGRect(x: 30, y: 40, width: 900, height: 700), to: window)
        #expect(tooLarge == CGRect(x: 30, y: 40, width: 800, height: 600))
    }

    @Test("a fixed-size window is still moved to the target's origin and keeps its size")
    func fixedSizeWindowIsMoved() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), displays: [small, large])
        window.isFixedSize = true

        let achieved = try FrameSetter.apply(CGRect(x: 30, y: 40, width: 300, height: 300), to: window)

        #expect(achieved == CGRect(x: 30, y: 40, width: 800, height: 600))
        #expect(window.calls == ["size", "position", "size"])
    }

    @Test("any other failure of the size step aborts before the window is moved")
    func sizeFailureStopsEarly() {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), displays: [small, large])
        window.failSizeWith = .accessibility(operation: "set AXSize", code: -25204)

        #expect(throws: WindowError.accessibility(operation: "set AXSize", code: -25204)) {
            try FrameSetter.apply(CGRect(x: 0, y: 0, width: 300, height: 300), to: window)
        }
        #expect(window.calls == ["size"])
        #expect(window.origin == CGPoint(x: 100, y: 100))
    }

    @Test("a window that is gone fails with noFocusedWindow, also from the size step")
    func windowGone() {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), displays: [small, large])
        window.failSizeWith = .noFocusedWindow

        #expect(throws: WindowError.noFocusedWindow) {
            try FrameSetter.apply(CGRect(x: 0, y: 0, width: 300, height: 300), to: window)
        }
    }

    @Test("a position that cannot be set is an error")
    func positionFailure() {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), displays: [small, large])
        window.failPositionWith = .attributeNotSettable("AXPosition")

        #expect(throws: WindowError.attributeNotSettable("AXPosition")) {
            try FrameSetter.apply(CGRect(x: 0, y: 0, width: 300, height: 300), to: window)
        }
    }

    // MARK: Staying inside the visible frame

    @Test("a window that refuses the size and sticks out is shifted back inside")
    func refusedSizeIsShiftedInside() throws {
        // Right half of a 1000 pt wide display, but the window is at least 700 pt wide.
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 400, height: 400), displays: [small, large])
        window.minimumSize = CGSize(width: 700, height: 300)
        let target = CGRect(x: 500, y: 0, width: 500, height: 800)

        let achieved = try FrameSetter.apply(target, to: window, within: small)

        // The size step ended at 700 x 800 at x 500, which sticks out by 200 pt on the right.
        #expect(achieved == CGRect(x: 300, y: 0, width: 700, height: 800))
        #expect(small.contains(achieved))
        #expect(window.calls == ["size", "position", "size", "position"])
    }

    @Test("the shift reports the frame read back, not the one computed")
    func shiftReportsReadBack() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 400, height: 400), displays: [small, large])
        window.minimumSize = CGSize(width: 700, height: 300)
        window.ignorePositionFromCall = 2

        let achieved = try FrameSetter.apply(
            CGRect(x: 500, y: 0, width: 500, height: 800), to: window, within: small)

        // The window did not follow the second move.
        #expect(achieved == CGRect(x: 500, y: 0, width: 700, height: 800))
    }

    @Test("a window larger than the visible frame is aligned to its top-left corner")
    func largerThanVisibleFrame() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 400, height: 400), displays: [small, large])
        window.minimumSize = CGSize(width: 700, height: 300)
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 800)

        let achieved = try FrameSetter.apply(
            CGRect(x: 300, y: 100, width: 300, height: 700), to: window, within: narrow)

        // It cannot fit, so it sticks out on the right only.
        #expect(achieved == CGRect(x: 0, y: 100, width: 700, height: 700))
    }

    @Test("a window that fits is not moved a second time")
    func insideIsLeftAlone() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 400, height: 400), displays: [small, large])
        let target = CGRect(x: 500, y: 0, width: 500, height: 800)

        let achieved = try FrameSetter.apply(target, to: window, within: small)

        #expect(achieved == target)
        #expect(window.calls == ["size", "position", "size"])
    }

    @Test("without a visible frame a window that sticks out stays where the target put it")
    func noVisibleFrameNoShift() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 400, height: 400), displays: [small, large])
        window.minimumSize = CGSize(width: 700, height: 300)

        let achieved = try FrameSetter.apply(CGRect(x: 500, y: 0, width: 500, height: 800), to: window)

        #expect(achieved == CGRect(x: 500, y: 0, width: 700, height: 800))
        #expect(window.calls == ["size", "position", "size"])
    }

    @Test("a fixed-size window that sticks out of the visible frame is shifted back inside")
    func fixedSizeIsShiftedInside() throws {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), displays: [small, large])
        window.isFixedSize = true

        let achieved = try FrameSetter.apply(
            CGRect(x: 500, y: 0, width: 500, height: 800), to: window, within: small)

        #expect(achieved == CGRect(x: 200, y: 0, width: 800, height: 600))
    }

    @Test("a failure while shifting is an error")
    func shiftFailure() {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 400, height: 400), displays: [small, large])
        window.minimumSize = CGSize(width: 700, height: 300)
        window.failPositionWith = .noFocusedWindow
        window.failPositionFromCall = 2

        #expect(throws: WindowError.noFocusedWindow) {
            try FrameSetter.apply(CGRect(x: 500, y: 0, width: 500, height: 800), to: window, within: small)
        }
    }
}
