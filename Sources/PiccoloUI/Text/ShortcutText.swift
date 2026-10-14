import Foundation
import PiccoloCore

/// How a shortcut is written: the modifiers in the order ⌃⌥⇧⌘, then the name of the key.
///
/// The pure part. Which character a key produces depends on the keyboard layout, so the
/// lookup is a parameter; ``KeyboardLayout`` is the live one.
///
/// The symbols (⌃⌥⇧⌘, the arrows and the like) and the function key names (F13) are the same in
/// every language. The few keys that are spelled out (Space, Help, Keypad 5) are looked up in
/// PiccoloUI's string catalog, in the language of `bundle`: the running app's by default.
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
    public static func string(
        for shortcut: Shortcut, bundle: Bundle = AppLanguage.currentTextBundle, character: (Int) -> String?
    ) -> String {
        modifierSymbols(shortcut.modifiers) + keyName(shortcut.keyCode, bundle: bundle, character: character)
    }

    /// The name of one key: from the table of special keys when it is there, otherwise the
    /// character from the layout in capitals, otherwise "Key <code>".
    public static func keyName(
        _ keyCode: Int, bundle: Bundle = AppLanguage.currentTextBundle, character: (Int) -> String?
    ) -> String {
        if let name = symbolKeys[keyCode] ?? spelledOutName(of: keyCode, bundle: bundle) {
            return name
        }
        if let text = character(keyCode), !text.isEmpty {
            return text.uppercased()
        }
        return String(localized: "Key \(keyCode)", bundle: bundle)
    }

    /// Keys that are named, not typed, and whose name is a symbol or a function key number, so that
    /// it reads the same in every language.
    static let symbolKeys: [Int: String] = {
        var keys: [Int: String] = [
            36: "↩",  // Return
            48: "⇥",  // Tab
            51: "⌫",  // Delete (backspace)
            53: "⎋",  // Escape
            115: "↖",  // Home
            116: "⇞",  // Page Up
            117: "⌦",  // Forward Delete
            119: "↘",  // End
            121: "⇟",  // Page Down
            123: "←",
            124: "→",
            125: "↓",
            126: "↑",
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

    /// The keypad keys: they produce the same character as a key on the main block, so they are
    /// named by the key they are.
    private static let keypadKeys: [Int: String] = [
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        65: ".", 67: "*", 69: "+", 75: "/", 78: "-", 81: "=",
    ]

    /// Keys that are spelled out in words, which are translated.
    private static func spelledOutName(of keyCode: Int, bundle: Bundle) -> String? {
        switch keyCode {
        case 49: return String(localized: "Space", bundle: bundle)
        case 71: return String(localized: "Clear", bundle: bundle)  // Keypad clear
        case 76: return String(localized: "Enter", bundle: bundle)  // Keypad enter
        case 114: return String(localized: "Help", bundle: bundle)
        default: break
        }
        guard let key = keypadKeys[keyCode] else { return nil }
        return String(localized: "Keypad \(key)", bundle: bundle)
    }

    // MARK: Keys the recorder treats specially

    /// Escape (`kVK_Escape`): pressed alone it cancels a recording.
    public static let escapeKeyCode = 53
    /// Delete (`kVK_Delete`) and Forward Delete (`kVK_ForwardDelete`): pressed alone they clear
    /// the shortcut that is being recorded.
    public static let deleteKeyCodes: Set<Int> = [51, 117]
}
