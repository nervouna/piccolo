import CoreGraphics

@testable import PiccoloSystem

/// A window on a set of displays. Like a real window it cannot grow beyond the display its
/// origin is on, and it never gets smaller than `minimumSize` or larger than `maximumSize`, which is
/// what makes the order of operations observable.
///
/// Tests use it from one thread only; `@unchecked Sendable` lets an executor provider capture it.
final class FakeWindow: WindowFrameAccess, @unchecked Sendable {
    var origin: CGPoint
    var size: CGSize
    var displays: [CGRect]
    var minimumSize = CGSize(width: 100, height: 100)
    var maximumSize = CGSize(width: 100_000, height: 100_000)
    /// Makes every `setSize` fail with this error, as `FocusedWindow` does for a fixed-size window.
    var failSizeWith: WindowError?
    /// Makes `setPosition` fail with this error, from the call numbered `failPositionFromCall` on.
    var failPositionWith: WindowError?
    var failPositionFromCall = 1
    /// Makes the window ignore `setPosition` silently, from this call on (1 is the first call).
    var ignorePositionFromCall: Int?
    var failFrameWith: WindowError?
    /// The operations that changed or tried to change the window, in order: "size", "position".
    var calls: [String] = []

    init(frame: CGRect, displays: [CGRect]) {
        origin = frame.origin
        size = frame.size
        self.displays = displays
    }

    /// A fixed-size window: its size is not settable.
    var isFixedSize: Bool {
        get { failSizeWith == .attributeNotSettable("AXSize") }
        set { failSizeWith = newValue ? .attributeNotSettable("AXSize") : nil }
    }

    func frame() throws -> CGRect {
        if let failFrameWith { throw failFrameWith }
        return CGRect(origin: origin, size: size)
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
        let number = calls.filter { $0 == "position" }.count
        if let failPositionWith, number >= failPositionFromCall { throw failPositionWith }
        if let ignorePositionFromCall, number >= ignorePositionFromCall { return }
        origin = newOrigin
    }
}
