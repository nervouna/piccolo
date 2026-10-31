import Foundation
import Testing

@testable import PiccoloCore

/// The default shortcuts that a new install starts with: the table of the README, exactly, in order.
@Suite("Default shortcuts")
struct DefaultShortcutsTests {
    /// One row of the table: the action, the key code and the modifiers of its shortcut.
    private struct Row: Equatable, CustomStringConvertible {
        let action: Action
        let keyCode: Int
        let modifiers: Set<Modifier>

        var description: String {
            "\(action) \(keyCode) \(modifiers.map(\.rawValue).sorted())"
        }
    }

    private static let controlOption: Set<Modifier> = [.control, .option]
    private static let controlOptionCommand: Set<Modifier> = [.control, .option, .command]
    private static let controlOptionShift: Set<Modifier> = [.control, .option, .shift]

    /// The table of the issue, in order: Left Half first, the custom area last.
    private static let table: [Row] = [
        Row(action: .placeWindow(.preset(.leftHalf)), keyCode: 4, modifiers: controlOption),  // ⌃⌥H
        Row(action: .placeWindow(.preset(.rightHalf)), keyCode: 37, modifiers: controlOption),  // ⌃⌥L
        Row(action: .placeWindow(.preset(.topLeft)), keyCode: 32, modifiers: controlOption),  // ⌃⌥U
        Row(action: .placeWindow(.preset(.topRight)), keyCode: 34, modifiers: controlOption),  // ⌃⌥I
        Row(action: .placeWindow(.preset(.bottomLeft)), keyCode: 38, modifiers: controlOption),  // ⌃⌥J
        Row(action: .placeWindow(.preset(.bottomRight)), keyCode: 40, modifiers: controlOption),  // ⌃⌥K
        Row(action: .placeWindow(.preset(.leftThird)), keyCode: 0, modifiers: controlOption),  // ⌃⌥A
        Row(action: .placeWindow(.preset(.centerThird)), keyCode: 1, modifiers: controlOption),  // ⌃⌥S
        Row(action: .placeWindow(.preset(.rightThird)), keyCode: 2, modifiers: controlOption),  // ⌃⌥D
        Row(action: .placeWindow(.preset(.leftTwoThirds)), keyCode: 12, modifiers: controlOption),  // ⌃⌥Q
        Row(action: .placeWindow(.preset(.rightTwoThirds)), keyCode: 14, modifiers: controlOption),  // ⌃⌥E
        Row(action: .placeWindow(.preset(.maximize)), keyCode: 15, modifiers: controlOption),  // ⌃⌥R
        Row(action: .placeWindow(.preset(.center)), keyCode: 8, modifiers: controlOption),  // ⌃⌥C
        Row(action: .restoreWindow, keyCode: 51, modifiers: controlOption),  // ⌃⌥⌫
        Row(action: .moveToDisplay(.next), keyCode: 30, modifiers: controlOption),  // ⌃⌥]
        Row(action: .moveToDisplay(.previous), keyCode: 33, modifiers: controlOption),  // ⌃⌥[
        Row(action: .moveToDisplay(.left), keyCode: 123, modifiers: controlOptionCommand),  // ⌃⌥⌘←
        Row(action: .moveToDisplay(.right), keyCode: 124, modifiers: controlOptionCommand),  // ⌃⌥⌘→
        Row(action: .moveToDisplay(.up), keyCode: 126, modifiers: controlOptionCommand),  // ⌃⌥⌘↑
        Row(action: .moveToDisplay(.down), keyCode: 125, modifiers: controlOptionCommand),  // ⌃⌥⌘↓
        Row(
            action: .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), keyCode: 19,
            modifiers: controlOption),  // ⌃⌥2
        Row(
            action: .arrangeGrid(GridSpec(count: 3, rows: 1, columns: 3)), keyCode: 20,
            modifiers: controlOption),  // ⌃⌥3
        Row(
            action: .arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2)), keyCode: 21,
            modifiers: controlOption),  // ⌃⌥4
        Row(
            action: .arrangeGrid(GridSpec(count: 6, rows: 2, columns: 3)), keyCode: 22,
            modifiers: controlOption),  // ⌃⌥6
        Row(action: .moveDivider(.left), keyCode: 27, modifiers: controlOption),  // ⌃⌥-
        Row(action: .moveDivider(.right), keyCode: 24, modifiers: controlOption),  // ⌃⌥=
        Row(action: .moveDivider(.up), keyCode: 27, modifiers: controlOptionShift),  // ⌃⌥⇧-
        Row(action: .moveDivider(.down), keyCode: 24, modifiers: controlOptionShift),  // ⌃⌥⇧=
        Row(action: .swapWindow(.left), keyCode: 123, modifiers: controlOption),  // ⌃⌥←
        Row(action: .swapWindow(.right), keyCode: 124, modifiers: controlOption),  // ⌃⌥→
        Row(action: .swapWindow(.up), keyCode: 126, modifiers: controlOption),  // ⌃⌥↑
        Row(action: .swapWindow(.down), keyCode: 125, modifiers: controlOption),  // ⌃⌥↓
        Row(
            action: .placeWindow(.custom(FractionalRect(x: 0.25, y: 0.1, width: 0.5, height: 0.65))),
            keyCode: 13, modifiers: controlOption),  // ⌃⌥W
    ]

    /// The rows of a config, as the table describes them.
    private func rows(_ config: Config) -> [Row] {
        config.bindings.map { binding in
            Row(
                action: binding.action,
                keyCode: binding.shortcut?.keyCode ?? -1,
                modifiers: binding.shortcut?.modifiers ?? [])
        }
    }

    @Test("the defaults are version 1 with the default resize step")
    func versionAndStep() {
        #expect(Config.defaultShortcuts.version == 1)
        #expect(Config.defaultShortcuts.resizeStep == 0.05)
    }

    @Test("the defaults carry Medium animation, columns-first grids, a 16 pt gap and the destination preview")
    func settingsDefaults() {
        #expect(Config.defaultShortcuts.animation == .medium)
        #expect(Config.defaultShortcuts.gridFillOrder == .columns)
        #expect(Config.defaultShortcuts.gap == 16)
        #expect(Config.defaultShortcuts.destinationPreview == true)
    }

    @Test("the settings defaults are the values a missing key falls back to")
    func settingsDefaultsAreTheFallbacks() {
        #expect(Config.defaultAnimation == .medium)
        #expect(Config.defaultGridFillOrder == .columns)
        #expect(Config.defaultGap == 16)
        #expect(WindowGap.default == 16)
        #expect(Config.defaultResizeStep == 0.05)
        #expect(Config.defaultDestinationPreview == true)
        #expect(Config().animation == Config.defaultShortcuts.animation)
        #expect(Config().gridFillOrder == Config.defaultShortcuts.gridFillOrder)
        #expect(Config().gap == Config.defaultShortcuts.gap)
        #expect(ActionSettings.default == ActionSettings(Config.defaultShortcuts))
    }

    @Test("the defaults are exactly the 33 bindings of the table, in order, each with a shortcut")
    func exactTable() {
        let config = Config.defaultShortcuts
        #expect(config.bindings.count == 33)
        #expect(Self.table.count == 33)
        #expect(rows(config) == Self.table, "the defaults are \(rows(config))")
    }

    @Test("the defaults are a valid config")
    func valid() throws {
        try Config.defaultShortcuts.validate()
    }

    @Test("Top Half and Bottom Half have no default shortcut")
    func noHalvesOnTop() {
        let actions = Config.defaultShortcuts.bindings.map(\.action)
        #expect(!actions.contains(.placeWindow(.preset(.topHalf))))
        #expect(!actions.contains(.placeWindow(.preset(.bottomHalf))))
    }

    @Test("every default shortcut may be registered as a global hotkey")
    func registrable() {
        for binding in Config.defaultShortcuts.bindings {
            #expect(binding.shortcut?.isRegistrable == true, "\(binding.action) cannot be registered")
        }
    }

    @Test("no two defaults share a shortcut, and every ID is distinct")
    func distinct() {
        let config = Config.defaultShortcuts
        let shortcuts = config.bindings.compactMap(\.shortcut)
        #expect(Set(shortcuts.map { "\($0.keyCode) \($0.modifiers.map(\.rawValue).sorted())" }).count == 33)
        #expect(Set(config.bindings.map(\.id)).count == 33)
    }

    @Test("all 33 defaults are accepted by the shortcut plan, with no issues")
    func planAcceptsAll() {
        let config = Config.defaultShortcuts
        let plan = ShortcutPlan.resolve(config.bindings)
        #expect(plan.issues.isEmpty, "the plan reports \(plan.issues)")
        #expect(plan.registrations.map(\.id) == config.bindings.map(\.id))
    }

    @Test("every call makes new IDs, so two calls share none")
    func freshIDs() {
        let first = Set(Config.defaultShortcuts.bindings.map(\.id))
        let second = Set(Config.defaultShortcuts.bindings.map(\.id))
        #expect(first.isDisjoint(with: second))
    }

    @Test("the defaults survive a save and a load unchanged")
    func roundTrip() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            let config = Config.defaultShortcuts
            try ConfigStore(url: url).save(config)
            let loaded = try ConfigStore(url: url).load()
            #expect(loaded.config == config)
            #expect(loaded.issues.isEmpty)
        }
    }
}
