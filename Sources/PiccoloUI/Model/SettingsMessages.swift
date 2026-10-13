import PiccoloCore

/// The sentences the model shows for rejected edits. The model validates in terms of the
/// config file (fractions); the window talks in percentages.
enum SettingsMessages {
    /// What a validation failure means for the person editing.
    static func describe(_ error: ValidationError) -> String {
        switch error {
        case .notFinite(let field):
            return "\(label(of: field)) must be a number."
        case .outOfRange(let field, let rule):
            switch (field, rule) {
            case ("x", _): return "Left must be 0% or more."
            case ("y", _): return "Top must be 0% or more."
            case ("width", _): return "Width must be more than 0%."
            case ("height", _): return "Height must be more than 0%."
            case ("x + width", _): return "Left plus width must not be more than 100%."
            case ("y + height", _): return "Top plus height must not be more than 100%."
            case ("rows", _): return "Rows must be at least 1."
            case ("columns", _): return "Columns must be at least 1."
            case ("count", "must be >= 1"): return "The number of windows must be at least 1."
            case ("count", _): return "The number of windows cannot be more than rows × columns."
            case ("resizeStep", _): return "The resize step must be more than 0% and at most 50%."
            default: return "\(field) \(rule)."
            }
        case .duplicateBindingID, .unsupportedVersion:
            return "\(error)."
        }
    }

    /// The name of a field of the model as the window calls it.
    private static func label(of field: String) -> String {
        switch field {
        case "x": "Left"
        case "y": "Top"
        case "width": "Width"
        case "height": "Height"
        case "resizeStep": "The resize step"
        default: field.prefix(1).uppercased() + field.dropFirst()
        }
    }

    static let bindingGone = "That binding no longer exists."

    static func notRegistrable(_ text: String) -> String {
        "\(text) cannot be a global shortcut: it needs ⌃, ⌥ or ⌘, or has to be a function key."
    }

    /// The system refused to register (`enabling`) or unregister Piccolo as a login item.
    static func loginItemFailed(enabling: Bool, reason: String) -> String {
        let sentence = "Launch at login could not be turned \(enabling ? "on" : "off")"
        return reason.isEmpty ? "\(sentence)." : "\(sentence): \(reason)"
    }

    static func alreadyUsed(_ text: String, by summary: String) -> String {
        "\(text) is already used by \(summary)."
    }
}
