import Foundation
import Testing

@testable import PiccoloCore

@Suite("Shortcut rules")
struct ShortcutRulesTests {
    /// The macOS virtual key codes of F1 to F20, written out here independently of `FunctionKey`.
    private static let functionKeyTable: [(name: String, code: Int)] = [
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96),
        ("F6", 97), ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109),
        ("F11", 103), ("F12", 111), ("F13", 105), ("F14", 107), ("F15", 113),
        ("F16", 106), ("F17", 64), ("F18", 79), ("F19", 80), ("F20", 90),
    ]

    /// Ordinary keys (not function keys): A, Space, Return, Tab, Delete, Escape, Fn,
    /// Home, Page Up, End, Page Down, the arrow keys, and an unknown negative code.
    private static let ordinaryKeyCodes = [0, 49, 36, 48, 51, 53, 63, 115, 116, 119, 121, 123, 124, 125, 126, -1]

    /// A key code that is not a function key, used where the key itself does not matter.
    private let ordinaryKey = 0

    /// Every set of modifiers, the empty set included.
    private static let allModifierSets: [Set<Modifier>] = (0..<(1 << Modifier.allCases.count)).map { mask in
        Set(Modifier.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
    }

    // MARK: Function keys

    @Test("every key of the table is a function key")
    func functionKeyTable() {
        #expect(Self.functionKeyTable.count == 20)
        for (name, code) in Self.functionKeyTable {
            #expect(FunctionKey.isFunctionKey(code), "\(name) has code \(code) and must be a function key")
        }
    }

    @Test("the named constants hold the codes of the table, F1 first")
    func constantsMatchTable() {
        let constants = [
            FunctionKey.f1, FunctionKey.f2, FunctionKey.f3, FunctionKey.f4, FunctionKey.f5,
            FunctionKey.f6, FunctionKey.f7, FunctionKey.f8, FunctionKey.f9, FunctionKey.f10,
            FunctionKey.f11, FunctionKey.f12, FunctionKey.f13, FunctionKey.f14, FunctionKey.f15,
            FunctionKey.f16, FunctionKey.f17, FunctionKey.f18, FunctionKey.f19, FunctionKey.f20,
        ]
        #expect(constants == Self.functionKeyTable.map(\.code))
    }

    @Test("codes that are not F1 to F20 are not function keys", arguments: ordinaryKeyCodes)
    func nonFunctionKeys(code: Int) {
        #expect(!FunctionKey.isFunctionKey(code), "code \(code) must not be a function key")
    }

    // MARK: Registrable shortcuts

    @Test("command, option or control on an ordinary key is registrable", arguments: [Modifier.command, .option, .control])
    func singleRegistrableModifier(modifier: Modifier) {
        #expect(Shortcut(keyCode: ordinaryKey, modifiers: [modifier]).isRegistrable)
    }

    @Test("shift alone on an ordinary key is not registrable")
    func shiftAlone() {
        #expect(!Shortcut(keyCode: ordinaryKey, modifiers: [.shift]).isRegistrable)
    }

    @Test("an ordinary key with no modifiers is not registrable", arguments: ordinaryKeyCodes)
    func noModifiers(code: Int) {
        #expect(!Shortcut(keyCode: code, modifiers: []).isRegistrable)
    }

    @Test("shift with command, option or control on an ordinary key is registrable")
    func shiftWithAnotherModifier() {
        #expect(Shortcut(keyCode: ordinaryKey, modifiers: [.shift, .command]).isRegistrable)
        #expect(Shortcut(keyCode: ordinaryKey, modifiers: [.shift, .option]).isRegistrable)
        #expect(Shortcut(keyCode: ordinaryKey, modifiers: [.shift, .control]).isRegistrable)
    }

    @Test("an ordinary key is registrable exactly when it has command, option or control, for every modifier set")
    func ordinaryKeyRule() {
        for modifiers in Self.allModifierSets {
            let hasRegistrableModifier = !modifiers.isDisjoint(with: [.command, .option, .control])
            let shortcut = Shortcut(keyCode: ordinaryKey, modifiers: modifiers)
            #expect(
                shortcut.isRegistrable == hasRegistrableModifier,
                "modifiers \(modifiers.map(\.rawValue).sorted()) must give isRegistrable == \(hasRegistrableModifier)")
        }
    }

    @Test("a function key is registrable with no modifiers")
    func functionKeyWithoutModifiers() {
        for (name, code) in Self.functionKeyTable {
            #expect(Shortcut(keyCode: code, modifiers: []).isRegistrable, "\(name) alone must be registrable")
        }
    }

    @Test("a function key is registrable with every modifier set")
    func functionKeyWithAnyModifiers() {
        for (name, code) in Self.functionKeyTable {
            for modifiers in Self.allModifierSets {
                #expect(
                    Shortcut(keyCode: code, modifiers: modifiers).isRegistrable,
                    "\(name) with modifiers \(modifiers.map(\.rawValue).sorted()) must be registrable")
            }
        }
    }

    @Test("a function key with shift alone is registrable")
    func functionKeyWithShift() {
        #expect(Shortcut(keyCode: FunctionKey.f1, modifiers: [.shift]).isRegistrable)
    }
}
