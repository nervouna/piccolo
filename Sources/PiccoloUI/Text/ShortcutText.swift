import PiccoloCore

/// How a shortcut is written: the modifiers in the order ⌃⌥⇧⌘, then the name of the key.
///
/// The pure part. Which character a key produces depends on the keyboard layout, so the
/// lookup is a parameter; ``KeyboardLayout`` is the live one.
public enum ShortcutText {
    /// The modifiers as symbols in the order ⌃⌥⇧⌘; empty for none.
    public static func modifierSymbols(_ modifiers: Set<Modifier>) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text
    }

    /// The text of `shortcut`, for example "⌃⌥⇧⌘F14" or "⌘←".
    ///
    /// - Parameter character: The character the key produces on the current keyboard layout, or
    ///   `nil` when it produces none. It is asked for keys that are not in the table of special
    ///   keys only.
    public static func string(for shortcut: Shortcut, character: (Int) -> String?) -> String {
        modifierSymbols(shortcut.modifiers) + keyName(shortcut.keyCode, character: character)
    }

    /// The name of one key: from the table of special keys when it is there, otherwise the
    /// character from the layout in capitals, otherwise "Key <code>".
    public static func keyName(_ keyCode: Int, character: (Int) -> String?) -> String {
        if let name = specialKeys[keyCode] {
            return name
        }
        if let text = character(keyCode), !text.isEmpty {
            return text.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// Keys that are named, not typed: they do not produce a character, or produce the same one
    /// as another key (the keypad).
    static let specialKeys: [Int: String] = {
        var keys: [Int: String] = [
            36: "↩",  // Return
            48: "⇥",  // Tab
            49: "Space",
            51: "⌫",  // Delete (backspace)
            53: "⎋",  // Escape
            71: "Clear",  // Keypad clear
            76: "Enter",  // Keypad enter
            114: "Help",
            115: "↖",  // Home
            116: "⇞",  // Page Up
            117: "⌦",  // Forward Delete
            119: "↘",  // End
            121: "⇟",  // Page Down
            123: "←",
            124: "→",
            125: "↓",
            126: "↑",
            // Keypad.
            82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
            87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
            65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 75: "Keypad /", 78: "Keypad -",
            81: "Keypad =",
        ]
        let functionKeys = [
            FunctionKey.f1, FunctionKey.f2, FunctionKey.f3, FunctionKey.f4, FunctionKey.f5,
            FunctionKey.f6, FunctionKey.f7, FunctionKey.f8, FunctionKey.f9, FunctionKey.f10,
            FunctionKey.f11, FunctionKey.f12, FunctionKey.f13, FunctionKey.f14, FunctionKey.f15,
            FunctionKey.f16, FunctionKey.f17, FunctionKey.f18, FunctionKey.f19, FunctionKey.f20,
        ]
        for (index, code) in functionKeys.enumerated() {
            keys[code] = "F\(index + 1)"
        }
        return keys
    }()

    // MARK: Keys the recorder treats specially

    /// Escape (`kVK_Escape`): pressed alone it cancels a recording.
    public static let escapeKeyCode = 53
    /// Delete (`kVK_Delete`) and Forward Delete (`kVK_ForwardDelete`): pressed alone they clear
    /// the shortcut that is being recorded.
    public static let deleteKeyCodes: Set<Int> = [51, 117]
}
