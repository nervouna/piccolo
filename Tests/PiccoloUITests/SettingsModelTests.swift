import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

@MainActor
@Suite("Settings model")
struct SettingsModelTests {
    private func make(
        _ config: Config = UIFixture.twoBindings(), issues: [String] = []
    ) -> (model: SettingsModel, backend: InMemorySettingsBackend) {
        let backend = InMemorySettingsBackend(config: config, issues: issues)
        // A layout in which key code 0 is A and 11 is B; everything else produces nothing.
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage()) { code in
            ["0": "a", "11": "b"][String(code)]
        }
        return (model, backend)
    }

    // MARK: Initial state

    @Test("the model starts with the backend's bindings, resize step and issues")
    func initialState() {
        let config = Config(resizeStep: 0.1, bindings: UIFixture.twoBindings().bindings)
        let (model, _) = make(config, issues: ["bindings[3] skipped: duplicate id"])

        #expect(model.bindings == config.bindings)
        #expect(model.resizeStep == 0.1)
        #expect(model.issues == ["bindings[3] skipped: duplicate id"])
        #expect(model.recordingRow == nil)
        #expect(!model.isRecording)
        #expect(model.error == nil)
    }

    @Test("the window starts on the Shortcuts tab, and the tab is the model's to set")
    func tabStartsOnShortcuts() {
        let (model, backend) = make()
        #expect(model.tab == .shortcuts)
        #expect(SettingsTab.allCases == [.shortcuts, .general])
        #expect(SettingsTab.allCases.map(\.rawValue) == ["shortcuts", "general"])

        model.tab = .general

        #expect(model.tab == .general)
        // Showing a tab edits nothing.
        #expect(backend.saved.isEmpty)
    }

    @Test("issues are refreshed from the backend's answer to every save")
    func issuesAreRefreshed() {
        let (model, backend) = make(issues: ["old problem"])
        backend.issuesAfterSave = ["bindings[2] shortcut was refused"]
        model.setGap(8)
        #expect(model.issues == ["bindings[2] shortcut was refused"])

        backend.issuesAfterSave = []
        model.setResizeStep(0.1)
        #expect(model.issues.isEmpty)
    }

    // MARK: Removing

    @Test("remove deletes the binding and saves")
    func removeBinding() {
        let (model, backend) = make()

        #expect(model.removeBinding(UIFixture.idA))

        #expect(model.bindings.map(\.id) == [UIFixture.idB])
        #expect(backend.saved.last?.bindings.map(\.id) == [UIFixture.idB])
    }

    @Test("removing the last binding leaves an empty config")
    func removeAll() {
        let (model, _) = make()
        model.removeBinding(UIFixture.idB)
        model.removeBinding(UIFixture.idA)
        #expect(model.bindings.isEmpty)
    }

    @Test("removing an unknown binding is rejected and saves nothing")
    func removeUnknown() {
        let (model, backend) = make()
        #expect(!model.removeBinding(UUID()))
        #expect(model.error != nil)
        #expect(backend.saved.isEmpty)
    }

    // MARK: Actions

    @Test("updateAction replaces the action, keeps the shortcut and saves")
    func updateAction() {
        let (model, backend) = make()

        let accepted = model.updateAction(
            UIFixture.idA, to: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))

        #expect(accepted)
        #expect(model.binding(UIFixture.idA)?.action == .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))
        #expect(model.binding(UIFixture.idA)?.shortcut == UIFixture.f13)
        #expect(backend.saved.last == model.config)
    }

    @Test("a binding can be changed to Swap Window and to another direction, keeping its shortcut")
    func updateActionToSwap() {
        let (model, backend) = make()

        #expect(model.updateAction(UIFixture.idA, to: .swapWindow(.left)))
        #expect(model.binding(UIFixture.idA)?.action == .swapWindow(.left))
        #expect(model.updateAction(UIFixture.idA, to: .swapWindow(.down)))

        #expect(model.binding(UIFixture.idA)?.action == .swapWindow(.down))
        #expect(model.binding(UIFixture.idA)?.shortcut == UIFixture.f13)
        #expect(backend.saved.last == model.config)
    }

    @Test("a custom frame inside the screen is accepted")
    func customFrameAccepted() {
        let (model, _) = make()
        let frame = FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)
        #expect(model.updateAction(UIFixture.idA, to: .placeWindow(.custom(frame))))
        #expect(model.binding(UIFixture.idA)?.action == .placeWindow(.custom(frame)))
    }

    @Test(
        "an invalid action is rejected: nothing is saved, nothing changes, the error says what is wrong",
        arguments: [
            (
                "a frame that leaves the screen on the right",
                Action.placeWindow(.custom(FractionalRect(x: 0.6, y: 0, width: 0.5, height: 1))),
                "Left plus width"
            ),
            (
                "a frame that leaves the screen at the bottom",
                Action.placeWindow(.custom(FractionalRect(x: 0, y: 0.6, width: 1, height: 0.5))),
                "Top plus height"
            ),
            (
                "a negative left edge",
                Action.placeWindow(.custom(FractionalRect(x: -0.1, y: 0, width: 0.5, height: 1))),
                "Left must be"
            ),
            (
                "a frame without width",
                Action.placeWindow(.custom(FractionalRect(x: 0, y: 0, width: 0, height: 1))),
                "Width must be"
            ),
            (
                "a frame without height",
                Action.placeWindow(.custom(FractionalRect(x: 0, y: 0, width: 1, height: 0))),
                "Height must be"
            ),
            (
                "a frame that is not a number",
                Action.placeWindow(.custom(FractionalRect(x: .nan, y: 0, width: 1, height: 1))),
                "must be a number"
            ),
            (
                "more windows than the grid has cells",
                Action.arrangeGrid(GridSpec(count: 5, rows: 2, columns: 2)),
                "cannot be more than rows × columns"
            ),
            (
                "a grid without rows",
                Action.arrangeGrid(GridSpec(count: 1, rows: 0, columns: 2)),
                "Rows must be at least 1"
            ),
            (
                "a grid without columns",
                Action.arrangeGrid(GridSpec(count: 1, rows: 2, columns: 0)),
                "Columns must be at least 1"
            ),
            (
                "a grid with no windows",
                Action.arrangeGrid(GridSpec(count: 0, rows: 2, columns: 2)),
                "at least 1"
            ),
        ] as [(String, Action, String)]
    )
    func updateActionRejections(_ name: String, _ action: Action, _ message: String) {
        let (model, backend) = make()
        let before = model.config

        let accepted = model.updateAction(UIFixture.idA, to: action)

        #expect(!accepted, "\(name) was accepted")
        #expect(model.config == before, "\(name) changed the model")
        #expect(backend.saved.isEmpty, "\(name) was saved")
        #expect(model.error?.contains(message) == true, "\(name): the error is \(model.error ?? "nil")")
    }

    @Test("updateAction for an unknown binding is rejected")
    func updateUnknown() {
        let (model, backend) = make()
        #expect(!model.updateAction(UUID(), to: .moveToDisplay(.next)))
        #expect(model.error != nil)
        #expect(backend.saved.isEmpty)
    }

    @Test("the next accepted change clears the error")
    func errorIsCleared() {
        let (model, _) = make()
        model.updateAction(UIFixture.idA, to: .arrangeGrid(GridSpec(count: 9, rows: 1, columns: 1)))
        #expect(model.error != nil)

        #expect(model.updateAction(UIFixture.idA, to: .moveDivider(.left)))

        #expect(model.error == nil)
    }

    @Test("a rejected change keeps the error of an earlier rejection until it is replaced")
    func errorIsReplaced() {
        let (model, _) = make()
        model.updateAction(UIFixture.idA, to: .arrangeGrid(GridSpec(count: 9, rows: 1, columns: 1)))
        let first = model.error
        model.updateAction(UIFixture.idA, to: .placeWindow(.custom(FractionalRect(x: 0, y: 0, width: 0, height: 1))))
        #expect(model.error != nil)
        #expect(model.error != first)
    }

    @Test("clearError forgets the error")
    func clearError() {
        let (model, _) = make()
        model.removeBinding(UUID())
        model.clearError()
        #expect(model.error == nil)
    }

    @Test("an action that does not change is accepted without a save")
    func unchangedAction() {
        let (model, backend) = make()
        #expect(model.updateAction(UIFixture.idA, to: .placeWindow(.preset(.leftHalf))))
        #expect(backend.saved.isEmpty)
    }

    // MARK: Shortcuts

    @Test("shortcut text on the model uses the injected keyboard layout")
    func shortcutText() {
        let (model, _) = make()
        #expect(model.shortcutText(for: Shortcut(keyCode: 0, modifiers: [.command, .shift])) == "⇧⌘A")
        #expect(model.shortcutText(for: UIFixture.f14) == "⌃⌥⇧⌘F14")
    }

    // MARK: Resize step

    @Test("a valid resize step is saved", arguments: [0.1, 0.01, 0.5])
    func resizeStepAccepted(_ value: Double) {
        let (model, backend) = make()
        #expect(model.setResizeStep(value))
        #expect(model.resizeStep == value)
        #expect(backend.saved.last?.resizeStep == value)
    }

    @Test("a resize step outside (0, 0.5] is rejected, nothing is saved", arguments: [0.0, -0.1, 0.9, 0.51, 1, Double.nan, .infinity])
    func resizeStepRejected(_ value: Double) {
        let (model, backend) = make()
        let before = model.resizeStep

        #expect(!model.setResizeStep(value))

        #expect(model.resizeStep == before)
        #expect(backend.saved.isEmpty)
        #expect(model.error != nil)
    }

    @Test("the resize step error says the range")
    func resizeStepMessage() {
        let (model, _) = make()
        model.setResizeStep(0.9)
        #expect(model.error?.contains("0%") == true && model.error?.contains("50%") == true)
    }

    // MARK: Saving fails

    @Test("when the backend cannot save, no change shows and the error says why")
    func saveFailure() {
        let (model, backend) = make()
        backend.failure = "the config file was written by a newer version"
        let before = model.config

        #expect(!model.updateAction(UIFixture.idA, to: .moveToDisplay(.previous)))
        #expect(!model.setResizeStep(0.1))
        #expect(!model.removeBinding(UIFixture.idA))

        #expect(model.config == before)
        #expect(model.error?.contains("newer version") == true)
    }

    // MARK: Recording

    @Test("a key press when nothing is recording is not taken")
    func recordWithoutRecording() {
        let (model, backend) = make()
        #expect(!model.record(UIFixture.f14))
        #expect(model.binding(UIFixture.idA)?.shortcut == UIFixture.f13)
        #expect(backend.saved.isEmpty)
        #expect(backend.suspendRequests.isEmpty)
    }

    @Test("cancelRecording is safe when nothing is recording, and always asks for the hotkeys back")
    func cancelWithoutRecording() {
        let (model, backend) = make()
        model.cancelRecording()
        model.cancelRecording()
        #expect(!model.isRecording)
        #expect(backend.suspendRequests == [false, false])
        #expect(!backend.isSuspended)
    }

    @Test("a key press becomes the shortcut; it is saved while the hotkeys are suspended, then they come back")
    func recordKey() {
        let (model, backend) = make()
        model.beginRecording(.builtIn(.moveToDisplay(.next)))

        #expect(model.record(UIFixture.f14))

        #expect(model.binding(UIFixture.idB)?.shortcut == UIFixture.f14)
        #expect(!model.isRecording)
        #expect(backend.suspendedAtSave == [true])
        #expect(!backend.isSuspended)
        #expect(backend.suspendRequests == [true, false])
        #expect(model.error == nil)
    }

    @Test("issues the system reports only once the hotkeys are back are shown after the recording")
    func issuesAfterRecording() {
        let (model, backend) = make()
        backend.issuesAfterResume = ["bindings[1] shortcut was refused: taken by the system"]
        model.beginRecording(.builtIn(.moveToDisplay(.next)))

        model.record(UIFixture.f14)

        #expect(model.issues == ["bindings[1] shortcut was refused: taken by the system"])
    }

    @Test("every key press recording takes is counted, and one nobody takes is not")
    func pressesAreCounted() {
        let (model, _) = make()
        #expect(model.pressesTaken == 0)

        model.record(UIFixture.f14)
        #expect(model.pressesTaken == 0)

        let next = KeymapRowID.builtIn(.moveToDisplay(.next))
        model.beginRecording(next)
        model.record(UIFixture.f14)
        model.beginRecording(next)
        model.record(Shortcut(keyCode: 53, modifiers: []))
        #expect(model.pressesTaken == 2)
    }

    @Test("Escape and Delete with a modifier are shortcuts like any other")
    func escapeAndDeleteWithModifier() {
        let (model, _) = make()
        let next = KeymapRowID.builtIn(.moveToDisplay(.next))
        model.beginRecording(next)
        model.record(Shortcut(keyCode: 53, modifiers: [.command]))
        #expect(model.binding(UIFixture.idB)?.shortcut == Shortcut(keyCode: 53, modifiers: [.command]))

        model.beginRecording(next)
        model.record(Shortcut(keyCode: 51, modifiers: [.control]))
        #expect(model.binding(UIFixture.idB)?.shortcut == Shortcut(keyCode: 51, modifiers: [.control]))
    }

    @Test("a function key needs no modifier, control with a letter is fine")
    func registrableShortcuts() {
        let (model, _) = make()
        let next = KeymapRowID.builtIn(.moveToDisplay(.next))
        model.beginRecording(next)
        model.record(Shortcut(keyCode: FunctionKey.f5, modifiers: []))
        #expect(model.binding(UIFixture.idB)?.shortcut == Shortcut(keyCode: FunctionKey.f5, modifiers: []))
        #expect(model.error == nil)

        model.beginRecording(next)
        model.record(UIFixture.controlA)
        #expect(model.binding(UIFixture.idB)?.shortcut == UIFixture.controlA)
        #expect(model.error == nil)
    }

    @Test(
        "a shortcut that cannot be registered is rejected with the reason, and nothing is saved",
        arguments: [
            (Shortcut(keyCode: 0, modifiers: []), "A cannot be a global shortcut"),
            (Shortcut(keyCode: 0, modifiers: [.shift]), "⇧A cannot be a global shortcut"),
            (Shortcut(keyCode: 11, modifiers: []), "B cannot be a global shortcut"),
        ] as [(Shortcut, String)]
    )
    func notRegistrable(_ shortcut: Shortcut, _ message: String) {
        let (model, backend) = make()
        model.beginRecording(.builtIn(.moveToDisplay(.next)))

        model.record(shortcut)

        #expect(model.binding(UIFixture.idB)?.shortcut == nil)
        #expect(backend.saved.isEmpty)
        #expect(model.error?.contains(message) == true, "the error is \(model.error ?? "nil")")
    }

    @Test("a shortcut another binding uses is held as a conflict, and the sentence names that binding's action")
    func duplicateShortcut() throws {
        let (model, backend) = make()
        model.beginRecording(.builtIn(.moveToDisplay(.next)))

        model.record(UIFixture.f13)

        #expect(model.binding(UIFixture.idB)?.shortcut == nil)
        #expect(backend.saved.isEmpty)
        let conflict = try #require(model.pendingConflict)
        let owner = try #require(model.binding(conflict.ownerBindingID))
        let sentence = SettingsMessages.alreadyUsed(
            model.shortcutText(for: conflict.shortcut), by: model.summary(of: owner))
        #expect(sentence.contains("Left Half"), "the sentence is \(sentence)")
        #expect(sentence.contains("⌃⌥⇧⌘F13"), "the sentence is \(sentence)")
    }

    @Test("removing the binding of a row that is recording ends the recording and restores the hotkeys")
    func removeWhileRecording() {
        let grid = KeyBinding(id: UIFixture.idC, action: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))
        let (model, backend) = make(Config(bindings: [grid]))
        model.beginRecording(.layout(UIFixture.idC))

        #expect(model.removeBinding(UIFixture.idC))

        #expect(!model.isRecording)
        #expect(!backend.isSuspended)
        #expect(backend.suspendedAtSave == [true])
    }

    @Test("removing another binding while recording keeps recording")
    func removeOtherWhileRecording() {
        let (model, backend) = make()
        let next = KeymapRowID.builtIn(.moveToDisplay(.next))
        model.beginRecording(next)

        #expect(model.removeBinding(UIFixture.idA))

        #expect(model.recordingRow == next)
        #expect(backend.isSuspended)
    }

    @Test("a removal that cannot be saved leaves the recording as it was")
    func failedRemoveWhileRecording() {
        let grid = KeyBinding(id: UIFixture.idC, action: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))
        let (model, backend) = make(Config(bindings: [grid]))
        model.beginRecording(.layout(UIFixture.idC))
        backend.failure = "no space"

        #expect(!model.removeBinding(UIFixture.idC))

        #expect(model.recordingRow == .layout(UIFixture.idC))
        #expect(backend.isSuspended)
    }

    // MARK: Changes from outside

    @Test("a config replaced from outside is picked up, and the error is forgotten")
    func externalChange() {
        let (model, backend) = make()
        model.removeBinding(UUID())
        #expect(model.error != nil)

        let replaced = Config(
            resizeStep: 0.2,
            bindings: [KeyBinding(id: UIFixture.idC, action: .moveDivider(.up), shortcut: UIFixture.f15)])
        backend.replaceFromOutside(replaced, issues: ["bindings[1] skipped: broken"])

        #expect(model.config == replaced)
        #expect(model.issues == ["bindings[1] skipped: broken"])
        #expect(model.error == nil)
    }

    // MARK: Restoring the default shortcuts

    @Test("restoring keeps a copy of the file, replaces the bindings with the 33 defaults and keeps the resize step")
    func restoreDefaults() {
        let (model, backend) = make(Config(resizeStep: 0.2, bindings: UIFixture.twoBindings().bindings))

        #expect(model.restoreDefaultShortcuts())

        #expect(backend.copies == [InMemorySettingsBackend.copyName])
        #expect(model.backupName == InMemorySettingsBackend.copyName)
        #expect(model.bindings.count == 33)
        #expect(model.bindings.map(\.action) == Config.defaultShortcuts.bindings.map(\.action))
        #expect(model.bindings.map(\.shortcut) == Config.defaultShortcuts.bindings.map(\.shortcut))
        #expect(model.resizeStep == 0.2)
        #expect(backend.config.resizeStep == 0.2)
        #expect(backend.config.bindings.count == 33)
        #expect(model.error == nil)
    }

    @Test("the restored bindings have IDs that the replaced ones did not have")
    func restoreDefaultsNewIDs() {
        let (model, _) = make()
        let before = Set(model.bindings.map(\.id))

        #expect(model.restoreDefaultShortcuts())

        #expect(Set(model.bindings.map(\.id)).isDisjoint(with: before))
    }

    @Test("asking and then cancelling changes nothing: no copy, no save, the bindings stay")
    func restoreCancelChangesNothing() {
        let (model, backend) = make()
        let before = model.config

        model.askToRestoreDefaults()
        #expect(model.isConfirmingRestore)
        model.cancelRestoreDefaults()

        #expect(!model.isConfirmingRestore)
        #expect(model.config == before)
        #expect(backend.saved.isEmpty)
        #expect(backend.copies.isEmpty)
        #expect(model.backupName == nil)
        #expect(model.error == nil)
    }

    @Test("asking does not replace anything until the restore is performed")
    func askingChangesNothing() {
        let (model, backend) = make()
        let before = model.config

        model.askToRestoreDefaults()

        #expect(model.config == before)
        #expect(backend.saved.isEmpty)
        #expect(backend.copies.isEmpty)
    }

    @Test("performing a restore dismisses the confirmation")
    func restoreDismissesConfirmation() {
        let (model, _) = make()
        model.askToRestoreDefaults()
        #expect(model.restoreDefaultShortcuts())
        #expect(!model.isConfirmingRestore)
    }

    @Test("a restore without a config file keeps no copy and still replaces the bindings")
    func restoreWithoutFile() {
        let (model, backend) = make(.default)
        backend.hasFile = false

        #expect(model.restoreDefaultShortcuts())

        #expect(backend.copies.isEmpty)
        #expect(model.backupName == nil)
        #expect(model.bindings.count == 33)
        #expect(backend.config.bindings.count == 33)
    }

    @Test("a restore the backend cannot carry out changes nothing, and the error says why")
    func restoreFailure() {
        let (model, backend) = make()
        let before = model.config
        backend.failure = "the disk is full"

        #expect(!model.restoreDefaultShortcuts())

        #expect(model.config == before)
        #expect(model.backupName == nil)
        #expect(backend.saved.isEmpty)
        #expect(model.error?.contains("the disk is full") == true)
    }

    @Test("a restore ends a recording and gives the hotkeys back")
    func restoreEndsRecording() {
        let (model, backend) = make()
        model.beginRecording(.builtIn(.moveToDisplay(.next)))
        #expect(backend.isSuspended)

        #expect(model.restoreDefaultShortcuts())

        #expect(!model.isRecording)
        #expect(!backend.isSuspended)
        // The new bindings were saved while the hotkeys were suspended, and then registered.
        #expect(backend.suspendedAtSave.last == true)
    }

    // MARK: Window settings

    @Test("the window settings start as the backend's config holds them")
    func windowSettingsStart() {
        let config = Config(
            resizeStep: 0.1, animation: .slow, gridFillOrder: .columns, destinationPreview: false,
            bindings: UIFixture.twoBindings().bindings)
        let (model, _) = make(config)

        #expect(model.animation == .slow)
        #expect(model.gridFillOrder == .columns)
        #expect(model.destinationPreview == false)
        #expect(model.config == config)
    }

    @Test("a window animation is saved and shown", arguments: WindowAnimation.allCases)
    func animationAccepted(_ value: WindowAnimation) {
        let (model, backend) = make()
        #expect(model.setAnimation(value))
        #expect(model.animation == value)
        #expect(backend.config.animation == value)
    }

    @Test("a grid fill order is saved and shown", arguments: GridFillOrder.allCases)
    func gridFillOrderAccepted(_ value: GridFillOrder) {
        let (model, backend) = make()
        #expect(model.setGridFillOrder(value))
        #expect(model.gridFillOrder == value)
        #expect(backend.config.gridFillOrder == value)
    }

    @Test("the destination preview is saved and shown", arguments: [true, false])
    func destinationPreviewAccepted(_ value: Bool) {
        let (model, backend) = make()
        #expect(model.setDestinationPreview(value))
        #expect(model.destinationPreview == value)
        #expect(backend.config.destinationPreview == value)
    }

    @Test("a refused save leaves the window settings as they were, and says why")
    func windowSettingsRefused() {
        let (model, backend) = make()
        backend.failure = "the config file was written by a newer version"
        let before = model.config

        #expect(!model.setAnimation(.slow))
        #expect(!model.setGridFillOrder(.columns))
        #expect(!model.setDestinationPreview(false))

        #expect(model.config == before)
        #expect(model.animation == .fast)
        #expect(model.gridFillOrder == .rows)
        #expect(model.destinationPreview == Config.defaultDestinationPreview)
        #expect(backend.saved.isEmpty)
        #expect(model.error?.contains("newer version") == true)
    }

    @Test("restoring the default shortcuts keeps the resize step and the window settings")
    func restoreKeepsWindowSettings() {
        let config = Config(
            resizeStep: 0.2, animation: .slow, gridFillOrder: .columns, destinationPreview: false,
            bindings: UIFixture.twoBindings().bindings)
        let (model, backend) = make(config)

        #expect(model.restoreDefaultShortcuts())

        #expect(model.bindings.count == 33)
        #expect(model.resizeStep == 0.2)
        #expect(model.animation == .slow)
        #expect(model.gridFillOrder == .columns)
        #expect(model.destinationPreview == false)
        #expect(backend.config.bindings.count == 33)
        #expect(backend.config.resizeStep == 0.2)
        #expect(backend.config.animation == .slow)
        #expect(backend.config.gridFillOrder == .columns)
        #expect(backend.config.destinationPreview == false)
    }

    @Test("a config replaced from outside brings its window settings")
    func externalChangeWindowSettings() {
        let (model, backend) = make()

        backend.replaceFromOutside(Config(animation: .off, gridFillOrder: .columns, destinationPreview: false))

        #expect(model.animation == .off)
        #expect(model.gridFillOrder == .columns)
        #expect(model.destinationPreview == false)
    }
}
