import Foundation
import PiccoloCore

/// The sentences the model shows for rejected edits. The model validates in terms of the
/// config file (fractions); the window talks in percentages.
///
/// Every sentence is looked up in PiccoloUI's string catalog, in the language of `bundle`: the
/// running app's by default, and a given language's `AppLanguage/textBundle` when a test wants to
/// read a translation. The texts of ``ValidationError`` cases that no sentence is written for come
/// from PiccoloCore and are not translated.
enum SettingsMessages {
    /// What a validation failure means for the person editing.
    static func describe(_ error: ValidationError, bundle: Bundle = .module) -> String {
        switch error {
        case .notFinite(let field):
            return String(localized: "\(label(of: field, bundle: bundle)) must be a number.", bundle: bundle)
        case .outOfRange(let field, let rule):
            switch (field, rule) {
            case ("x", _): return String(localized: "Left must be 0% or more.", bundle: bundle)
            case ("y", _): return String(localized: "Top must be 0% or more.", bundle: bundle)
            case ("width", _): return String(localized: "Width must be more than 0%.", bundle: bundle)
            case ("height", _): return String(localized: "Height must be more than 0%.", bundle: bundle)
            case ("x + width", _):
                return String(localized: "Left plus width must not be more than 100%.", bundle: bundle)
            case ("y + height", _):
                return String(localized: "Top plus height must not be more than 100%.", bundle: bundle)
            case ("rows", _): return String(localized: "Rows must be at least 1.", bundle: bundle)
            case ("columns", _): return String(localized: "Columns must be at least 1.", bundle: bundle)
            case ("count", "must be >= 1"):
                return String(localized: "The number of windows must be at least 1.", bundle: bundle)
            case ("count", _):
                return String(localized: "The number of windows cannot be more than rows × columns.", bundle: bundle)
            case ("resizeStep", _):
                return String(localized: "The resize step must be more than 0% and at most 50%.", bundle: bundle)
            case ("gap", _):
                return String(localized: "The window gap must be a whole number from 0 to 64 pt.", bundle: bundle)
            default: return "\(field) \(rule)."
            }
        case .duplicateBindingID, .unsupportedVersion:
            return "\(error)."
        }
    }

    /// The name of a field of the model as the window calls it.
    private static func label(of field: String, bundle: Bundle) -> String {
        switch field {
        case "x": String(localized: "Left", bundle: bundle)
        case "y": String(localized: "Top", bundle: bundle)
        case "width": String(localized: "Width", bundle: bundle)
        case "height": String(localized: "Height", bundle: bundle)
        case "resizeStep": String(localized: "The resize step", bundle: bundle)
        default: field.prefix(1).uppercased() + field.dropFirst()
        }
    }

    static func bindingGone(bundle: Bundle = .module) -> String {
        String(localized: "That binding no longer exists.", bundle: bundle)
    }

    static func notRegistrable(_ text: String, bundle: Bundle = .module) -> String {
        String(
            localized: "\(text) cannot be a global shortcut: it needs ⌃, ⌥ or ⌘, or has to be a function key.",
            bundle: bundle)
    }

    /// The system refused to register (`enabling`) or unregister Piccolo as a login item.
    static func loginItemFailed(enabling: Bool, reason: String, bundle: Bundle = .module) -> String {
        switch (enabling, reason.isEmpty) {
        case (true, true): String(localized: "Launch at login could not be turned on.", bundle: bundle)
        case (true, false): String(localized: "Launch at login could not be turned on: \(reason)", bundle: bundle)
        case (false, true): String(localized: "Launch at login could not be turned off.", bundle: bundle)
        case (false, false): String(localized: "Launch at login could not be turned off: \(reason)", bundle: bundle)
        }
    }

    static func alreadyUsed(_ text: String, by summary: String, bundle: Bundle = .module) -> String {
        String(localized: "\(text) is already used by \(summary).", bundle: bundle)
    }

    /// A change that the backend could not save; `reason` is the backend's own words.
    static func notSaved(_ reason: String, bundle: Bundle = .module) -> String {
        String(localized: "The change could not be saved: \(reason)", bundle: bundle)
    }

    /// The restart that applies a new language could not be arranged.
    static func restartFailed(_ reason: String, bundle: Bundle = .module) -> String {
        String(localized: "Piccolo could not restart: \(reason)", bundle: bundle)
    }
}
