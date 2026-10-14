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

    /// The table of the issue, in order: Left Half first, Move Divider Down last.
    private static let table: [Row] = [
        Row(action: .placeWindow(.preset(.leftHalf)), keyCode: 123, modifiers: controlOption),  // ⌃⌥←
        Row(action: .placeWindow(.preset(.rightHalf)), keyCode: 124, modifiers: controlOption),  // ⌃⌥→
        Row(action: .placeWindow(.preset(.topHalf)), keyCode: 126, modifiers: controlOption),  // ⌃⌥↑
        Row(action: .placeWindow(.preset(.bottomHalf)), keyCode: 125, modifiers: controlOption),  // ⌃⌥↓
        Row(action: .placeWindow(.preset(.topLeft)), keyCode: 32, modifiers: controlOption),  // ⌃⌥U
        Row(action: .placeWindow(.preset(.topRight)), keyCode: 34, modifiers: controlOption),  // ⌃⌥I
        Row(action: .placeWindow(.preset(.bottomLeft)), keyCode: 38, modifiers: controlOption),  // ⌃⌥J
        Row(action: .placeWindow(.preset(.bottomRight)), keyCode: 40, modifiers: controlOption),  // ⌃⌥K
        Row(action: .placeWindow(.preset(.leftThird)), keyCode: 2, modifiers: controlOption),  // ⌃⌥D
        Row(action: .placeWindow(.preset(.centerThird)), keyCode: 3, modifiers: controlOption),  // ⌃⌥F
        Row(action: .placeWindow(.preset(.rightThird)), keyCode: 5, modifiers: controlOption),  // ⌃⌥G
        Row(action: .placeWindow(.preset(.leftTwoThirds)), keyCode: 14, modifiers: controlOption),  // ⌃⌥E
        Row(action: .placeWindow(.preset(.rightTwoThirds)), keyCode: 17, modifiers: controlOption),  // ⌃⌥T
        Row(action: .placeWindow(.preset(.maximize)), keyCode: 36, modifiers: controlOption),  // ⌃⌥↩
        Row(action: .placeWindow(.preset(.center)), keyCode: 8, modifiers: controlOption),  // ⌃⌥C
        Row(action: .moveToDisplay(.next), keyCode: 124, modifiers: controlOptionCommand),  // ⌃⌥⌘→
        Row(action: .moveToDisplay(.previous), keyCode: 123, modifiers: controlOptionCommand),  // ⌃⌥⌘←
        Row(
            action: .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), keyCode: 19,
            modifiers: controlOptionShift),  // ⌃⌥⇧2
        Row(
            action: .arrangeGrid(GridSpec(count: 3, rows: 1, columns: 3)), keyCode: 20,
            modifiers: controlOptionShift),  // ⌃⌥⇧3
        Row(
            action: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)), keyCode: 21,
            modifiers: controlOptionShift),  // ⌃⌥⇧4
        Row(
            action: .arrangeGrid(GridSpec(count: 6, rows: 2, columns: 3)), keyCode: 22,
            modifiers: controlOptionShift),  // ⌃⌥⇧6
        Row(action: .moveDivider(.left), keyCode: 123, modifiers: controlOptionShift),  // ⌃⌥⇧←
        Row(action: .moveDivider(.right), keyCode: 124, modifiers: controlOptionShift),  // ⌃⌥⇧→
        Row(action: .moveDivider(.up), keyCode: 126, modifiers: controlOptionShift),  // ⌃⌥⇧↑
        Row(action: .moveDivider(.down), keyCode: 125, modifiers: controlOptionShift),  // ⌃⌥⇧↓
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

    @Test("the defaults carry the default window animation, grid fill order and destination preview")
    func settingsDefaults() {
        #expect(Config.defaultShortcuts.animation == .fast)
        #expect(Config.defaultShortcuts.gridFillOrder == .rows)
        #expect(Config.defaultShortcuts.destinationPreview == true)
    }

    @Test("the defaults are exactly the 25 bindings of the table, in order, each with a shortcut")
    func exactTable() {
        let config = Config.defaultShortcuts
        #expect(config.bindings.count == 25)
        #expect(Self.table.count == 25)
        #expect(rows(config) == Self.table, "the defaults are \(rows(config))")
    }

    @Test("the defaults are a valid config")
    func valid() throws {
        try Config.defaultShortcuts.validate()
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
        #expect(Set(shortcuts.map { "\($0.keyCode) \($0.modifiers.map(\.rawValue).sorted())" }).count == 25)
        #expect(Set(config.bindings.map(\.id)).count == 25)
    }

    @Test("all 25 defaults are accepted by the shortcut plan, with no issues")
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
