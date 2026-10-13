import ApplicationServices
import CoreGraphics
import Foundation

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
    private let element: AXUIElement

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
        let window = unsafeDowncast(value as AnyObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        return FocusedWindow(
            pid: app.pid, appName: app.name ?? app.bundleID ?? "", element: window)
    }

    private init(pid: pid_t, appName: String, element: AXUIElement) {
        self.pid = pid
        self.appName = appName
        self.element = element
    }

    // MARK: WindowFrameAccess

    public func frame() throws -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        let position = try readValue(kAXPositionAttribute)
        let extent = try readValue(kAXSizeAttribute)
        guard AXValueGetValue(position, .cgPoint, &origin) else {
            throw malformedValue(kAXPositionAttribute)
        }
        guard AXValueGetValue(extent, .cgSize, &size) else {
            throw malformedValue(kAXSizeAttribute)
        }
        return CGRect(origin: origin, size: size)
    }

    public func setSize(_ size: CGSize) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw malformedValue(kAXSizeAttribute)
        }
        try writeValue(value, to: kAXSizeAttribute)
    }

    public func setPosition(_ origin: CGPoint) throws {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else {
            throw malformedValue(kAXPositionAttribute)
        }
        try writeValue(value, to: kAXPositionAttribute)
    }

    /// Moves and resizes the window to `frame` and returns the frame it ended up with.
    /// See ``FrameSetter/apply(_:to:within:)``.
    @discardableResult
    public func setFrame(_ frame: CGRect, within visibleFrame: CGRect? = nil) throws -> CGRect {
        try FrameSetter.apply(frame, to: self, within: visibleFrame)
    }

    // MARK: Accessibility plumbing

    private func malformedValue(_ attribute: String) -> WindowError {
        .accessibility(operation: "convert \(attribute)", code: AXError.illegalArgument.rawValue)
    }

    private func readValue(_ attribute: String) throws -> AXValue {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        switch error {
        case .success:
            break
        case .invalidUIElement, .noValue:
            throw WindowError.noFocusedWindow
        default:
            throw WindowError(axError: error, operation: "read \(attribute)")
        }
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else {
            throw malformedValue(attribute)
        }
        // The cast is checked by the type ID above.
        return unsafeDowncast(raw as AnyObject, to: AXValue.self)
    }

    private func writeValue(_ value: AXValue, to attribute: String) throws {
        var settable: DarwinBoolean = false
        let settableError = AXUIElementIsAttributeSettable(
            element, attribute as CFString, &settable)
        switch settableError {
        case .success:
            guard settable.boolValue else { throw WindowError.attributeNotSettable(attribute) }
        case .attributeUnsupported, .noValue:
            throw WindowError.attributeNotSettable(attribute)
        case .invalidUIElement:
            throw WindowError.noFocusedWindow
        default:
            throw WindowError(axError: settableError, operation: "check \(attribute)")
        }

        let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        switch error {
        case .success:
            break
        case .attributeUnsupported:
            throw WindowError.attributeNotSettable(attribute)
        case .invalidUIElement:
            throw WindowError.noFocusedWindow
        default:
            throw WindowError(axError: error, operation: "set \(attribute)")
        }
    }
}
