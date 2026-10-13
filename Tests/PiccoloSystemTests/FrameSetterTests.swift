import CoreGraphics
import Testing

@testable import PiccoloSystem

/// A window on a pair of displays. Like a real window it cannot grow beyond the
/// display its origin is on, and it never gets smaller than `minimumSize` or larger
/// than `maximumSize`, which is what makes the order of operations observable.
private final class FakeWindow: WindowFrameAccess {
    var origin: CGPoint
    var size: CGSize
    var displays: [CGRect]
    var minimumSize = CGSize(width: 100, height: 100)
    var maximumSize = CGSize(width: 100_000, height: 100_000)
    var failSizeWith: WindowError?
    var calls: [String] = []

    init(frame: CGRect, displays: [CGRect]) {
        origin = frame.origin
        size = frame.size
        self.displays = displays
    }

    func frame() throws -> CGRect {
        CGRect(origin: origin, size: size)
    }

    func setSize(_ newSize: CGSize) throws {
        calls.append("size")
        if let failSizeWith { throw failSizeWith }
        let display = displays.first { $0.contains(origin) } ?? displays[0]
        size = CGSize(
            width: min(max(newSize.width, minimumSize.width), min(maximumSize.width, display.width)),
            height: min(
                max(newSize.height, minimumSize.height), min(maximumSize.height, display.height)))
    }

    func setPosition(_ newOrigin: CGPoint) throws {
        calls.append("position")
        origin = newOrigin
    }
}

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

    @Test("a size that cannot be set aborts before the window is moved")
    func sizeFailureStopsEarly() {
        let window = FakeWindow(
            frame: CGRect(x: 100, y: 100, width: 800, height: 600), displays: [small, large])
        window.failSizeWith = .attributeNotSettable("AXSize")

        #expect(throws: WindowError.attributeNotSettable("AXSize")) {
            try FrameSetter.apply(CGRect(x: 0, y: 0, width: 300, height: 300), to: window)
        }
        #expect(window.calls == ["size"])
        #expect(window.origin == CGPoint(x: 100, y: 100))
    }
}
