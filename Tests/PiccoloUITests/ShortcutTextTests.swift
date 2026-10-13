import Testing

import PiccoloCore

@testable import PiccoloUI

@Suite("Shortcut text")
struct ShortcutTextTests {
    /// A layout with a few characters: A, S, the comma and the digit 1.
    private let layout: (Int) -> String? = { code in
        [0: "a", 1: "s", 43: ",", 18: "1"][code]
    }

    private func text(_ keyCode: Int, _ modifiers: Set<Modifier>) -> String {
        ShortcutText.string(for: Shortcut(keyCode: keyCode, modifiers: modifiers), character: layout)
    }

    @Test("modifiers come in the order control, option, shift, command")
    func modifierOrder() {
        #expect(ShortcutText.modifierSymbols([.command, .shift, .option, .control]) == "⌃⌥⇧⌘")
        #expect(ShortcutText.modifierSymbols([.command, .control]) == "⌃⌘")
        #expect(ShortcutText.modifierSymbols([.shift]) == "⇧")
        #expect(ShortcutText.modifierSymbols([]) == "")
    }

    @Test("a function key with all four modifiers")
    func hyperF14() {
        #expect(text(FunctionKey.f14, [.control, .option, .shift, .command]) == "⌃⌥⇧⌘F14")
    }

    @Test("F1 to F20 are named by number")
    func functionKeys() {
        let codes = [
            FunctionKey.f1, FunctionKey.f2, FunctionKey.f3, FunctionKey.f4, FunctionKey.f5,
            FunctionKey.f6, FunctionKey.f7, FunctionKey.f8, FunctionKey.f9, FunctionKey.f10,
            FunctionKey.f11, FunctionKey.f12, FunctionKey.f13, FunctionKey.f14, FunctionKey.f15,
            FunctionKey.f16, FunctionKey.f17, FunctionKey.f18, FunctionKey.f19, FunctionKey.f20,
        ]
        for (index, code) in codes.enumerated() {
            #expect(text(code, []) == "F\(index + 1)")
        }
    }

    @Test("special keys come from the table", arguments: [
        (123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
        (36, "↩"), (49, "Space"), (48, "⇥"), (51, "⌫"), (117, "⌦"), (53, "⎋"),
        (115, "↖"), (119, "↘"), (116, "⇞"), (121, "⇟"), (114, "Help"),
        (76, "Enter"), (82, "Keypad 0"), (92, "Keypad 9"), (69, "Keypad +"),
    ] as [(Int, String)])
    func specialKeys(_ keyCode: Int, _ name: String) {
        #expect(text(keyCode, []) == name)
        #expect(text(keyCode, [.command]) == "⌘" + name)
    }

    @Test("the table wins over the keyboard layout")
    func tableBeforeLayout() {
        let everything: (Int) -> String? = { _ in "x" }
        #expect(ShortcutText.keyName(123, character: everything) == "←")
        #expect(ShortcutText.keyName(FunctionKey.f5, character: everything) == "F5")
    }

    @Test("character keys come from the layout, in capitals")
    func characterKeys() {
        #expect(text(0, [.command]) == "⌘A")
        #expect(text(1, [.control, .shift]) == "⌃⇧S")
        #expect(text(43, [.command]) == "⌘,")
        #expect(text(18, [.option]) == "⌥1")
    }

    @Test("a key without a character is named by its code")
    func unknownKey() {
        #expect(text(200, [.command]) == "⌘Key 200")
    }

    @Test("an empty answer from the layout counts as no character")
    func emptyCharacter() {
        #expect(ShortcutText.keyName(7, character: { _ in "" }) == "Key 7")
    }

    @Test("the keys the recorder treats specially are Escape and the two delete keys")
    func recorderKeys() {
        #expect(ShortcutText.escapeKeyCode == 53)
        #expect(ShortcutText.deleteKeyCodes == [51, 117])
    }
}

@MainActor
@Suite("Keyboard layout")
struct KeyboardLayoutTests {
    @Test("the live layout names the letter keys")
    func letterKeys() {
        // Whatever the layout, key code 0 (the A position) produces a character.
        let character = KeyboardLayout.character(forKeyCode: 0)
        #expect(character?.isEmpty == false)
    }

    @Test("a key code outside the key range produces nothing")
    func outOfRange() {
        #expect(KeyboardLayout.character(forKeyCode: -1) == nil)
        #expect(KeyboardLayout.character(forKeyCode: 70_000) == nil)
    }
}
