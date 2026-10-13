import ApplicationServices
import CoreGraphics
import Foundation

/// Reads the windows of one application through Accessibility.
enum AccessibilityWindows {
    /// The attributes read for every window, in this order, with one request per window.
    private static let attributes: [String] = [
        kAXPositionAttribute, kAXSizeAttribute, kAXSubroleAttribute, kAXMinimizedAttribute,
        // The constant for this attribute is missing from some SDKs.
        "AXFullScreen",
    ]

    /// The windows `pid` lists as its own: standard or not, minimized or not.
    ///
    /// Every call to the application is cut off after `timeout` seconds.
    ///
    /// - Returns: `nil` when the application does not answer (it is hung, does not support
    ///   Accessibility, or is not a graphical application). A window that cannot be read is left
    ///   out; the others are still returned.
    static func read(pid: pid_t, timeout: Float) -> [AccessibleWindow]? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }
        // The cast is checked by the type ID above.
        let list = unsafeDowncast(value as AnyObject, to: CFArray.self)

        // An application that answered for its window list but then stops answering must not cost a
        // timeout per window: after a few timeouts' worth of time the rest of its windows are skipped.
        let started = ContinuousClock.now
        let budget = Duration.seconds(Double(timeout) * 3)

        var windows: [AccessibleWindow] = []
        for index in 0..<CFArrayGetCount(list) {
            if started.duration(to: .now) > budget { break }
            let item = unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: CFTypeRef.self)
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { continue }
            // The cast is checked by the type ID above.
            let element = unsafeDowncast(item as AnyObject, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(element, timeout)
            if let window = describe(element) {
                windows.append(window)
            }
        }
        return windows
    }

    /// One window, from a single request for all attributes.
    private static func describe(_ element: AXUIElement) -> AccessibleWindow? {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        guard error == .success, let values, CFArrayGetCount(values) == attributes.count else {
            return nil
        }
        func value(_ index: Int) -> CFTypeRef? {
            let item = unsafeBitCast(CFArrayGetValueAtIndex(values, index), to: CFTypeRef.self)
            // An attribute that cannot be read comes back as an AXValue holding the error.
            if CFGetTypeID(item) == AXValueGetTypeID(),
                AXValueGetType(unsafeDowncast(item as AnyObject, to: AXValue.self)) == .axError
            {
                return nil
            }
            return item
        }

        guard let position = value(0).flatMap({ point(from: $0) }),
            let size = value(1).flatMap({ extent(from: $0) })
        else { return nil }

        // The handle is the element itself. A closed window reports `windowGone`, and the
        // timeout is the one for actions, now that enumerating is over.
        AXUIElementSetMessagingTimeout(element, FocusedWindow.messagingTimeout)
        return AccessibleWindow(
            number: WindowNumber.of(element),
            frame: CGRect(origin: position, size: size),
            isStandard: (value(2) as? String) == kAXStandardWindowSubrole,
            isMinimized: bool(value(3)),
            isFullScreen: bool(value(4)),
            handle: AccessibilityWindow(element: element, whenGone: .windowGone))
    }

    private static func point(from item: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(item) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(item as AnyObject, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetType(value) == .cgPoint, AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func extent(from item: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(item) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(item as AnyObject, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetType(value) == .cgSize, AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private static func bool(_ item: CFTypeRef?) -> Bool {
        guard let item, CFGetTypeID(item) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue(unsafeDowncast(item as AnyObject, to: CFBoolean.self))
    }
}
