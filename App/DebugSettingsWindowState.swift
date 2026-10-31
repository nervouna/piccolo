#if DEBUG
import AppKit
import PiccoloControl
import PiccoloCore
import PiccoloUI

/// What the debug control channel says about the Settings window itself, beyond the model:
/// the fields `settings.state` adds, and `settings.moveWindow`, which puts the window on a display.
///
/// Like the rest of the control channel, this file is compiled out of Release builds.
extension DebugControlServer {
    nonisolated static func registerSettingsWindowCommands(in router: inout ControlRouter) {
        // Moves the open window to the top-left corner of the visible frame of a display (the index in the
        // `displays` answer, the primary display first) and fits it to that display: the window is never
        // taller than the display's visible frame. Answers the window fields of `settings.state`. It is
        // how a test looks at the window on each display.
        router.register("settings.moveWindow") { params in
            let display = try params.decode(DisplayParams.self).display
            return try onMainActor {
                guard SettingsController.shared.moveWindow(toDisplayAt: display) else {
                    throw ControlCommandError.failed(
                        "the Settings window is not open, or there is no display \(display)")
                }
                return .object(settingsWindowState())
            }
        }
    }

    /// The window fields of `settings.state`:
    ///
    /// - `windowFrame`: `{x, y, width, height}` of the window in canonical space (the origin at the top
    ///   left of the primary display, y down), when it is open.
    /// - `windowTitle`: the title of the window, once it exists.
    /// - `firstResponder`: `"none"` when the window itself or nothing is the first responder, `"textField"`
    ///   for a text field or the field editor of one, `"other"` for anything else.
    /// - `contentFits`: whether the selected tab's content fits its visible area without scrolling, when the
    ///   window is open.
    @MainActor
    static func settingsWindowState() -> [String: JSONValue] {
        let settings = SettingsController.shared
        var state: [String: JSONValue] = ["firstResponder": .string(settings.firstResponder.rawValue)]
        if let frame = settings.windowFrame, let primary = NSScreen.screens.first {
            let canonical = ScreenSpace.canonicalRect(
                fromAppKit: frame, primaryDisplayHeight: primary.frame.height)
            state["windowFrame"] = JSONValue(rect: canonical)
        }
        if let title = settings.windowTitle {
            state["windowTitle"] = .string(title)
        }
        if let fits = settings.contentFits {
            state["contentFits"] = .bool(fits)
        }
        return state
    }

    private struct DisplayParams: Decodable {
        var display: Int
    }
}
#endif
