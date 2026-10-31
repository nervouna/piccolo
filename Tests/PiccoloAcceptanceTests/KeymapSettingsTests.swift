import Foundation
import PiccoloControl
import PiccoloCore
import Testing

@testable import PiccoloUI

/// Acceptance tests for the keymap of the Settings window: the installed Debug Piccolo lists a row for
/// every built-in action, records a shortcut for a row from real keyboard events, settles a conflict, adds
/// grids and custom areas, and keeps the config file and the global hotkeys in step with all of it.
///
/// Every test runs on a temporary config applied with `config.load` (see ``withSettingsSession(_:inNewSubfolder:_:)``),
/// holding the 33 default shortcuts, so that Settings never writes to the default location. Recording
/// suspends every hotkey, so the keys the tests post (including Left Half's default shortcut) never
/// fire an action; only the shortcut recorded for a new binding is a hotkey afterwards, and it is control +
/// option + shift + command with F14.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Keymap settings")
    struct KeymapSettings {
        private let piccolo = PiccoloClient()

        private static let leftHalf = Action.placeWindow(.preset(.leftHalf))
        private static let topLeft = Action.placeWindow(.preset(.topLeft))
        private static let topHalf = Action.placeWindow(.preset(.topHalf))

        // MARK: 1. A row without a binding

        @Test("keymap 1. recording ⌃⌥⇧⌘F14 on placeWindow.topHalf, which has no binding, adds one to the file and registers the hotkey")
        func recordUnboundRow() async throws {
            try await withSettingsSession(Config.defaultShortcuts.bindings) { session in
                try piccolo.settingsSetSearch("")
                try session.openSettings()
                let before = try session.fileBindings()
                #expect(
                    !before.contains { $0.action == Self.topHalf },
                    "the default shortcuts already bind \(Self.topHalf)")
                let registeredBefore = try piccolo.configStatus().registered

                let state = try await session.record("placeWindow.topHalf", TestShortcut.f14)

                #expect(state.error == nil, "recording set the error \(state.error ?? "")")
                #expect(state.recordingRow == nil, "the recording did not end")
                #expect(state.conflict == nil)
                let after = try session.fileBindings()
                #expect(after.count == before.count + 1, "the file holds \(after.count) bindings, not \(before.count + 1)")
                #expect(Array(after.dropLast()) == before, "the other bindings changed")
                let added = try #require(after.last)
                #expect(added.action == Self.topHalf)
                #expect(added.shortcut == TestShortcut.f14)

                let row = try #require(state.rows.first { $0.row == "placeWindow.topHalf" })
                #expect(row.section == "halves")
                #expect(row.shortcuts.map(\.bindingID) == [added.id])
                #expect(row.shortcuts.map(\.shortcutText) == ["⌃⌥⇧⌘F14"])
                #expect(row.shortcuts.map(\.active) == [true])
                #expect(!row.recording)

                let registered = try piccolo.configStatus().registered
                #expect(
                    registered.contains(
                        PiccoloClient.RegisteredShortcut(
                            id: added.id, keyCode: TestShortcut.f14.keyCode, modifiers: TestShortcut.f14.modifiers)),
                    "config.status does not list the new hotkey: \(registered)")
                #expect(registered.count == registeredBefore.count + 1)
            }
        }

        // MARK: 2. A shortcut another row has

        @Test("keymap 2. recording Left Half's shortcut on placeWindow.topLeft answers a conflict naming Left Half and changes nothing; replacing moves the shortcut in one step")
        func conflictAndReplace() async throws {
            let leftShortcut = try Config.defaultShortcut(of: Self.leftHalf)
            try await withSettingsSession(Config.defaultShortcuts.bindings) { session in
                try piccolo.settingsSetSearch("")
                try session.openSettings()
                let before = try session.fileBindings()
                let beforeBytes = try session.fileBytes()
                let left = try #require(before.first { $0.action == Self.leftHalf })
                #expect(left.shortcut == leftShortcut)
                // The text of the shortcut on this keyboard layout, as the keymap shows it.
                let leftText = try #require(
                    try piccolo.keymapState().rows.first { $0.row == "placeWindow.leftHalf" }?.shortcuts.first?.shortcutText,
                    "the Left Half row shows no shortcut")
                let topLeft = try #require(before.first { $0.action == Self.topLeft })
                let registeredBefore = try piccolo.configStatus().registered

                let state = try await session.record("placeWindow.topLeft", leftShortcut)

                let conflict = try #require(state.conflict, "recording a taken shortcut answered no conflict")
                let texts = try InterfaceTexts.current(piccolo)
                #expect(conflict.row == "placeWindow.topLeft")
                #expect(conflict.shortcutText == leftText)
                #expect(conflict.ownerBindingID == left.id)
                #expect(conflict.ownerName == texts.summary(of: Self.leftHalf), "the conflict names \(conflict.ownerName)")
                #expect(state.recordingRow == nil, "the recording did not end")
                #expect(state.error == nil)
                #expect(try session.fileBytes() == beforeBytes, "the conflict changed the file")
                #expect(try session.fileBindings() == before)

                let resolved = try piccolo.keymapResolveConflict(replace: true)

                #expect(resolved.conflict == nil, "the conflict is still pending")
                #expect(resolved.error == nil)
                let leftRow = try #require(resolved.rows.first { $0.row == "placeWindow.leftHalf" })
                #expect(leftRow.shortcuts.isEmpty, "Left Half still has \(leftRow.shortcuts)")
                let topLeftRow = try #require(resolved.rows.first { $0.row == "placeWindow.topLeft" })
                #expect(topLeftRow.shortcuts.map(\.shortcutText) == [leftText])

                let after = try session.fileBindings()
                #expect(!after.contains { $0.action == Self.leftHalf }, "the file still has a Left Half binding")
                #expect(after.count == before.count - 1)
                let changed = try #require(after.first { $0.id == topLeft.id })
                #expect(changed.shortcut == leftShortcut)
                #expect(after.filter { $0.shortcut == leftShortcut }.map(\.id) == [topLeft.id])

                let registered = try piccolo.configStatus().registered
                let holders = registered.filter {
                    $0.keyCode == leftShortcut.keyCode && $0.modifiers == leftShortcut.modifiers
                }
                #expect(holders.map(\.id) == [topLeft.id], "\(leftText) is registered for \(holders.map(\.id))")
                #expect(registered.count == registeredBefore.count - 1)
            }
        }

        // MARK: 3. Adding a layout

        @Test("keymap 3. adding the grid 3 in 2 × 2, which exists, is refused and leaves the file; adding 4 in 2 × 2 adds it and records it")
        func addLayout() async throws {
            try await withSettingsSession(Config.defaultShortcuts.bindings) { session in
                try piccolo.settingsSetSearch("")
                let beforeBytes = try session.fileBytes()
                let registeredBefore = try piccolo.configStatus().registered
                let existing = Action.arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2))
                let language = try #require(AppLanguage(rawValue: try piccolo.settingsState().effectiveLanguage))
                let bundle = try #require(language.textBundle)

                let message = try piccolo.keymapAddLayoutExpectingRefusal(existing)

                #expect(message == SettingsMessages.duplicateGrid(bundle: bundle), "the message is \"\(message)\"")
                #expect(try session.fileBytes() == beforeBytes, "the refused grid changed the file")
                let refused = try piccolo.keymapState()
                #expect(refused.error == message)
                #expect(refused.errorTarget == .string("window"))
                #expect(refused.recordingRow == nil)

                let grid = Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))
                let state = try piccolo.keymapAddLayout(grid)

                let recording = try #require(state.recordingRow, "adding a grid did not start a recording")
                let id = try #require(UUID(uuidString: recording), "recordingRow is \(recording), not a binding's UUID")
                let added = try #require(try session.fileBindings().last)
                #expect(added == KeyBinding(id: id, action: grid, shortcut: nil))
                let row = try #require(state.rows.first { $0.row == recording })
                #expect(row.section == "grids")
                #expect(row.editable)
                #expect(row.recording)
                #expect(row.shortcuts.isEmpty)
                // The hotkeys are suspended while the row records.
                #expect(try piccolo.configStatus().registered.isEmpty)

                try piccolo.settingsCancelRecording()
                #expect(try piccolo.keymapState().recordingRow == nil)
                #expect(try piccolo.configStatus().registered == registeredBefore)
            }
        }

        // MARK: 4. The rows and the other commands

        @Test("keymap 4. the state lists the rows in order, a row can be begun, cleared and edited, and errors say where they are")
        func rowsAndCommands() async throws {
            let extra = KeyBinding(action: Self.leftHalf, shortcut: TestShortcut.f13)
            let defaults = Config.defaultShortcuts.bindings
            try await withSettingsSession(defaults + [extra]) { session in
                try piccolo.settingsSetSearch("")
                let state = try piccolo.keymapState()

                // 30 built-in rows, the four default grids and the default custom area, in the order of the keymap.
                let sections = state.rows.map(\.section).reduce(into: [String]()) { names, name in
                    if names.last != name { names.append(name) }
                }
                #expect(
                    sections
                        == [
                            "halves", "quarters", "thirds", "other", "displays", "grids", "dividers", "swaps",
                            "customAreas",
                        ],
                    "the sections are \(sections)")
                #expect(state.rows.count == 35, "the state lists \(state.rows.count) rows")
                #expect(state.rows.filter { !$0.editable }.map(\.row) == BuiltInActions.all.map { KeymapRowID.builtIn($0).name })
                let grids = state.rows.filter { $0.section == "grids" }
                #expect(grids.count == 4)
                #expect(grids.allSatisfy { $0.editable && UUID(uuidString: $0.row) != nil })
                let areas = state.rows.filter { $0.section == "customAreas" }
                #expect(areas.count == 1)
                #expect(areas.allSatisfy { $0.editable && UUID(uuidString: $0.row) != nil })

                // A hand-edited file may bind one action twice: both shortcuts are in the row, in file order.
                let leftRow = try #require(state.rows.first { $0.row == "placeWindow.leftHalf" })
                let defaultLeft = try #require(defaults.first { $0.action == Self.leftHalf })
                #expect(leftRow.shortcuts.map(\.bindingID) == [defaultLeft.id, extra.id])
                #expect(leftRow.shortcuts.last?.shortcutText == "⌃⌥⇧⌘F13")
                // Top Half and Bottom Half have no default shortcut; Next Display has one.
                let topHalfRow = try #require(state.rows.first { $0.row == "placeWindow.topHalf" })
                #expect(topHalfRow.shortcuts.isEmpty)
                let nextRow = try #require(state.rows.first { $0.row == "moveToDisplay.next" })
                #expect(nextRow.shortcuts.count == 1)

                // Beginning a recording marks the row and suspends the hotkeys; cancelling brings them back.
                let registeredBefore = try piccolo.configStatus().registered
                let recording = try piccolo.keymapBeginRecording("placeWindow.leftHalf")
                #expect(recording.recordingRow == "placeWindow.leftHalf")
                #expect(recording.rows.filter(\.recording).map(\.row) == ["placeWindow.leftHalf"])
                #expect(try piccolo.configStatus().registered.isEmpty)
                try piccolo.settingsCancelRecording()
                #expect(try piccolo.keymapState().recordingRow == nil)
                #expect(try piccolo.configStatus().registered == registeredBefore)

                // Clearing a built-in row removes its first binding and releases the hotkey.
                let divider = try #require(try session.fileBindings().first { $0.action == .moveDivider(.left) })
                let cleared = try piccolo.keymapClearShortcut("moveDivider.left")
                #expect(cleared.rows.first { $0.row == "moveDivider.left" }?.shortcuts.isEmpty == true)
                #expect(!(try session.fileBindings().contains { $0.id == divider.id }))
                #expect(!(try session.registeredIDs().contains(divider.id)))

                // A grid can become another grid, but not one that exists.
                let threeInTwoByTwo = Action.arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2))
                let sixInTwoByThree = Action.arrangeGrid(GridSpec(count: 6, rows: 2, columns: 3))
                let grid = try #require(try session.fileBindings().first { $0.action == threeInTwoByTwo })
                let refusal = try piccolo.keymapUpdateLayoutExpectingRefusal(grid.id, sixInTwoByThree)
                #expect(try piccolo.keymapState().error == refusal)
                #expect(try piccolo.keymapState().errorTarget == .string("window"))
                let fiveInThreeByTwo = Action.arrangeGrid(GridSpec(count: 5, rows: 3, columns: 2))
                let updated = try piccolo.keymapUpdateLayout(grid.id, fiveInThreeByTwo)
                #expect(updated.error == nil)
                #expect(updated.errorTarget == nil)
                #expect(try session.fileBindings().first { $0.id == grid.id }?.action == fiveInThreeByTwo)
                #expect(updated.rows.first { $0.row == grid.id.uuidString }?.shortcuts.count == 1, "the grid lost its shortcut")

                // The sheet's request.
                #expect(try piccolo.keymapEditLayout(row: grid.id.uuidString).layoutEditor == .object(["edit": .string(grid.id.uuidString)]))
                #expect(try piccolo.keymapEditLayout(new: "customAreas").layoutEditor == .object(["new": .string("customAreas")]))
                #expect(try piccolo.keymapDismissLayoutEditor().layoutEditor == nil)

                // A field's error says which field.
                _ = try piccolo.settingsSetGapExpectingRejection(100)
                #expect(try piccolo.keymapState().errorTarget == .object(["field": .string("gap")]))
                _ = try piccolo.settingsSetGap(0)
                #expect(try piccolo.keymapState().errorTarget == nil)

                // No conflict is pending.
                _ = try piccolo.keymapResolveConflictExpectingRefusal(replace: true)
            }
        }
    }
}
