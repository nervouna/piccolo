import Foundation
import Observation
import PiccoloCore

/// What the Settings window shows and edits: the bindings, the settings of the config (resize step,
/// window animation, grid fill order, destination preview), the problems with the config, which
/// row of the keymap is recording a shortcut, whether Piccolo launches at login
/// (not part of the config: the system keeps it, see ``LoginItemBackend``) and the language of the
/// interface (not part of the config either: macOS keeps it per app, see ``LanguageBackend``).
///
/// The window and the debug control commands call the same methods. Every accepted change is
/// persisted through the ``SettingsBackend`` before it shows: the model never holds a config that
/// is not saved. A rejected change (the model's own rules, or a backend that cannot save) leaves
/// everything as it was and sets ``error``; the next accepted change clears it.
///
/// While a row of the keymap is recording a shortcut the backend's global hotkeys are suspended, so that
/// an existing shortcut can be pressed to record it again. Every way recording can end (a key, a
/// cancel, the removal of the binding, a reload that lost it) restores them, except a shortcut that
/// cannot be a global one, after which the row goes on recording; whoever owns the window calls
/// ``cancelRecording()`` when the window closes or the app is deactivated.
///
/// The keymap (``keymap``) is the row-centred view of the bindings that the Shortcuts tab shows; the
/// methods that take a ``KeymapRowID`` are in `SettingsModel+Keymap.swift`.
///
/// Every accepted change to the config is a step of the history: ``undo()`` and ``redo()`` walk it, up to
/// ``historyLimit`` steps back. Restoring the default shortcuts is one step, and so is a conflict that was
/// replaced. A config replaced from outside (``reload()``) clears the history. Whether Piccolo launches at
/// login and the language of the interface are not part of the config and not part of the history.
@MainActor
@Observable
public final class SettingsModel {
    /// The language the running app shows its texts in: one of the eight, never ``AppLanguage/system``.
    /// It does not change until Piccolo is started again.
    public let effectiveLanguage: AppLanguage
    /// The bindings in the order the config keeps them.
    public private(set) var bindings: [KeyBinding]
    /// Fraction of the screen a linked resize moves a divider by, as in the config file.
    public private(set) var resizeStep: Double
    /// How long a window takes to move to its new place, as in the config file.
    public private(set) var animation: WindowAnimation
    /// Where the windows of a grid go when there are fewer windows than cells, as in the config file.
    public private(set) var gridFillOrder: GridFillOrder
    /// Whether holding a shortcut shows where its windows will go before they move, as in the config file.
    public private(set) var destinationPreview: Bool
    /// The window gap in points (0 to 64).
    public private(set) var gap: Int
    /// The problems found when the config was applied, one line each.
    public private(set) var issues: [String]
    /// The bindings whose shortcut is not active, as the backend last reported them. Read
    /// ``inactiveBindingIDs`` instead: it is empty while a shortcut is being recorded.
    private var reportedInactiveBindingIDs: Set<UUID>
    /// What the search field holds. Only the Shortcuts tab uses it; it is saved nowhere. Change it with
    /// ``setSearch(_:)``.
    public private(set) var search = ""
    /// The tab the window shows. The tab control binds to it, so that whatever sets it (a click, the
    /// debug control channel) changes what the window shows.
    public var tab: SettingsTab = .shortcuts
    /// The row of the keymap that is waiting for a key press, if any.
    public internal(set) var recordingRow: KeymapRowID?
    /// The shortcut a row was recorded with that another binding already has, until it is replaced
    /// (``resolveConflict(replace:)``) or dropped. Beginning a recording, any accepted change and a reload
    /// drop it.
    public internal(set) var pendingConflict: ShortcutConflict?
    /// The request to open the sheet for a grid or a custom area, until it is dismissed.
    public internal(set) var layoutEditor: LayoutEditorRequest?
    /// Why the last change was rejected, until the next change is accepted.
    public private(set) var error: String?
    /// Where ``error`` shows: under a row, under a field, or in the window. `nil` exactly when ``error`` is.
    public private(set) var errorTarget: SettingsErrorTarget?
    /// How many key presses recording has taken (Escape and Delete included). A caller that
    /// posts a key press can tell by it that the press arrived.
    public internal(set) var pressesTaken = 0
    /// What the system last said about starting Piccolo at login. ``refreshLoginItem()`` reads it
    /// again; ``setLaunchAtLogin(_:)`` does after every change.
    public private(set) var loginItemStatus: LoginItemStatus
    /// Why the last change of the login item failed, until the next one succeeds. Separate from
    /// ``error``: it is shown next to the switch it belongs to.
    public private(set) var loginItemError: String?
    /// Whether the confirmation for restoring the default shortcuts is showing. The alert binds to it.
    public var isConfirmingRestore = false
    /// The file name of the copy the last successful restore kept next to the config file, or `nil`
    /// when it kept none (there was no file).
    public private(set) var backupName: String?
    /// The language chosen for the interface, or ``AppLanguage/system``. macOS applies it the next time
    /// Piccolo starts; ``effectiveLanguage`` is the one the running app shows.
    public private(set) var language: AppLanguage
    /// Why the last restart could not be arranged, until the next one can. Shown next to the button.
    public private(set) var restartError: String?
    /// The configs the accepted changes replaced, the oldest first: ``undo()`` applies the last one.
    private var undoSteps: [Config] = []
    /// The configs the undone changes replaced, the last undone first at the end: ``redo()`` applies the last one.
    private var redoSteps: [Config] = []

    /// How many changes ``undo()`` can take back at most. The oldest are forgotten.
    public static let historyLimit = 100

    @ObservationIgnored let backend: any SettingsBackend
    @ObservationIgnored private let loginItem: any LoginItemBackend
    @ObservationIgnored private let languageBackend: any LanguageBackend
    @ObservationIgnored private let characterForKeyCode: @MainActor (Int) -> String?

    /// - Parameters:
    ///   - backend: Where the config is read from and saved to.
    ///   - loginItem: The system's login item for Piccolo.
    ///   - language: Where the language of the interface is stored, and how Piccolo restarts.
    ///   - characterForKeyCode: The character a key produces on the current keyboard layout;
    ///     ``KeyboardLayout`` is the live lookup.
    public init(
        backend: any SettingsBackend,
        loginItem: any LoginItemBackend,
        language: any LanguageBackend,
        characterForKeyCode: @escaping @MainActor (Int) -> String? = { KeyboardLayout.character(forKeyCode: $0) }
    ) {
        self.backend = backend
        self.loginItem = loginItem
        self.languageBackend = language
        self.characterForKeyCode = characterForKeyCode
        loginItemStatus = loginItem.status
        self.language = language.storedLanguage
        effectiveLanguage = language.runningLanguage
        let snapshot = backend.current()
        bindings = snapshot.config.bindings
        resizeStep = snapshot.config.resizeStep
        animation = snapshot.config.animation
        gridFillOrder = snapshot.config.gridFillOrder
        destinationPreview = snapshot.config.destinationPreview
        gap = snapshot.config.gap
        issues = snapshot.issues
        reportedInactiveBindingIDs = snapshot.inactiveBindingIDs
        backend.onExternalChange = { [weak self] in
            self?.reload()
        }
    }

    // MARK: Reading

    /// The config the model holds, which is the one that was saved last.
    public var config: Config {
        Config(
            resizeStep: resizeStep,
            animation: animation,
            gridFillOrder: gridFillOrder,
            destinationPreview: destinationPreview,
            gap: gap,
            bindings: bindings)
    }

    public func binding(_ id: UUID) -> KeyBinding? {
        bindings.first { $0.id == id }
    }

    /// The summary line of a binding's action, for example "Left Half".
    public func summary(of binding: KeyBinding) -> String {
        ActionSummary.text(for: binding.action)
    }

    /// The text of a shortcut on the current keyboard layout, for example "⌃⌥⇧⌘F14".
    public func shortcutText(for shortcut: Shortcut) -> String {
        ShortcutText.string(for: shortcut, character: characterForKeyCode)
    }

    /// The bindings with a shortcut that is not active. While a shortcut is being recorded every global
    /// hotkey is suspended, which is no fault of the bindings, so none is marked then.
    public var inactiveBindingIDs: Set<UUID> {
        isRecording ? [] : reportedInactiveBindingIDs
    }

    /// Whether a row is waiting for a key press.
    public var isRecording: Bool {
        recordingRow != nil
    }

    /// The sections of the keymap under the current search, in the language of the running app.
    public var keymap: [KeymapGroup] {
        Keymap.make(bindings: bindings, query: search, characterForKeyCode: characterForKeyCode)
    }

    // MARK: Searching

    /// Sets the search query, which filters ``keymap``.
    public func setSearch(_ text: String) {
        search = text
    }

    // MARK: Editing

    /// Removes a binding. If its row was recording, recording ends and the hotkeys come back.
    @discardableResult
    public func removeBinding(_ id: UUID) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else {
            return reject(SettingsMessages.bindingGone())
        }
        var candidate = config
        candidate.bindings.remove(at: index)
        return commit(candidate)
    }

    /// Replaces what a binding does.
    @discardableResult
    public func updateAction(_ id: UUID, to action: Action) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else {
            return reject(SettingsMessages.bindingGone())
        }
        var candidate = config
        candidate.bindings[index].action = action
        return commit(candidate)
    }

    /// Sets the linked-resize step, as a fraction of the screen: more than 0 and at most 0.5.
    @discardableResult
    public func setResizeStep(_ value: Double) -> Bool {
        var candidate = config
        candidate.resizeStep = value
        return commit(candidate, rejection: .field(.resizeStep))
    }

    /// Sets how long a window takes to move to its new place.
    @discardableResult
    public func setAnimation(_ value: WindowAnimation) -> Bool {
        var candidate = config
        candidate.animation = value
        return commit(candidate)
    }

    /// Sets where the windows of a grid go when there are fewer windows than cells.
    @discardableResult
    public func setGridFillOrder(_ value: GridFillOrder) -> Bool {
        var candidate = config
        candidate.gridFillOrder = value
        return commit(candidate)
    }

    /// Sets whether holding a shortcut shows where its windows will go before they move.
    @discardableResult
    public func setDestinationPreview(_ value: Bool) -> Bool {
        var candidate = config
        candidate.destinationPreview = value
        return commit(candidate)
    }

    /// Sets the window gap, in points: a whole number from 0 to 64.
    @discardableResult
    public func setGap(_ value: Int) -> Bool {
        var candidate = config
        candidate.gap = value
        return commit(candidate, rejection: .field(.gap))
    }

    /// Forgets the errors, for example when the window closes.
    public func clearError() {
        resetError()
        loginItemError = nil
        restartError = nil
    }

    // MARK: Restoring the defaults

    /// Asks for confirmation before the bindings are replaced by the default shortcuts.
    public func askToRestoreDefaults() {
        isConfirmingRestore = true
    }

    /// Dismisses the confirmation without a change.
    public func cancelRestoreDefaults() {
        isConfirmingRestore = false
    }

    /// Replaces every binding with `Config.defaultShortcuts` and keeps the settings (resize step, window
    /// animation, grid fill order, destination preview, window gap). The config file in use is copied next to itself
    /// first, when there is one (see ``SettingsBackend``), so the current shortcuts can be recovered. A
    /// recording ends, since its binding is gone and the hotkeys come back with the new bindings.
    ///
    /// This does not ask: the window asks first (see ``askToRestoreDefaults()``). Answers whether the
    /// bindings were replaced; when they were not, ``error`` says why and nothing changed.
    @discardableResult
    public func restoreDefaultShortcuts() -> Bool {
        isConfirmingRestore = false
        backupName = nil
        let before = config
        var candidate = before
        candidate.bindings = Config.defaultShortcuts.bindings
        do {
            try candidate.validate()
        } catch {
            return reject(SettingsMessages.describe(error))
        }
        do {
            backupName = try backend.backUpAndReplace(with: candidate.bindings)
        } catch {
            return reject(Self.message(for: error))
        }
        takeConfigFromBackend()
        // A row of the keymap outlives the bindings, so its recording would go on without this.
        if isRecording {
            cancelRecording()
        }
        recordStep(replacing: before)
        return true
    }

    // MARK: Launch at login

    /// Whether the "Launch at login" switch is on: Piccolo is a login item, also while the system
    /// waits for the user to allow it (``LoginItemStatus/requiresApproval``), so that the switch
    /// can still be turned off.
    public var launchesAtLogin: Bool {
        loginItemStatus.isRegistered
    }

    /// Reads the login item's status from the system again, for example when the tab appears or
    /// the app is activated: the user can change it in System Settings at any time.
    public func refreshLoginItem() {
        loginItemStatus = loginItem.status
    }

    /// Registers (`true`) or unregisters (`false`) Piccolo as a login item and reads the status
    /// back, whatever came of it. Answers whether the system accepted; on a refusal
    /// ``loginItemError`` says why and the status is the one the system reports, so the switch
    /// is back where it was.
    @discardableResult
    public func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        defer { loginItemStatus = loginItem.status }
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            loginItemError = SettingsMessages.loginItemFailed(enabling: enabled, reason: error.message)
            return false
        }
        loginItemError = nil
        return true
    }

    /// Opens Login Items in System Settings.
    public func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    // MARK: Language

    /// Whether the chosen language differs from the one the running app shows, so that a restart
    /// is needed to see the choice. ``AppLanguage/system`` is the language the system's list gives
    /// now (``LanguageBackend/systemLanguage``): on a Mac set to Simplified Chinese, choosing System
    /// default while the app runs in Simplified Chinese needs no restart.
    public var restartRequired: Bool {
        let chosen = language == .system ? languageBackend.systemLanguage : language
        return chosen != effectiveLanguage
    }

    /// Chooses the language of the interface and stores it for the next launch. The running app keeps
    /// its language: ``restartRequired`` says whether it differs, and ``restartNow()`` applies it.
    public func setLanguage(_ language: AppLanguage) {
        languageBackend.store(language)
        self.language = languageBackend.storedLanguage
        restartError = nil
    }

    /// Reads the stored choice again, for example when the window opens or the app is activated: the
    /// user can give Piccolo a language in System Settings, and a script can write the defaults.
    public func refreshLanguage() {
        language = languageBackend.storedLanguage
    }

    /// Quits Piccolo and starts it again, so that the stored language applies. Does not return when it
    /// works, because the app quits. Answers `false` when the restart could not be arranged;
    /// ``restartError`` says why and the app keeps running.
    @discardableResult
    public func restartNow() -> Bool {
        do {
            try languageBackend.restart()
        } catch {
            restartError = SettingsMessages.restartFailed(error.message)
            return false
        }
        restartError = nil
        return true
    }

    // MARK: Recording

    /// Ends recording without a change and restores the global hotkeys. Safe to call at any
    /// time, also when nothing is recording.
    public func cancelRecording() {
        recordingRow = nil
        backend.setShortcutsSuspended(false)
        // Registering the shortcuts again can turn up problems the system reports only then
        // (a shortcut it refuses), and they were not part of the answer to a save made while
        // the hotkeys were suspended.
        let snapshot = backend.current()
        issues = snapshot.issues
        reportedInactiveBindingIDs = snapshot.inactiveBindingIDs
    }

    /// Offers a key press to the row that is recording. Does nothing and answers `false` when nothing
    /// is recording. What a press does is described at `recordForRow(_:_:)`.
    @discardableResult
    public func record(_ press: Shortcut) -> Bool {
        guard let row = recordingRow else { return false }
        recordForRow(row, press)
        return true
    }

    // MARK: External changes

    /// Takes the config in effect from the backend again, because it was replaced under the
    /// model (a reload from the menu, another file loaded). A recording of a row whose binding is
    /// gone ends, and so does a request for the sheet of a binding that is gone. The history of changes is
    /// cleared: the configs in it belong to a file that is no longer the one in effect.
    public func reload() {
        takeConfigFromBackend()
        undoSteps.removeAll()
        redoSteps.removeAll()
    }

    /// Makes the backend's config the model's, as ``reload()`` does but with the history left alone.
    private func takeConfigFromBackend() {
        let snapshot = backend.current()
        bindings = snapshot.config.bindings
        resizeStep = snapshot.config.resizeStep
        animation = snapshot.config.animation
        gridFillOrder = snapshot.config.gridFillOrder
        destinationPreview = snapshot.config.destinationPreview
        gap = snapshot.config.gap
        issues = snapshot.issues
        reportedInactiveBindingIDs = snapshot.inactiveBindingIDs
        resetError()
        pendingConflict = nil
        endRecordingIfTargetIsGone()
        if case .edit(let id) = layoutEditor, binding(id) == nil {
            layoutEditor = nil
        }
    }

    // MARK: Committing

    /// Validates `candidate`, persists it and, only then, makes it the model's state, as one step of the
    /// history. A change that is accepted drops a pending conflict; one that is rejected shows its message
    /// at `rejection`. A candidate equal to the config in effect is accepted and is no step.
    func commit(_ candidate: Config, rejection: SettingsErrorTarget = .window) -> Bool {
        let before = config
        guard apply(candidate, rejection: rejection) else { return false }
        recordStep(replacing: before)
        return true
    }

    /// The part of ``commit(_:rejection:)`` that undo and redo share: validates `candidate`, persists it
    /// and makes it the model's state, leaving the history to the caller.
    private func apply(_ candidate: Config, rejection: SettingsErrorTarget) -> Bool {
        if candidate == config {
            resetError()
            pendingConflict = nil
            return true
        }
        do {
            try candidate.validate()
        } catch {
            return reject(SettingsMessages.describe(error), target: rejection)
        }
        let newIssues: [String]
        do {
            newIssues = try backend.save(candidate)
        } catch {
            return reject(Self.message(for: error), target: rejection)
        }
        bindings = candidate.bindings
        resizeStep = candidate.resizeStep
        animation = candidate.animation
        gridFillOrder = candidate.gridFillOrder
        destinationPreview = candidate.destinationPreview
        gap = candidate.gap
        issues = newIssues
        reportedInactiveBindingIDs = backend.current().inactiveBindingIDs
        resetError()
        pendingConflict = nil
        endRecordingIfTargetIsGone()
        return true
    }

    // MARK: Undo and redo

    /// Whether ``undo()`` has a change to take back.
    public var canUndo: Bool {
        !undoSteps.isEmpty
    }

    /// Whether ``redo()`` has an undone change to apply again.
    public var canRedo: Bool {
        !redoSteps.isEmpty
    }

    /// Takes back the last change made to the config: the config it replaced is validated and saved as any
    /// other change is. A recording ends and a pending conflict is dropped. Answers whether a change was taken
    /// back. When there is nothing to take back it does nothing at all; when the backend cannot save, ``error``
    /// says why (at the window), and nothing changes: not the config, the history, a recording or a conflict.
    @discardableResult
    public func undo() -> Bool {
        guard let target = undoSteps.last else { return false }
        let current = config
        guard travel(to: target) else { return false }
        undoSteps.removeLast()
        redoSteps.append(current)
        return true
    }

    /// Applies the change that ``undo()`` took back last, in the same way.
    @discardableResult
    public func redo() -> Bool {
        guard let target = redoSteps.last else { return false }
        let current = config
        guard travel(to: target) else { return false }
        redoSteps.removeLast()
        undoSteps.append(current)
        return true
    }

    /// Makes `target` the config through the usual validate-and-save path, then ends what the config
    /// replaced may have left behind: a recording, and the request for the sheet of a layout that is gone.
    private func travel(to target: Config) -> Bool {
        guard apply(target, rejection: .window) else { return false }
        if isRecording {
            cancelRecording()
        }
        if case .edit(let id) = layoutEditor, binding(id) == nil {
            layoutEditor = nil
        }
        return true
    }

    /// Adds the config that the change just made replaced to the history, forgetting the oldest steps beyond
    /// ``historyLimit`` and the steps that could have been redone. No step when nothing changed.
    private func recordStep(replacing before: Config) {
        guard config != before else { return }
        undoSteps.append(before)
        if undoSteps.count > Self.historyLimit {
            undoSteps.removeFirst(undoSteps.count - Self.historyLimit)
        }
        redoSteps.removeAll()
    }

    /// Records the message of a rejected change and where it shows. Always answers `false`.
    @discardableResult
    func reject(_ message: String, target: SettingsErrorTarget = .window) -> Bool {
        error = message
        errorTarget = target
        return false
    }

    /// Forgets the error and its place.
    func resetError() {
        error = nil
        errorTarget = nil
    }

    /// Ends the recording of a row of a layout whose binding is no longer in the config. The built-in rows
    /// are always there.
    private func endRecordingIfTargetIsGone() {
        if let row = recordingRow, Keymap.row(row, in: bindings) == nil {
            cancelRecording()
        }
    }

    private static func message(for error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return SettingsMessages.notSaved(text)
    }
}
