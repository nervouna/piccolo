import ApplicationServices
import CoreGraphics
import Foundation

/// A window reached through its Accessibility element: reads and sets its frame.
///
/// AXPosition and AXSize are already in canonical coordinates (global, top-left origin of the
/// primary display, y down), so frames cross this boundary unchanged.
///
/// The element goes stale when the window closes; ``FocusedWindow`` and the window catalog both
/// build on this type, and differ in what a stale element is reported as (`whenGone`).
struct AccessibilityWindow: WindowFrameAccess {
    let element: AXUIElement
    /// What a stale element or a missing value is reported as.
    private let whenGone: WindowError

    init(element: AXUIElement, whenGone: WindowError) {
        self.element = element
        self.whenGone = whenGone
    }

    // MARK: WindowFrameAccess

    func frame() throws -> CGRect {
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

    func setSize(_ size: CGSize) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw malformedValue(kAXSizeAttribute)
        }
        try writeValue(value, to: kAXSizeAttribute)
    }

    func setPosition(_ origin: CGPoint) throws {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else {
            throw malformedValue(kAXPositionAttribute)
        }
        try writeValue(value, to: kAXPositionAttribute)
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
            throw whenGone
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
            throw whenGone
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
            throw whenGone
        default:
            throw WindowError(axError: error, operation: "set \(attribute)")
        }
    }
}
