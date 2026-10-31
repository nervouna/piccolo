import Foundation
import PiccoloControl
import PiccoloCore
import Testing

/// Acceptance tests for undo and redo in the Settings window: the installed Debug Piccolo takes back and
/// applies again the changes made through Settings, and keeps the config file and the global hotkeys in
/// step with every step.
///
/// Every test runs on a temporary config applied with `config.load` (see ``withSettingsSession(_:inNewSubfolder:_:)``),
/// which also starts the history empty: a config replaced from outside clears it. The shortcut a
/// recording posts is control + option + ←, a default shortcut, while the hotkeys are suspended; no test
/// registers a shortcut that someone could press by accident, apart from the default shortcuts that the
/// restore puts in the config for the time of one test.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Settings undo")
    struct SettingsUndo {
        private let piccolo = PiccoloClient()

        private static let leftHalf = Action.placeWindow(.preset(.leftHalf))
        private static let topLeft = Action.placeWindow(.preset(.topLeft))
        private static let controlOptionLeft = Shortcut(keyCode: 123, modifiers: [.control, .option])

        // MARK: a. A setting

        @Test("undo 1. settings.setGap 16 then 20, settings.undo: the file has 16; settings.redo: 20")
        func undoAndRedoGap() async throws {
            try await withSettingsSession(Config.defaultShortcuts.bindings) { session in
                let start = try piccolo.settingsState()
                #expect(!start.canUndo, "a freshly loaded config can be undone")
                #expect(!start.canRedo)
                #expect(start.gap == 0)
                _ = try piccolo.settingsUndoExpectingRefusal()
                _ = try piccolo.settingsRedoExpectingRefusal()

                try piccolo.settingsSetGap(16)
                let changed = try piccolo.settingsSetGap(20)
                #expect(changed.canUndo)
                #expect(!changed.canRedo)
                #expect(try session.fileConfig().gap == 20)

                let undone = try piccolo.settingsUndo()
                #expect(undone.gap == 16, "the state has the gap \(undone.gap) after the undo")
                #expect(try session.fileConfig().gap == 16, "the file does not have 16 after the undo")
                #expect(undone.canUndo, "the change from 0 to 16 is still to be undone")
                #expect(undone.canRedo)

                let redone = try piccolo.settingsRedo()
                #expect(redone.gap == 20)
                #expect(try session.fileConfig().gap == 20, "the file does not have 20 after the redo")
                #expect(redone.canUndo)
                #expect(!redone.canRedo)
                _ = try piccolo.settingsRedoExpectingRefusal()

                // All the way back, to the config that was loaded.
                try piccolo.settingsUndo()
                let first = try piccolo.settingsUndo()
                #expect(first.gap == 0)
                #expect(try session.fileConfig().gap == 0)
                #expect(!first.canUndo)
                #expect(first.canRedo)
                let refusal = try piccolo.settingsUndoExpectingRefusal()
                #expect(!refusal.isEmpty)
                #expect(try piccolo.settingsState().error == nil, "a refused undo set the error")

                // A new change after an undo drops what could be redone.
                try piccolo.settingsSetGap(8)
                #expect(try piccolo.settingsState().canRedo == false)
                _ = try piccolo.settingsRedoExpectingRefusal()
            }
        }

        // MARK: b. A conflict

        @Test("undo 2. a conflict replaced with settings.record and settings.resolveConflict is one step: undo gives ⌃⌥← back to Left Half and the old shortcut to Top Left, in the file and registered")
        func undoReplacedConflict() async throws {
            try await withSettingsSession(Config.defaultShortcuts.bindings) { session in
                try piccolo.settingsSetSearch("")
                try session.openSettings()
                let before = try session.fileBindings()
                let left = try #require(before.first { $0.action == Self.leftHalf })
                #expect(left.shortcut == Self.controlOptionLeft)
                let topLeft = try #require(before.first { $0.action == Self.topLeft })
                let defaultTopLeft = try #require(
                    Config.defaultShortcuts.bindings.first { $0.action == Self.topLeft }?.shortcut)
                #expect(topLeft.shortcut == defaultTopLeft)
                let rowsBefore = try piccolo.keymapState().rows
                let registeredBefore = try piccolo.configStatus().registered

                let recorded = try await session.record("placeWindow.topLeft", Self.controlOptionLeft)
                #expect(recorded.conflict != nil, "recording a taken shortcut answered no conflict")
                try piccolo.keymapResolveConflict(replace: true)
                #expect(!(try session.fileBindings().contains { $0.id == left.id }), "the replace did not take the shortcut")
                #expect(try piccolo.settingsState().canUndo)

                let undone = try piccolo.settingsUndo()

                #expect(undone.error == nil, "the undo set the error \(undone.error ?? "")")
                #expect(try session.fileBindings() == before, "the file does not hold the bindings it held before the replace")
                let rows = try piccolo.keymapState().rows
                let leftRow = try #require(rows.first { $0.row == "placeWindow.leftHalf" })
                #expect(leftRow.shortcuts.map(\.shortcutText) == ["⌃⌥←"], "Left Half has \(leftRow.shortcuts)")
                #expect(leftRow.shortcuts.map(\.bindingID) == [left.id])
                let topLeftRow = try #require(rows.first { $0.row == "placeWindow.topLeft" })
                #expect(
                    topLeftRow.shortcuts.map(\.shortcutText)
                        == rowsBefore.first { $0.row == "placeWindow.topLeft" }?.shortcuts.map(\.shortcutText),
                    "Top Left has \(topLeftRow.shortcuts)")
                #expect(topLeftRow.shortcuts.map(\.bindingID) == [topLeft.id])
                #expect(rows == rowsBefore, "the keymap is not the one it was before the replace")
                #expect(try piccolo.keymapState().conflict == nil)

                let registered = try piccolo.configStatus().registered
                #expect(Set(registered.map(\.id)) == Set(registeredBefore.map(\.id)))
                let holders = registered.filter {
                    $0.keyCode == Self.controlOptionLeft.keyCode && $0.modifiers == Self.controlOptionLeft.modifiers
                }
                #expect(holders.map(\.id) == [left.id], "⌃⌥← is registered for \(holders.map(\.id))")
                #expect(
                    registered.contains {
                        $0.id == topLeft.id && $0.keyCode == defaultTopLeft.keyCode && $0.modifiers == defaultTopLeft.modifiers
                    }, "Top Left's own shortcut is not registered again")

                let redone = try piccolo.settingsRedo()
                #expect(redone.error == nil)
                #expect(!(try session.fileBindings().contains { $0.id == left.id }), "the redo did not replace again")
                let holdersAfterRedo = try piccolo.configStatus().registered.filter {
                    $0.keyCode == Self.controlOptionLeft.keyCode && $0.modifiers == Self.controlOptionLeft.modifiers
                }
                #expect(holdersAfterRedo.map(\.id) == [topLeft.id], "⌃⌥← is registered for \(holdersAfterRedo.map(\.id))")
            }
        }

        // MARK: c. A restore

        @Test("undo 3. restoring the default shortcuts is one step: undo gives the bindings back, redo restores the defaults")
        func undoRestore() async throws {
            let a = KeyBinding(action: Self.leftHalf, shortcut: TestShortcut.f13)
            let b = KeyBinding(action: Self.topLeft, shortcut: TestShortcut.f14)
            try await withSettingsSession([a, b]) { session in
                try piccolo.settingsSetGap(12)
                let (restored, _) = try piccolo.settingsRestoreDefaults()
                #expect(restored.bindings.count == 32)
                #expect(restored.gap == 12, "the restore changed the gap")
                let restoredBindings = try session.fileBindings()
                #expect(restoredBindings.count == 32)

                let undone = try piccolo.settingsUndo()

                #expect(undone.error == nil)
                #expect(undone.gap == 12)
                #expect(try session.fileBindings() == [a, b], "the file does not hold the two bindings again")
                #expect(Set(try session.registeredIDs()) == [a.id, b.id])
                #expect(undone.canUndo, "the gap is still a step")

                let redone = try piccolo.settingsRedo()
                #expect(redone.bindings.count == 32)
                #expect(try session.fileBindings() == restoredBindings)
                #expect(try session.fileConfig().gap == 12)
            }
        }

        // MARK: d. Recording

        @Test("undo 4. settings.undo ends a recording and brings the hotkeys back")
        func undoEndsRecording() async throws {
            try await withSettingsSession(Config.defaultShortcuts.bindings) { session in
                try piccolo.settingsSetGap(16)
                let registeredBefore = try piccolo.configStatus().registered
                let recording = try piccolo.keymapBeginRecording("placeWindow.leftHalf")
                #expect(recording.recordingRow == "placeWindow.leftHalf")
                #expect(try piccolo.configStatus().registered.isEmpty)

                let undone = try piccolo.settingsUndo()

                #expect(undone.gap == 0)
                #expect(try piccolo.keymapState().recordingRow == nil, "the undo did not end the recording")
                #expect(try piccolo.configStatus().registered == registeredBefore, "the hotkeys did not come back")
            }
        }

        // MARK: e. Closing the window

        @Test("undo 5. closing the window drops a pending conflict, so that it does not come back with the window")
        func closingDropsConflict() async throws {
            try await withSettingsSession(Config.defaultShortcuts.bindings) { session in
                try piccolo.settingsSetSearch("")
                try session.openSettings()
                let beforeBytes = try session.fileBytes()

                let state = try await session.record("placeWindow.topLeft", Self.controlOptionLeft)
                #expect(state.conflict != nil, "recording a taken shortcut answered no conflict")

                try piccolo.settingsClose()
                #expect(try piccolo.keymapState().conflict == nil, "the conflict outlived the window")

                try session.openSettings()
                #expect(try piccolo.keymapState().conflict == nil, "the conflict came back with the window")
                #expect(try session.fileBytes() == beforeBytes, "closing the window changed the file")
                #expect(!(try piccolo.settingsState().canUndo), "a dropped conflict is a step")
            }
        }
    }
}

/// `settings.undo` and `settings.redo`.
extension PiccoloClient {
    /// `settings.undo`, which answers the state.
    @discardableResult
    func settingsUndo() throws -> SettingsState {
        try decodeState(try send("settings.undo"), of: "settings.undo")
    }

    /// `settings.redo`, which answers the state.
    @discardableResult
    func settingsRedo() throws -> SettingsState {
        try decodeState(try send("settings.redo"), of: "settings.redo")
    }

    /// `settings.undo` when there is nothing to undo, which must be refused. Returns the message.
    func settingsUndoExpectingRefusal() throws -> String {
        try historyExpectingRefusal("settings.undo")
    }

    /// `settings.redo` when there is nothing to redo, which must be refused. Returns the message.
    func settingsRedoExpectingRefusal() throws -> String {
        try historyExpectingRefusal("settings.redo")
    }

    private func historyExpectingRefusal(_ command: String) throws -> String {
        let response = try sendRaw(command)
        guard !response.ok else {
            throw AcceptanceFailure(
                "\(command) was accepted with nothing to take back or apply; it answered \(String(describing: response.result))"
            )
        }
        guard let message = response.error, !message.isEmpty else {
            throw AcceptanceFailure("\(command) was refused without saying why")
        }
        return message
    }
}
