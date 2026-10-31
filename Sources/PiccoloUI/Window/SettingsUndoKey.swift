import PiccoloCore

/// The key presses that undo and redo in the Settings window: ⌘Z and ⇧⌘Z. Piccolo has no Edit menu
/// to give them to, so the window recognises them itself (see `SettingsWindowController`).
enum SettingsUndoKey {
    enum Command: Equatable, Sendable {
        case undo
        case redo
    }

    /// The key code of the key that types Z on a US keyboard (`kVK_ANSI_Z`).
    static let zKeyCode = 6

    /// What a key press asks for, or `nil` when it is neither ⌘Z nor ⇧⌘Z. No other modifier may be held
    /// (⌥⌘Z and ⌃⌘Z are not undo).
    ///
    /// - Parameters:
    ///   - characters: What the key types on the current layout, ignoring the modifiers but Shift. The
    ///     key is the one that types Z there: on AZERTY it is not the key of a US keyboard's Z. A layout
    ///     with no Latin letters types something else; macOS matches ⌘ shortcuts by the US key then, so
    ///     that is what this does.
    ///   - keyCode: The virtual key code of the press.
    ///   - modifiers: The modifiers held, Caps Lock and the like left out.
    static func command(characters: String?, keyCode: Int, modifiers: Set<Modifier>) -> Command? {
        guard modifiers == [.command] || modifiers == [.command, .shift] else { return nil }
        guard isZ(characters: characters, keyCode: keyCode) else { return nil }
        return modifiers.contains(.shift) ? .redo : .undo
    }

    private static func isZ(characters: String?, keyCode: Int) -> Bool {
        let typed = characters?.lowercased() ?? ""
        if typed.count == 1, let scalar = typed.unicodeScalars.first, scalar.isASCII, scalar.properties.isAlphabetic {
            return typed == "z"
        }
        return keyCode == zKeyCode
    }
}
