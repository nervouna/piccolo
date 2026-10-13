import ApplicationServices
import CoreGraphics
import Foundation
import PiccoloCore

/// The focused window of the frontmost application, reached through Accessibility.
///
/// AXPosition and AXSize are already in canonical coordinates (global, top-left
/// origin of the primary display, y down), so frames cross this boundary unchanged.
///
/// Create one per operation: the underlying element goes stale when the window
/// closes.
public struct FocusedWindow: WindowFrameAccess {
    /// Accessibility calls block while the target application is unresponsive. This
    /// bounds every call, so that an app that hangs cannot hang Piccolo with it.
    public static let messagingTimeout: Float = 2

    public let pid: pid_t
    public let appName: String
    private let window: AccessibilityWindow

    /// Finds the focused window of the frontmost application.
    ///
    /// - Throws: ``WindowError/notTrusted``, ``WindowError/noFrontmostApplication``,
    ///   ``WindowError/noFocusedWindow``, or ``WindowError/accessibility(operation:code:)``.
    public static func current(
        permission: AccessibilityPermission = AccessibilityPermission()
    ) throws -> FocusedWindow {
        guard permission.isTrusted else { throw WindowError.notTrusted }
        guard let app = FrontmostApplication.current() else {
            throw WindowError.noFrontmostApplication
        }

        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &value)
        switch error {
        case .success:
            break
        case .noValue, .attributeUnsupported, .invalidUIElement:
            throw WindowError.noFocusedWindow
        default:
            throw WindowError(axError: error, operation: "read \(kAXFocusedWindowAttribute)")
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw WindowError.noFocusedWindow
        }

        // The cast is checked by the type ID above.
        let element = unsafeDowncast(value as AnyObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return FocusedWindow(
            pid: app.pid, appName: app.name ?? app.bundleID ?? "", element: element)
    }

    private init(pid: pid_t, appName: String, element: AXUIElement) {
        self.pid = pid
        self.appName = appName
        self.window = AccessibilityWindow(element: element, whenGone: .noFocusedWindow)
    }

    /// The window's number, which is its identity in ``PiccoloCore/FocusHistory``, or `nil` when the
    /// system gives none and no window of the application matches the frame.
    public var windowID: WindowID? {
        WindowIdentity.id(of: window.element, pid: pid)
    }

    // MARK: WindowFrameAccess

    public func frame() throws -> CGRect {
        try window.frame()
    }

    public func setSize(_ size: CGSize) throws {
        try window.setSize(size)
    }

    public func setPosition(_ origin: CGPoint) throws {
        try window.setPosition(origin)
    }

    /// Moves and resizes the window to `frame` and returns the frame it ended up with.
    /// See ``FrameSetter/apply(_:to:within:)``.
    @discardableResult
    public func setFrame(_ frame: CGRect, within visibleFrame: CGRect? = nil) throws -> CGRect {
        try FrameSetter.apply(frame, to: self, within: visibleFrame)
    }
}
