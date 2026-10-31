import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

/// Recording a shortcut for a row of the keymap, the conflicts it finds, and where errors show.
@MainActor
@Suite("Keymap model")
struct KeymapModelTests {
    private static let leftHalfAction = Action.placeWindow(.preset(.leftHalf))
    private static let rightHalfAction = Action.placeWindow(.preset(.rightHalf))
    private static let topLeftAction = Action.placeWindow(.preset(.topLeft))
    private static let nextAction = Action.moveToDisplay(.next)
    private static let gridAction = Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))
    private static let areaAction = Action.placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)))

    private let leftRow = KeymapRowID.builtIn(KeymapModelTests.leftHalfAction)
    private let rightRow = KeymapRowID.builtIn(KeymapModelTests.rightHalfAction)
    private let topLeftRow = KeymapRowID.builtIn(KeymapModelTests.topLeftAction)
    private let nextRow = KeymapRowID.builtIn(KeymapModelTests.nextAction)

    private let left = KeyBinding(action: leftHalfAction, shortcut: UIFixture.f13)
    private let right = KeyBinding(action: rightHalfAction, shortcut: UIFixture.f14)
    private let grid = KeyBinding(action: gridAction, shortcut: UIFixture.f15)
    private let area = KeyBinding(action: areaAction)

    private func make(
        _ bindings: [KeyBinding]? = nil
    ) -> (model: SettingsModel, backend: InMemorySettingsBackend) {
        let backend = InMemorySettingsBackend(config: Config(bindings: bindings ?? [left, right, grid, area]))
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage()) { code in
            ["0": "a", "11": "b"][String(code)]
        }
        return (model, backend)
    }

    private let escape = Shortcut(keyCode: ShortcutText.escapeKeyCode, modifiers: [])
    private let delete = Shortcut(keyCode: 51, modifiers: [])
    private let forwardDelete = Shortcut(keyCode: 117, modifiers: [])
    private let shiftA = Shortcut(keyCode: 0, modifiers: [.shift])
    private let plainA = Shortcut(keyCode: 0, modifiers: [])
    private let hyperF16 = Shortcut(keyCode: FunctionKey.f16, modifiers: UIFixture.hyper)

    // MARK: Beginning a recording

    @Test("beginning a recording on a row marks it, suspends the hotkeys and clears the error")
    func beginRecordingRow() {
        let (model, backend) = make()
        model.setGap(100)
        #expect(model.error != nil)

        #expect(model.beginRecording(leftRow))

        #expect(model.recordingRow == leftRow)
        #expect(model.isRecording)
        #expect(model.recordingBindingID == nil)
        #expect(model.error == nil)
        #expect(model.errorTarget == nil)
        #expect(backend.suspendRequests == [true])
        #expect(backend.isSuspended)
        #expect(model.inactiveBindingIDs.isEmpty)
    }

    @Test("a built-in row is there whether a binding has its action or not")
    func beginRecordingUnboundRow() {
        let (model, _) = make()
        #expect(model.beginRecording(topLeftRow))
        #expect(model.recordingRow == topLeftRow)
    }

    @Test("a row that does not exist cannot be recorded: the error is the window's and nothing is suspended")
    func beginRecordingMissingRow() {
        let (model, backend) = make()

        // A layout ID nobody has, the ID of a built-in binding (not a layout), and a layout as a built-in row.
        for row in [
            KeymapRowID.layout(UUID()), KeymapRowID.layout(left.id), KeymapRowID.builtIn(Self.gridAction),
        ] {
            #expect(!model.beginRecording(row))
            #expect(model.recordingRow == nil)
            #expect(model.errorTarget == .window)
            #expect(model.error != nil)
        }
        #expect(backend.suspendRequests.isEmpty)
        #expect(!model.isRecording)
    }

    @Test("a recording of a binding and a recording of a row replace each other")
    func rowAndBindingRecordingReplaceEachOther() {
        let (model, backend) = make()

        model.beginRecording(left.id)
        #expect(model.isRecording)
        #expect(model.recordingRow == nil)

        model.beginRecording(rightRow)
        #expect(model.recordingBindingID == nil)
        #expect(model.recordingRow == rightRow)

        model.beginRecording(right.id)
        #expect(model.recordingRow == nil)
        #expect(model.recordingBindingID == right.id)
        #expect(model.isRecording)

        // The hotkeys stay suspended throughout and come back once.
        #expect(!backend.suspendRequests.contains(false))
        model.cancelRecording()
        #expect(!model.isRecording)
        #expect(model.recordingRow == nil)
        #expect(model.recordingBindingID == nil)
        #expect(backend.suspendRequests.last == false)
        #expect(!backend.isSuspended)
    }

    @Test("cancelling a recording of a row restores the hotkeys and refreshes the issues")
    func cancelRecordingRow() {
        let (model, backend) = make()
        backend.issuesAfterResume = ["the system refused a shortcut"]
        model.beginRecording(leftRow)

        model.cancelRecording()

        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
        #expect(model.issues == ["the system refused a shortcut"])
    }

    @Test("a press is not taken when nothing is recording")
    func noRecording() {
        let (model, backend) = make()
        #expect(!model.record(hyperF16))
        #expect(model.pressesTaken == 0)
        #expect(backend.saved.isEmpty)
    }

    // MARK: Escape and Delete

    @Test("Escape alone cancels: nothing changes and the hotkeys come back")
    func escapeCancels() {
        let (model, backend) = make()
        model.beginRecording(leftRow)

        #expect(model.record(escape))

        #expect(model.recordingRow == nil)
        #expect(model.pressesTaken == 1)
        #expect(backend.saved.isEmpty)
        #expect(backend.suspendRequests == [true, false])
        #expect(model.error == nil)
        #expect(model.pendingConflict == nil)
    }

    @Test("Escape with a modifier is a shortcut, not a cancel")
    func escapeWithModifier() {
        let (model, backend) = make()
        model.beginRecording(topLeftRow)
        let press = Shortcut(keyCode: ShortcutText.escapeKeyCode, modifiers: [.control])

        model.record(press)

        #expect(backend.saved.last?.bindings.last?.shortcut == press)
    }

    @Test("Escape also takes away the reason shown under the row for a shortcut that cannot be global")
    func escapeClearsRowError() {
        let (model, _) = make()
        model.beginRecording(leftRow)
        model.record(shiftA)
        #expect(model.errorTarget == .row(leftRow))

        model.record(escape)

        #expect(model.recordingRow == nil)
        #expect(model.error == nil)
        #expect(model.errorTarget == nil)
    }

    @Test("Delete clears a built-in row: its first binding is removed from the config", arguments: [51, 117])
    func deleteRemovesBuiltInBinding(keyCode: Int) {
        let (model, backend) = make()
        model.beginRecording(leftRow)

        #expect(model.record(Shortcut(keyCode: keyCode, modifiers: [])))

        #expect(model.bindings.map(\.id) == [right.id, grid.id, area.id])
        #expect(backend.saved.count == 1)
        #expect(backend.saved.last?.bindings.map(\.id) == [right.id, grid.id, area.id])
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
        #expect(model.error == nil)
    }

    @Test("Delete clears a layout row: its shortcut becomes nil and the binding stays", arguments: [51, 117])
    func deleteClearsLayoutShortcut(keyCode: Int) {
        let (model, backend) = make()
        model.beginRecording(.layout(grid.id))

        model.record(Shortcut(keyCode: keyCode, modifiers: []))

        #expect(model.bindings.map(\.id) == [left.id, right.id, grid.id, area.id])
        #expect(model.binding(grid.id)?.shortcut == nil)
        #expect(model.binding(grid.id)?.action == Self.gridAction)
        #expect(backend.saved.count == 1)
        #expect(model.recordingRow == nil)
    }

    @Test("Delete on a row without a binding changes nothing and ends the recording")
    func deleteOnUnboundRow() {
        let (model, backend) = make()
        model.beginRecording(topLeftRow)

        model.record(delete)

        #expect(backend.saved.isEmpty)
        #expect(model.bindings.count == 4)
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
    }

    @Test("Delete with a modifier is a shortcut, not a clear")
    func deleteWithModifier() {
        let (model, backend) = make()
        model.beginRecording(topLeftRow)
        let press = Shortcut(keyCode: 51, modifiers: [.command])

        model.record(press)

        #expect(backend.saved.last?.bindings.last?.shortcut == press)
    }

    @Test("clearShortcut removes only the first binding of a built-in row")
    func clearShortcutKeepsTheExtraBindings() {
        let extra = KeyBinding(action: Self.leftHalfAction, shortcut: hyperF16)
        let (model, backend) = make([left, right, extra])

        #expect(model.clearShortcut(leftRow))

        #expect(model.bindings.map(\.id) == [right.id, extra.id])
        #expect(backend.saved.count == 1)
        #expect(model.recordingRow == nil)
    }

    @Test("clearShortcut of a layout row sets the shortcut to nil, and of an unbound row is no change")
    func clearShortcutLayoutAndUnbound() {
        let (model, backend) = make()

        #expect(model.clearShortcut(.layout(grid.id)))
        #expect(model.binding(grid.id)?.shortcut == nil)
        #expect(backend.saved.count == 1)

        #expect(model.clearShortcut(topLeftRow))
        #expect(model.clearShortcut(.layout(area.id)))
        #expect(backend.saved.count == 1)
        #expect(model.error == nil)
    }

    @Test("clearShortcut of a row that does not exist is refused")
    func clearShortcutMissingRow() {
        let (model, backend) = make()
        #expect(!model.clearShortcut(.layout(UUID())))
        #expect(model.errorTarget == .window)
        #expect(backend.saved.isEmpty)
    }

    @Test("a clear the backend cannot save leaves the config and names the row")
    func clearShortcutNotSaved() {
        let (model, backend) = make()
        backend.failure = "the disk is full"
        model.beginRecording(leftRow)

        model.record(delete)

        #expect(model.bindings.count == 4)
        #expect(model.error?.contains("the disk is full") == true)
        #expect(model.errorTarget == .row(leftRow))
        #expect(model.recordingRow == nil)
    }

    // MARK: A shortcut that cannot be global

    @Test("a shortcut that cannot be registered changes nothing, names the row, and recording goes on")
    func notRegistrableKeepsRecording() {
        let (model, backend) = make()
        model.beginRecording(leftRow)

        for press in [shiftA, plainA] {
            #expect(model.record(press))

            #expect(model.recordingRow == leftRow)
            #expect(model.isRecording)
            #expect(model.errorTarget == .row(leftRow))
            #expect(model.error == SettingsMessages.notRegistrable(model.shortcutText(for: press)))
            #expect(backend.saved.isEmpty)
            #expect(backend.suspendRequests == [true], "the hotkeys came back")
            #expect(backend.isSuspended)
            #expect(model.pendingConflict == nil)
        }
        #expect(model.pressesTaken == 2)

        // The next acceptable shortcut is taken, and the error goes.
        model.record(hyperF16)
        #expect(model.binding(left.id)?.shortcut == hyperF16)
        #expect(model.recordingRow == nil)
        #expect(model.error == nil)
        #expect(model.errorTarget == nil)
        #expect(!backend.isSuspended)
    }

    // MARK: A shortcut another binding has

    @Test("a shortcut another binding has changes nothing, ends the recording and holds the conflict")
    func conflictHeld() {
        let (model, backend) = make()
        model.beginRecording(rightRow)

        model.record(UIFixture.f13)

        #expect(backend.saved.isEmpty)
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
        #expect(
            model.pendingConflict
                == ShortcutConflict(row: rightRow, shortcut: UIFixture.f13, ownerBindingID: left.id))
        #expect(model.error == nil)
        #expect(model.binding(right.id)?.shortcut == UIFixture.f14)
    }

    @Test("replacing a conflict takes the shortcut from a built-in owner, whose binding is removed, in one save")
    func replaceBuiltInOwner() {
        let (model, backend) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)

        #expect(model.resolveConflict(replace: true))

        #expect(model.pendingConflict == nil)
        #expect(backend.saved.count == 1)
        #expect(model.bindings.map(\.id) == [right.id, grid.id, area.id])
        #expect(model.binding(right.id)?.shortcut == UIFixture.f13)
        #expect(model.error == nil)
    }

    @Test("replacing a conflict gives the shortcut to a row without a binding as a new binding")
    func replaceForUnboundRow() throws {
        let (model, backend) = make()
        model.beginRecording(topLeftRow)
        model.record(UIFixture.f13)
        #expect(model.pendingConflict?.ownerBindingID == left.id)

        #expect(model.resolveConflict(replace: true))

        #expect(backend.saved.count == 1)
        #expect(model.bindings.count == 4)
        #expect(model.binding(left.id) == nil)
        let added = try #require(model.bindings.last)
        #expect(added.action == Self.topLeftAction)
        #expect(added.shortcut == UIFixture.f13)
        #expect(![left.id, right.id, grid.id, area.id].contains(added.id))
    }

    @Test("replacing a conflict takes the shortcut from a layout owner, which stays without a shortcut")
    func replaceLayoutOwner() {
        let (model, backend) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f15)
        #expect(model.pendingConflict == ShortcutConflict(row: rightRow, shortcut: UIFixture.f15, ownerBindingID: grid.id))

        #expect(model.resolveConflict(replace: true))

        #expect(backend.saved.count == 1)
        #expect(model.bindings.map(\.id) == [left.id, right.id, grid.id, area.id])
        #expect(model.binding(grid.id)?.shortcut == nil)
        #expect(model.binding(grid.id)?.action == Self.gridAction)
        #expect(model.binding(right.id)?.shortcut == UIFixture.f15)
    }

    @Test("a layout row can take a shortcut from a built-in row, and the other way round")
    func replaceAcrossKinds() {
        let (model, _) = make()
        model.beginRecording(.layout(area.id))
        model.record(UIFixture.f13)
        #expect(model.resolveConflict(replace: true))
        #expect(model.binding(area.id)?.shortcut == UIFixture.f13)
        #expect(model.binding(left.id) == nil)
    }

    @Test("cancelling a conflict drops it and changes nothing")
    func cancelConflict() {
        let (model, backend) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)

        #expect(model.resolveConflict(replace: false))

        #expect(model.pendingConflict == nil)
        #expect(backend.saved.isEmpty)
        #expect(model.config == Config(bindings: [left, right, grid, area]))
        #expect(model.error == nil)
    }

    @Test("resolving with no conflict pending does nothing")
    func resolveWithoutConflict() {
        let (model, backend) = make()
        #expect(!model.resolveConflict(replace: true))
        #expect(!model.resolveConflict(replace: false))
        #expect(backend.saved.isEmpty)
        #expect(model.error == nil)
    }

    @Test("beginning a recording drops a pending conflict")
    func beginningDropsConflict() {
        let (model, _) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)
        #expect(model.pendingConflict != nil)

        model.beginRecording(leftRow)

        #expect(model.pendingConflict == nil)
    }

    @Test("beginning a recording of a binding drops a pending conflict too")
    func beginningBindingDropsConflict() {
        let (model, _) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)

        model.beginRecording(right.id)

        #expect(model.pendingConflict == nil)
    }

    @Test("any accepted change drops a pending conflict, and one that is refused does not")
    func acceptedChangeDropsConflict() {
        let (model, _) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)

        model.setGap(100)
        #expect(model.pendingConflict != nil, "a refused change dropped the conflict")

        #expect(model.setGap(8))
        #expect(model.pendingConflict == nil)
    }

    @Test("a reload drops a pending conflict")
    func reloadDropsConflict() {
        let (model, backend) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)

        backend.replaceFromOutside(Config(bindings: [left, right]))

        #expect(model.pendingConflict == nil)
    }

    @Test("a replace the backend cannot save changes nothing, names the row and keeps the conflict")
    func replaceNotSaved() {
        let (model, backend) = make()
        model.beginRecording(rightRow)
        model.record(UIFixture.f13)
        backend.failure = "the disk is full"
        let before = model.config

        #expect(!model.resolveConflict(replace: true))

        #expect(model.config == before)
        #expect(model.error?.contains("the disk is full") == true)
        #expect(model.errorTarget == .row(rightRow))
        #expect(model.pendingConflict != nil)
    }

    @Test("a shortcut that an extra binding of the same row has is a conflict with that binding")
    func conflictWithAnExtraBinding() {
        let extra = KeyBinding(action: Self.leftHalfAction, shortcut: hyperF16)
        let (model, backend) = make([left, extra])
        model.beginRecording(leftRow)

        model.record(hyperF16)

        #expect(backend.saved.isEmpty)
        #expect(model.pendingConflict == ShortcutConflict(row: leftRow, shortcut: hyperF16, ownerBindingID: extra.id))

        #expect(model.resolveConflict(replace: true))
        #expect(model.bindings.map(\.id) == [left.id])
        #expect(model.binding(left.id)?.shortcut == hyperF16)
    }

    // MARK: The row's own shortcut and shortcuts that are accepted

    @Test("the row's own shortcut ends the recording and changes nothing")
    func ownShortcut() {
        let (model, backend) = make()
        model.beginRecording(leftRow)

        model.record(UIFixture.f13)

        #expect(backend.saved.isEmpty)
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
        #expect(model.pendingConflict == nil)
        #expect(model.error == nil)
    }

    @Test("a built-in row with a binding takes the shortcut on its first binding only")
    func setsTheFirstBinding() {
        let extra = KeyBinding(action: Self.leftHalfAction, shortcut: hyperF16)
        let (model, backend) = make([extra, left])
        // `extra` is first in the file, so it is the row's binding.
        model.beginRecording(leftRow)

        model.record(UIFixture.f14)

        #expect(model.binding(extra.id)?.shortcut == UIFixture.f14)
        #expect(model.binding(left.id)?.shortcut == UIFixture.f13)
        #expect(model.bindings.map(\.id) == [extra.id, left.id])
        #expect(backend.saved.count == 1)
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
        #expect(backend.suspendedAtSave == [true], "the hotkeys were not suspended during the save")
    }

    @Test("a built-in binding without a shortcut takes it")
    func setsABindingWithoutShortcut() {
        let unbound = KeyBinding(action: Self.nextAction)
        let (model, backend) = make([unbound])
        model.beginRecording(nextRow)

        model.record(UIFixture.f13)

        #expect(model.bindings == [KeyBinding(id: unbound.id, action: Self.nextAction, shortcut: UIFixture.f13)])
        #expect(backend.saved.count == 1)
    }

    @Test("a built-in row without a binding appends a new one with the action and the shortcut")
    func appendsABinding() throws {
        let (model, backend) = make()
        model.beginRecording(nextRow)

        model.record(hyperF16)

        #expect(model.bindings.count == 5)
        #expect(Array(model.bindings.prefix(4)) == [left, right, grid, area])
        let added = try #require(model.bindings.last)
        #expect(added.action == Self.nextAction)
        #expect(added.shortcut == hyperF16)
        #expect(![left.id, right.id, grid.id, area.id].contains(added.id))
        #expect(backend.saved.count == 1)
        #expect(backend.saved.last == model.config)
        #expect(model.recordingRow == nil)
        #expect(model.error == nil)
    }

    @Test("a layout row takes the shortcut on its own binding")
    func setsALayoutShortcut() {
        let (model, backend) = make()
        model.beginRecording(.layout(area.id))

        model.record(hyperF16)

        #expect(model.bindings.count == 4)
        #expect(model.binding(area.id)?.shortcut == hyperF16)
        #expect(model.binding(area.id)?.action == Self.areaAction)
        #expect(backend.saved.count == 1)
        #expect(model.recordingRow == nil)
    }

    @Test("a shortcut the backend cannot save ends the recording and names the row")
    func setNotSaved() {
        let (model, backend) = make()
        backend.failure = "the disk is full"
        model.beginRecording(nextRow)

        model.record(hyperF16)

        #expect(model.bindings.count == 4)
        #expect(model.error?.contains("the disk is full") == true)
        #expect(model.errorTarget == .row(nextRow))
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
    }

    @Test("a layout row that is removed while it records ends the recording")
    func removingARecordingLayoutRow() {
        let (model, backend) = make()
        model.beginRecording(.layout(area.id))

        #expect(model.removeBinding(area.id))

        #expect(model.recordingRow == nil)
        #expect(!model.isRecording)
        #expect(!backend.isSuspended)
    }

    @Test("a reload that loses a recording layout row ends the recording, one that keeps it does not")
    func reloadWithRecordingRow() {
        let (model, backend) = make()
        model.beginRecording(.layout(area.id))

        backend.replaceFromOutside(Config(bindings: [left, area]))
        #expect(model.recordingRow == .layout(area.id))
        #expect(backend.isSuspended)

        backend.replaceFromOutside(Config(bindings: [left]))
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
    }

    @Test("restoring the default shortcuts ends a recording of a row")
    func restoreEndsRowRecording() {
        let (model, backend) = make()
        model.beginRecording(leftRow)

        #expect(model.restoreDefaultShortcuts())

        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)
    }

    // MARK: The keymap and the search

    @Test("the model's keymap follows the search")
    func keymapFollowsSearch() {
        let (model, _) = make()
        #expect(model.keymap.map(\.section) == KeymapSection.allCases)

        model.setSearch(ActionSummary.text(for: Self.leftHalfAction))

        #expect(model.keymap.flatMap(\.rows).map(\.id) == [leftRow])
        model.setSearch("")
        #expect(model.keymap.map(\.section) == KeymapSection.allCases)
    }

    // MARK: Where errors show

    @Test("a window gap and a resize step that are refused name their field")
    func fieldErrors() {
        let (model, _) = make()

        #expect(!model.setGap(100))
        #expect(model.errorTarget == .field(.gap))
        #expect(model.error == SettingsMessages.describe(.outOfRange(field: "gap", rule: "x")))

        #expect(model.setGap(8))
        #expect(model.error == nil)
        #expect(model.errorTarget == nil)

        #expect(!model.setResizeStep(0.9))
        #expect(model.errorTarget == .field(.resizeStep))
        #expect(model.error != nil)

        model.clearError()
        #expect(model.error == nil)
        #expect(model.errorTarget == nil)
    }

    @Test("every other rejection names the window")
    func windowErrors() {
        let (model, backend) = make()

        backend.failure = "the disk is full"
        #expect(!model.setAnimation(.slow))
        #expect(model.errorTarget == .window)
        #expect(model.addBinding() == nil)
        #expect(model.errorTarget == .window)
        #expect(!model.setGap(8))
        #expect(model.errorTarget == .field(.gap), "a gap that cannot be saved is the gap's error")
        #expect(!model.restoreDefaultShortcuts())
        #expect(model.errorTarget == .window)
        backend.failure = nil

        #expect(!model.removeBinding(UUID()))
        #expect(model.errorTarget == .window)
        #expect(!model.updateAction(UUID(), to: Self.nextAction))
        #expect(model.errorTarget == .window)
        #expect(!model.setShortcut(UUID(), to: hyperF16))
        #expect(model.errorTarget == .window)
        #expect(!model.beginRecording(UUID()))
        #expect(model.errorTarget == .window)
    }

    @Test("a rejected shortcut of the binding-ID path names the row of that binding")
    func bindingPathErrorsNameTheRow() {
        let (model, _) = make()

        #expect(!model.setShortcut(left.id, to: shiftA))
        #expect(model.errorTarget == .row(leftRow))

        #expect(!model.setShortcut(right.id, to: UIFixture.f13))
        #expect(model.errorTarget == .row(rightRow))
        #expect(model.error == SettingsMessages.alreadyUsed(
            model.shortcutText(for: UIFixture.f13), by: model.summary(of: left)))

        #expect(!model.setShortcut(grid.id, to: UIFixture.f13))
        #expect(model.errorTarget == .row(.layout(grid.id)))

        model.beginRecording(area.id)
        model.record(shiftA)
        #expect(model.errorTarget == .row(.layout(area.id)))
        #expect(model.recordingBindingID == nil, "the binding-ID path ends recording on a rejection")
    }

    @Test("the binding-ID path of recording is unchanged")
    func bindingPathUnchanged() {
        let (model, backend) = make()
        model.beginRecording(right.id)
        #expect(model.recordingBindingID == right.id)
        #expect(model.isRecording)

        model.record(hyperF16)

        #expect(model.binding(right.id)?.shortcut == hyperF16)
        #expect(model.recordingBindingID == nil)
        #expect(model.pressesTaken == 1)
        #expect(backend.suspendRequests == [true, false])
        #expect(model.pendingConflict == nil)
    }

    @Test("the error and its target are replaced by a later error and cleared by a reload")
    func errorTargetLifecycle() {
        let (model, backend) = make()
        #expect(!model.setGap(100))
        #expect(!model.setResizeStep(0.9))
        #expect(model.errorTarget == .field(.resizeStep))

        backend.replaceFromOutside(Config(bindings: [left]))

        #expect(model.error == nil)
        #expect(model.errorTarget == nil)
    }
}
