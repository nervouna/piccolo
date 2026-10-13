import ApplicationServices
import Foundation

/// Why a window could not be read or changed.
public enum WindowError: Error, Equatable, LocalizedError {
    /// The process is not trusted for Accessibility.
    case notTrusted
    /// No application is frontmost.
    case noFrontmostApplication
    /// The frontmost application has no focused window.
    case noFocusedWindow
    /// The frontmost application is Piccolo itself (its Settings window has the focus). Piccolo
    /// never moves its own windows: an Accessibility request to the calling process is answered
    /// on the calling thread, and AppKit stops a window change that does not come from the main
    /// thread, where actions never run.
    case ownWindow
    /// The window refuses changes to this attribute (for example `AXSize` of a
    /// window that cannot be resized).
    case attributeNotSettable(String)
    /// Any other Accessibility failure, with the failed operation and the raw
    /// `AXError` code.
    case accessibility(operation: String, code: Int32)

    /// Maps an `AXError` from `operation` to a typed error.
    init(axError: AXError, operation: String) {
        switch axError {
        case .apiDisabled:
            self = .notTrusted
        default:
            self = .accessibility(operation: operation, code: axError.rawValue)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Accessibility access is not granted to this process"
        case .noFrontmostApplication:
            return "no application is frontmost"
        case .noFocusedWindow:
            return "the frontmost application has no focused window"
        case .ownWindow:
            return "the frontmost application is Piccolo itself, which does not move its own windows"
        case .attributeNotSettable(let attribute):
            return "the focused window does not allow changing \(attribute)"
        case .accessibility(let operation, let code):
            return "Accessibility call failed: \(operation) (AXError \(code))"
        }
    }
}
