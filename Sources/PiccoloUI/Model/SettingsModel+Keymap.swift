import Foundation
import PiccoloCore

/// The shortcut a row was recorded with that another binding already has, waiting for the person to
/// choose between replacing it and keeping things as they are.
public struct ShortcutConflict: Equatable, Sendable {
    /// The row that was recorded.
    public let row: KeymapRowID
    public let shortcut: Shortcut
    /// The binding that has the shortcut.
    public let ownerBindingID: UUID
}

/// A field of the General tab that an error is about.
public enum SettingsField: String, Sendable {
    case gap
    case resizeStep
}

/// Where the window shows the last error: under a row of the keymap, under a field, or for the window as
/// a whole.
public enum SettingsErrorTarget: Equatable, Sendable {
    case row(KeymapRowID)
    case field(SettingsField)
    case window
}

/// A request to open the sheet that edits a grid or a custom area.
public enum LayoutEditorRequest: Equatable, Sendable {
    /// A new grid (``KeymapSection/grids``) or custom area (``KeymapSection/customAreas``).
    case new(KeymapSection)
    /// The layout of this binding.
    case edit(UUID)
}

// The keymap's side of the model: recording by row, conflicts, and the grid and custom area rows. The
// stored state is declared in `SettingsModel`, which the observation macro needs.
extension SettingsModel {
    // MARK: Recording by row

    /// Starts recording a shortcut for a row of the keymap and suspends the global hotkeys. A recording
    /// that is going on, of a row or of a binding, moves to this row. Clears the error and drops a pending
    /// conflict. A row that does not exist is rejected.
    @discardableResult
    public func beginRecording(_ row: KeymapRowID) -> Bool {
        guard Keymap.row(row, in: bindings) != nil else {
            return reject(SettingsMessages.bindingGone())
        }
        resetError()
        pendingConflict = nil
        recordingBindingID = nil
        recordingRow = row
        backend.setShortcutsSuspended(true)
        return true
    }

    /// Takes away the shortcut of a row: a built-in row loses its first binding, which is removed from the
    /// config; a layout row keeps its binding and loses its shortcut. A row without a shortcut to take away
    /// is no change. Answers whether the change was accepted; a rejection names the row.
    @discardableResult
    public func clearShortcut(_ row: KeymapRowID) -> Bool {
        guard let found = Keymap.row(row, in: bindings) else {
            return reject(SettingsMessages.bindingGone())
        }
        var candidate = config
        if let primary = found.primaryBinding {
            if found.isEditable {
                if let index = candidate.bindings.firstIndex(where: { $0.id == primary.id }) {
                    candidate.bindings[index].shortcut = nil
                }
            } else {
                candidate.bindings.removeAll { $0.id == primary.id }
            }
        }
        return commit(candidate, rejection: .row(row))
    }

    /// Takes a key press for the row that is recording. Escape alone cancels, Delete alone clears; a shortcut
    /// that cannot be a global one is rejected and recording goes on; one that another binding has becomes a
    /// pending conflict and ends the recording; the row's own shortcut ends it with no change; anything else
    /// is given to the row.
    func recordForRow(_ row: KeymapRowID, _ press: Shortcut) {
        pressesTaken += 1
        guard let found = Keymap.row(row, in: bindings) else {
            cancelRecording()
            return
        }
        if press.modifiers.isEmpty && press.keyCode == ShortcutText.escapeKeyCode {
            cancelRecording()
            // The reason shown under the row for an earlier press goes with the recording.
            if errorTarget == .row(row) {
                resetError()
            }
            return
        }
        if press.modifiers.isEmpty && ShortcutText.deleteKeyCodes.contains(press.keyCode) {
            clearShortcut(row)
            cancelRecording()
            return
        }
        guard press.isRegistrable else {
            reject(SettingsMessages.notRegistrable(shortcutText(for: press)), target: .row(row))
            return
        }
        resetError()
        if let owner = bindings.first(where: { $0.id != found.primaryBinding?.id && $0.shortcut == press }) {
            cancelRecording()
            pendingConflict = ShortcutConflict(row: row, shortcut: press, ownerBindingID: owner.id)
            return
        }
        if found.shortcut != press {
            _ = commit(config(giving: press, to: found), rejection: .row(row))
        }
        cancelRecording()
    }

    /// Settles the pending conflict. `replace: true` takes the shortcut from the binding that has it (it is
    /// removed when its action is built in; a layout keeps its binding and loses the shortcut) and gives it
    /// to the row, in one change. `replace: false` drops the conflict. Answers `false` when no conflict is
    /// pending, or when the change is rejected, in which case the conflict stays.
    @discardableResult
    public func resolveConflict(replace: Bool) -> Bool {
        guard let conflict = pendingConflict else { return false }
        guard replace else {
            pendingConflict = nil
            return true
        }
        guard let row = Keymap.row(conflict.row, in: bindings),
            let owner = binding(conflict.ownerBindingID), owner.shortcut == conflict.shortcut
        else {
            pendingConflict = nil
            return reject(SettingsMessages.bindingGone(), target: .row(conflict.row))
        }
        var candidate = config(giving: conflict.shortcut, to: row)
        if owner.action.isBuiltIn {
            candidate.bindings.removeAll { $0.id == owner.id }
        } else if let index = candidate.bindings.firstIndex(where: { $0.id == owner.id }) {
            candidate.bindings[index].shortcut = nil
        }
        return commit(candidate, rejection: .row(conflict.row))
    }

    /// The config with `shortcut` on the row's first binding, or on a new binding of the row's action when it has none.
    private func config(giving shortcut: Shortcut, to row: KeymapRow) -> Config {
        var candidate = config
        if let primary = row.primaryBinding,
            let index = candidate.bindings.firstIndex(where: { $0.id == primary.id })
        {
            candidate.bindings[index].shortcut = shortcut
        } else {
            candidate.bindings.append(KeyBinding(action: row.action, shortcut: shortcut))
        }
        return candidate
    }

    // MARK: Layout rows

    /// The first thing wrong with `action` as a grid or a custom area, or `nil`: the config's own rules,
    /// then that no other binding of the same section has an equal action. `id` is the binding being edited.
    public func layoutProblem(_ action: Action, editing id: UUID?) -> LayoutProblem? {
        LayoutProblems.first(for: action, editing: id, in: bindings)
    }

    /// Adds a grid or a custom area without a shortcut and starts recording one for its row. Answers its
    /// binding's ID, or `nil` when the action is neither, has a problem (``layoutProblem(_:editing:)``) or
    /// cannot be saved; the error says why and nothing is saved.
    @discardableResult
    public func addLayout(_ action: Action) -> UUID? {
        let section = KeymapSection(of: action)
        guard section == .grids || section == .customAreas else {
            reject(SettingsMessages.notALayout())
            return nil
        }
        if let problem = layoutProblem(action, editing: nil) {
            reject(problem.message)
            return nil
        }
        let binding = KeyBinding(action: action)
        var candidate = config
        candidate.bindings.append(binding)
        guard commit(candidate) else { return nil }
        beginRecording(.layout(binding.id))
        return binding.id
    }

    /// Replaces the action of a grid or a custom area with another of the same section, keeping its binding,
    /// its place and its shortcut. Rejected, with nothing saved, when the binding is not a layout, the action
    /// is of the other section, or it has a problem.
    @discardableResult
    public func updateLayout(_ id: UUID, to action: Action) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else {
            return reject(SettingsMessages.bindingGone())
        }
        let current = bindings[index].action
        guard !current.isBuiltIn else {
            return reject(SettingsMessages.notALayout())
        }
        guard KeymapSection(of: action) == KeymapSection(of: current) else {
            return reject(SettingsMessages.layoutKindFixed())
        }
        if let problem = layoutProblem(action, editing: id) {
            return reject(problem.message)
        }
        var candidate = config
        candidate.bindings[index].action = action
        return commit(candidate)
    }

    // MARK: The sheet for a layout

    /// Asks for the sheet that edits a grid or a custom area (the window shows it for ``layoutEditor``). A
    /// recording ends and a pending conflict is dropped. Rejected when the request is for a section that has
    /// no sheet, or for a binding that is not a layout.
    @discardableResult
    public func editLayout(_ request: LayoutEditorRequest) -> Bool {
        switch request {
        case .new(let section):
            guard section == .grids || section == .customAreas else {
                return reject(SettingsMessages.notALayout())
            }
        case .edit(let id):
            guard let binding = binding(id) else {
                return reject(SettingsMessages.bindingGone())
            }
            guard !binding.action.isBuiltIn else {
                return reject(SettingsMessages.notALayout())
            }
        }
        if isRecording {
            cancelRecording()
        }
        pendingConflict = nil
        layoutEditor = request
        return true
    }

    /// Withdraws the request for the sheet, for example when the sheet closes or the window does.
    public func dismissLayoutEditor() {
        layoutEditor = nil
    }
}
