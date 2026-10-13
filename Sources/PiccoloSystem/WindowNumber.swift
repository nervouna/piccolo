import ApplicationServices
import CoreGraphics
import PiccoloCore

/// Private API: the window number (the `CGWindowID` the window server uses) behind an Accessibility
/// window element.
///
/// `_AXUIElementGetWindow` is not declared in any public header, but it has been stable for well over
/// a decade and every window manager for macOS that matches Accessibility windows to window server
/// windows relies on it. This is the only declaration of it in the project. Using a private symbol
/// rules out the Mac App Store, which is already a non-goal (see "Product scope" in `CLAUDE.md`).
///
/// Do not call it from anywhere else: go through ``WindowNumber``.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError

/// Identifies Accessibility windows by their window number.
enum WindowNumber {
    /// The window number of `element`, or `nil` when the system does not give one (the call fails
    /// for some windows, or reports 0, which is no window).
    static func of(_ element: AXUIElement) -> WindowID? {
        var number: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &number) == .success, number != 0 else { return nil }
        return WindowID(rawValue: number)
    }
}
