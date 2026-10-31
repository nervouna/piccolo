import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

/// Undo and redo of the changes made in the Settings window: the history the model keeps, what a
/// step is, and what ends it.
@MainActor
@Suite("Settings undo")
struct SettingsUndoModelTests {
    private static let leftHalfAction = Action.placeWindow(.preset(.leftHalf))
    private static let rightHalfAction = Action.placeWindow(.preset(.rightHalf))
    private static let topLeftAction = Action.placeWindow(.preset(.topLeft))
    private static let gridAction = Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))

    private let leftRow = KeymapRowID.builtIn(SettingsUndoModelTests.leftHalfAction)
    private let rightRow = KeymapRowID.builtIn(SettingsUndoModelTests.rightHalfAction)
    private let topLeftRow = KeymapRowID.builtIn(SettingsUndoModelTests.topLeftAction)

    private let left = KeyBinding(action: leftHalfAction, shortcut: UIFixture.f13)
    private let right = KeyBinding(action: rightHalfAction, shortcut: UIFixture.f14)

    private func make(
        _ config: Config? = nil, language: FakeLanguage = FakeLanguage(), loginItem: FakeLoginItem = FakeLoginItem()
    ) -> (model: SettingsModel, backend: InMemorySettingsBackend) {
        let backend = InMemorySettingsBackend(
            config: config ?? Config(animation: .fast, gridFillOrder: .rows, gap: 16, bindings: [left, right]))
        let model = SettingsModel(backend: backend, loginItem: loginItem, language: language) { code in
            ["0": "a", "11": "b"][String(code)]
        }
        return (model, backend)
    }

    // MARK: A setting

    @Test("a model starts with nothing to undo or redo")
    func startsEmpty() {
        let (model, _) = make()
        #expect(!model.canUndo)
        #expect(!model.canRedo)
    }

    @Test("a setting can be undone and redone, each saved through the backend")
    func undoRedoSetting() {
        let (model, backend) = make()

        #expect(model.setGap(20))
        #expect(model.canUndo)
        #expect(!model.canRedo)

        #expect(model.undo())
        #expect(model.gap == 16)
        #expect(backend.config.gap == 16)
        #expect(model.config == backend.config)
        #expect(!model.canUndo)
        #expect(model.canRedo)

        #expect(model.redo())
        #expect(model.gap == 20)
        #expect(backend.config.gap == 20)
        #expect(model.canUndo)
        #expect(!model.canRedo)
        #expect(backend.saved.map(\.gap) == [20, 16, 20])
        #expect(model.error == nil)
    }

    @Test("every kind of setting is a step of its own, undone in the reverse order")
    func undoManySettings() {
        let (model, _) = make()
        let original = model.config

        model.setGap(24)
        model.setResizeStep(0.1)
        model.setAnimation(.slow)
        model.setGridFillOrder(.columns)
        model.setDestinationPreview(!original.destinationPreview)

        #expect(model.undo())
        #expect(model.destinationPreview == original.destinationPreview)
        #expect(model.gridFillOrder == .columns)
        #expect(model.undo())
        #expect(model.gridFillOrder == original.gridFillOrder)
        #expect(model.undo())
        #expect(model.animation == original.animation)
        #expect(model.undo())
        #expect(model.resizeStep == original.resizeStep)
        #expect(model.undo())
        #expect(model.config == original)
        #expect(!model.canUndo)
        #expect(!model.undo())
    }

    @Test("a change that changes nothing, or is refused, is no step")
    func noStepForNoChange() {
        let (model, _) = make()

        #expect(model.setGap(16))
        #expect(!model.canUndo)

        #expect(!model.setGap(1000))
        #expect(!model.setResizeStep(0))
        #expect(!model.canUndo)
        #expect(!model.canRedo)
    }

    @Test("a refused change leaves the history as it was")
    func refusedChangeKeepsHistory() {
        let (model, backend) = make()
        model.setGap(20)
        model.undo()
        #expect(model.canRedo)

        backend.failure = "disk full"
        #expect(!model.setGap(30))

        #expect(model.canRedo)
        #expect(!model.canUndo)
    }

    @Test("nothing to undo or redo is refused, and changes nothing, not even the error")
    func nothingToDo() {
        let (model, backend) = make()
        model.setGap(1000)
        let error = model.error
        #expect(error != nil)

        #expect(!model.undo())
        #expect(!model.redo())

        #expect(backend.saved.isEmpty)
        #expect(model.error == error)
        #expect(model.config == backend.config)
    }

    // MARK: A recorded shortcut

    @Test("a recorded shortcut can be undone and redone")
    func undoRedoRecording() {
        let (model, backend) = make()
        model.beginRecording(topLeftRow)
        model.record(UIFixture.f15)
        #expect(model.bindings.count == 3)

        #expect(model.undo())
        #expect(model.bindings == [left, right])
        #expect(backend.config.bindings == [left, right])

        #expect(model.redo())
        #expect(model.bindings.count == 3)
        #expect(model.bindings.last?.shortcut == UIFixture.f15)
        #expect(backend.config.bindings == model.bindings)
    }

    @Test("a shortcut that is cleared comes back with undo")
    func undoClear() {
        let (model, backend) = make()
        model.clearShortcut(leftRow)
        #expect(model.binding(left.id) == nil)

        #expect(model.undo())

        #expect(model.binding(left.id) == left)
        #expect(backend.config.bindings == [left, right])
    }

    @Test("an added layout and an edited one are steps, and so is a removed binding")
    func undoLayouts() throws {
        let (model, _) = make()
        let id = try #require(model.addLayout(Self.gridAction))
        model.cancelRecording()
        let changed = Action.arrangeGrid(GridSpec(count: 3, rows: 1, columns: 3))
        #expect(model.updateLayout(id, to: changed))
        #expect(model.removeBinding(left.id))

        #expect(model.undo())
        #expect(model.binding(left.id) == left)
        #expect(model.undo())
        #expect(model.binding(id)?.action == Self.gridAction)
        #expect(model.undo())
        #expect(model.binding(id) == nil)
        #expect(model.bindings == [left, right])
    }

    // MARK: A conflict

    @Test("a conflict that was replaced is one step: undo gives both bindings their shortcut back")
    func undoReplacedConflict() {
        let (model, backend) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)
        #expect(model.pendingConflict != nil)
        #expect(model.resolveConflict(replace: true))
        #expect(model.binding(left.id) == nil)
        #expect(model.binding(right.id)?.shortcut == UIFixture.f13)

        #expect(model.undo())

        #expect(model.binding(left.id)?.shortcut == UIFixture.f13)
        #expect(model.binding(right.id)?.shortcut == UIFixture.f14)
        #expect(model.bindings == [left, right])
        #expect(backend.config.bindings == [left, right])
        #expect(!model.canUndo)

        #expect(model.redo())
        #expect(model.binding(left.id) == nil)
        #expect(model.binding(right.id)?.shortcut == UIFixture.f13)
        #expect(backend.config.bindings.map(\.id) == [right.id])
    }

    @Test("a conflict that is dropped is no step")
    func droppedConflictIsNoStep() {
        let (model, _) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)
        #expect(model.resolveConflict(replace: false))
        #expect(!model.canUndo)
    }

    // MARK: Restoring the defaults

    @Test("restoring the default shortcuts is one step: undo brings the bindings back, redo restores the defaults")
    func undoRedoRestore() {
        let (model, backend) = make()
        let before = model.config

        #expect(model.restoreDefaultShortcuts())
        let restored = model.config
        #expect(restored.bindings.count == 33)
        #expect(backend.copies.count == 1)

        #expect(model.undo())
        #expect(model.config == before)
        #expect(backend.config == before)
        #expect(!model.canUndo)

        #expect(model.redo())
        #expect(model.config == restored)
        #expect(backend.config == restored)
        #expect(!model.canRedo)
        // The copy of the file belongs to the restore; undo and redo make no more.
        #expect(backend.copies.count == 1)
    }

    @Test("a restore that the backend cannot save is no step")
    func refusedRestoreIsNoStep() {
        let (model, backend) = make()
        backend.failure = "disk full"

        #expect(!model.restoreDefaultShortcuts())

        #expect(!model.canUndo)
    }

    // MARK: A new change after an undo

    @Test("a new change after an undo drops the steps that could be redone")
    func newChangeDropsRedo() {
        let (model, _) = make()
        model.setGap(20)
        model.setGap(24)
        model.undo()
        #expect(model.canRedo)

        model.setAnimation(.slow)

        #expect(!model.canRedo)
        #expect(!model.redo())
        #expect(model.gap == 20)
        #expect(model.animation == .slow)
        #expect(model.canUndo)
    }

    // MARK: The limit

    /// Makes `count` changes of the gap, each a different value from the one before it.
    private func changeGap(_ model: SettingsModel, times count: Int) {
        for step in 1...count {
            #expect(model.setGap(step % 65))
        }
    }

    @Test("the history keeps 100 steps")
    func limitKeepsHundred() {
        let (model, _) = make(Config(gap: 0, bindings: [left]))
        #expect(SettingsModel.historyLimit == 100)

        changeGap(model, times: 100)
        var undone = 0
        while model.undo() { undone += 1 }

        #expect(undone == 100)
        #expect(model.gap == 0)
        #expect(!model.canUndo)
        #expect(model.canRedo)
    }

    @Test("the 101st step pushes out the oldest")
    func limitDropsOldest() {
        let (model, _) = make(Config(gap: 0, bindings: [left]))

        changeGap(model, times: 101)
        var undone = 0
        while model.undo() { undone += 1 }

        #expect(undone == 100)
        // The first change (0 to 1) is out of the history: the oldest state that is left is its result.
        #expect(model.gap == 1)
        #expect(!model.canUndo)
    }

    @Test("a long history is redone as far as it was undone")
    func limitAndRedo() {
        let (model, _) = make(Config(gap: 0, bindings: [left]))
        changeGap(model, times: 130)
        let last = model.gap
        while model.undo() {}

        var redone = 0
        while model.redo() { redone += 1 }

        #expect(redone == 100)
        #expect(model.gap == last)
    }

    @Test("the steps that were undone are as many as the redo can take back")
    func redoAllTheWay() {
        let (model, _) = make()
        model.setGap(20)
        model.setGap(24)
        model.setGap(30)
        while model.undo() {}
        #expect(model.gap == 16)

        var redone = 0
        while model.redo() { redone += 1 }

        #expect(redone == 3)
        #expect(model.gap == 30)
    }

    // MARK: A reload

    @Test("a reload clears both histories")
    func reloadClearsHistory() {
        let (model, backend) = make()
        model.setGap(20)
        model.setGap(24)
        model.undo()
        #expect(model.canUndo)
        #expect(model.canRedo)

        backend.replaceFromOutside(Config(gap: 5, bindings: [right]))

        #expect(!model.canUndo)
        #expect(!model.canRedo)
        #expect(!model.undo())
        #expect(!model.redo())
        #expect(model.gap == 5)
    }

    @Test("a reload that changes nothing clears the history too")
    func reloadOfTheSameConfig() {
        let (model, _) = make()
        model.setGap(20)

        model.reload()

        #expect(!model.canUndo)
    }

    // MARK: A save that is refused

    @Test("a save the backend refuses during an undo changes nothing and names the window")
    func refusedUndo() {
        let (model, backend) = make()
        model.setGap(20)
        backend.failure = "disk full"

        #expect(!model.undo())

        #expect(model.gap == 20)
        #expect(backend.config.gap == 20)
        #expect(model.error?.contains("disk full") == true)
        #expect(model.errorTarget == .window)
        #expect(model.canUndo)
        #expect(!model.canRedo)

        backend.failure = nil
        #expect(model.undo())
        #expect(model.gap == 16)
        #expect(model.error == nil)
        #expect(model.errorTarget == nil)
    }

    @Test("a save the backend refuses during a redo changes nothing and names the window")
    func refusedRedo() {
        let (model, backend) = make()
        model.setGap(20)
        model.undo()
        backend.failure = "disk full"

        #expect(!model.redo())

        #expect(model.gap == 16)
        #expect(model.error?.contains("disk full") == true)
        #expect(model.errorTarget == .window)
        #expect(model.canRedo)
        #expect(!model.canUndo)

        backend.failure = nil
        #expect(model.redo())
        #expect(model.gap == 20)
    }

    @Test("a successful undo clears an earlier error")
    func undoClearsError() {
        let (model, _) = make()
        model.setGap(20)
        model.setGap(1000)
        #expect(model.error != nil)

        #expect(model.undo())

        #expect(model.error == nil)
        #expect(model.errorTarget == nil)
    }

    // MARK: A recording and a conflict

    @Test("undo ends a recording and brings the hotkeys back")
    func undoEndsRecording() {
        let (model, backend) = make()
        model.setGap(20)
        model.beginRecording(topLeftRow)
        #expect(backend.isSuspended)

        #expect(model.undo())

        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
        #expect(model.gap == 16)
    }

    @Test("redo ends a recording and brings the hotkeys back")
    func redoEndsRecording() {
        let (model, backend) = make()
        model.setGap(20)
        model.undo()
        model.beginRecording(leftRow)

        #expect(model.redo())

        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
    }

    @Test("a recording that goes on is not ended by an undo that is refused")
    func refusedUndoKeepsRecording() {
        let (model, backend) = make()
        model.setGap(20)
        model.beginRecording(leftRow)
        backend.failure = "disk full"

        #expect(!model.undo())

        #expect(model.recordingRow == leftRow)
        #expect(backend.isSuspended)
    }

    @Test("an undo of the layout whose recording is going on ends the recording")
    func undoOfTheRecordingLayout() throws {
        let (model, backend) = make()
        let id = try #require(model.addLayout(Self.gridAction))
        #expect(model.recordingRow == .layout(id))

        #expect(model.undo())

        #expect(model.binding(id) == nil)
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
    }

    @Test("undo and redo drop a pending conflict")
    func undoDropsConflict() {
        let (model, _) = make()
        model.setGap(20)
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)
        #expect(model.pendingConflict != nil)

        #expect(model.undo())
        #expect(model.pendingConflict == nil)

        model.beginRecording(rightRow)
        model.record(UIFixture.f13)
        #expect(model.pendingConflict != nil)

        #expect(model.redo())
        #expect(model.pendingConflict == nil)
    }

    @Test("a request for the sheet of a layout that an undo removed is dismissed")
    func undoDismissesSheetOfRemovedLayout() throws {
        let (model, _) = make()
        let id = try #require(model.addLayout(Self.gridAction))
        model.cancelRecording()
        model.editLayout(.edit(id))
        #expect(model.layoutEditor == .edit(id))

        #expect(model.undo())

        #expect(model.layoutEditor == nil)
    }

    @Test("a request for a new layout's sheet stays through an undo")
    func undoKeepsNewLayoutSheet() {
        let (model, _) = make()
        model.setGap(20)
        model.editLayout(.new(.grids))

        #expect(model.undo())

        #expect(model.layoutEditor == .new(.grids))
    }

    // MARK: What is not in the history

    @Test("launch at login and the language are not in the history")
    func systemSettingsAreNotInTheHistory() {
        let language = FakeLanguage()
        let loginItem = FakeLoginItem()
        let (model, _) = make(language: language, loginItem: loginItem)

        model.setLaunchAtLogin(true)
        model.setLanguage(.ja)

        #expect(!model.canUndo)
        #expect(!model.canRedo)

        model.setGap(20)
        model.setLaunchAtLogin(false)
        model.setLanguage(.fr)
        #expect(model.undo())

        #expect(model.gap == 16)
        #expect(language.storedLanguage == .fr)
        #expect(model.language == .fr)
        #expect(loginItem.requests == [true, false])
    }

    @Test("the model's config after an undo is the one the backend holds, and its issues are the backend's")
    func undoRefreshesIssues() {
        let (model, backend) = make()
        model.setGap(20)
        backend.issuesAfterSave = ["a shortcut was refused"]

        #expect(model.undo())

        #expect(model.issues == ["a shortcut was refused"])
        #expect(model.config == backend.config)
    }
}
