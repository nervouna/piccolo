import Foundation
import Observation
import PiccoloCore

/// What the Settings window shows and edits: the bindings, the settings of the config (resize step,
/// window animation, grid fill order, destination preview), the problems with the config, which
/// binding is selected and which is recording a shortcut, whether Piccolo launches at login
/// (not part of the config: the system keeps it, see ``LoginItemBackend``) and the language of the
/// interface (not part of the config either: macOS keeps it per app, see ``LanguageBackend``).
///
/// The window and the debug control commands call the same methods. Every accepted change is
/// persisted through the ``SettingsBackend`` before it shows: the model never holds a config that
/// is not saved. A rejected change (the model's own rules, or a backend that cannot save) leaves
/// everything as it was and sets ``error``; the next accepted change clears it.
///
/// While a binding or a row of the keymap is recording a shortcut the backend's global hotkeys are
/// suspended, so that an existing shortcut can be pressed to record it again. Every way recording can
/// end (a key, a cancel, the removal of the binding, a reload that lost it) restores them, except a
/// shortcut that cannot be a global one, after which a row goes on recording; whoever owns the window
/// calls ``cancelRecording()`` when the window closes or the app is deactivated.
///
/// The keymap (``keymap``) is the row-centred view of the bindings that the Shortcuts tab shows; the
/// methods that take a ``KeymapRowID`` are in `SettingsModel+Keymap.swift`.
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
    /// The binding the editor shows. The list binds to it.
    public var selectedBindingID: UUID?
    /// The tab the window shows. The tab control binds to it, so that whatever sets it (a click, the
    /// debug control channel) changes what the window shows.
    public var tab: SettingsTab = .shortcuts
    /// The binding that is waiting for a key press, if any. Recording by binding is the way of the list
    /// view; the keymap records by row (``recordingRow``). Only one of the two is ever set.
    public internal(set) var recordingBindingID: UUID?
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
        selectedBindingID = snapshot.config.bindings.first?.id
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

    /// The sections of the list under the current search, in the language of the running app.
    public var sections: [BindingSection] {
        BindingSections.make(bindings: bindings, query: search, characterForKeyCode: characterForKeyCode)
    }

    /// Whether the list shows the binding under the current search.
    public func isVisible(_ id: UUID) -> Bool {
        sections.contains { section in section.bindings.contains { $0.id == id } }
    }

    /// The bindings with a shortcut that is not active. While a shortcut is being recorded every global
    /// hotkey is suspended, which is no fault of the bindings, so none is marked then.
    public var inactiveBindingIDs: Set<UUID> {
        isRecording ? [] : reportedInactiveBindingIDs
    }

    /// Whether a row or a binding is waiting for a key press.
    public var isRecording: Bool {
        recordingRow != nil || recordingBindingID != nil
    }

    /// The sections of the keymap under the current search, in the language of the running app.
    public var keymap: [KeymapGroup] {
        Keymap.make(bindings: bindings, query: search, characterForKeyCode: characterForKeyCode)
    }

    // MARK: Searching

    /// Sets the search query. The selection stays when the selected binding is still shown;
    /// otherwise it moves to the first shown binding, or to none when nothing is shown.
    public func setSearch(_ text: String) {
        search = text
        let shown = sections.flatMap(\.bindings)
        if let selected = selectedBindingID, shown.contains(where: { $0.id == selected }) {
            return
        }
        selectedBindingID = shown.first?.id
    }

    // MARK: Editing

    /// Adds a binding that places the window in the left half and has no shortcut, and selects it.
    /// Answers its ID, or `nil` when it could not be saved.
    @discardableResult
    public func addBinding() -> UUID? {
        let binding = KeyBinding(action: .newBindingDefault)
        var candidate = config
        candidate.bindings.append(binding)
        guard commit(candidate) else { return nil }
        // A search that would hide the new binding is cleared.
        if !isVisible(binding.id) {
            search = ""
        }
        selectedBindingID = binding.id
        return binding.id
    }

    /// Removes a binding. If it was recording, recording ends and the hotkeys come back.
    @discardableResult
    public func removeBinding(_ id: UUID) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else {
            return reject(SettingsMessages.bindingGone())
        }
        var candidate = config
        candidate.bindings.remove(at: index)
        guard commit(candidate) else { return false }
        if recordingBindingID == id {
            cancelRecording()
        }
        if selectedBindingID == id {
            // The binding that took its place, or the one before when it was the last.
            selectedBindingID = bindings.isEmpty ? nil : bindings[min(index, bindings.count - 1)].id
        }
        return true
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

    /// Sets the shortcut of a binding, or clears it with `nil`.
    ///
    /// A shortcut is rejected when it cannot be registered as a global hotkey (see
    /// `Shortcut.isRegistrable`) and when another binding already has it.
    @discardableResult
    public func setShortcut(_ id: UUID, to shortcut: Shortcut?) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else {
            return reject(SettingsMessages.bindingGone())
        }
        let target = SettingsErrorTarget.row(KeymapRowID(bindings[index]))
        if let shortcut {
            guard shortcut.isRegistrable else {
                return reject(SettingsMessages.notRegistrable(shortcutText(for: shortcut)), target: target)
            }
            if let other = bindings.first(where: { $0.id != id && $0.shortcut == shortcut }) {
                return reject(
                    SettingsMessages.alreadyUsed(shortcutText(for: shortcut), by: summary(of: other)),
                    target: target)
            }
        }
        var candidate = config
        candidate.bindings[index].shortcut = shortcut
        return commit(candidate, rejection: target)
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
    /// recording ends, since its binding is gone and the hotkeys come back with the new bindings, and the
    /// list selects the first binding.
    ///
    /// This does not ask: the window asks first (see ``askToRestoreDefaults()``). Answers whether the
    /// bindings were replaced; when they were not, ``error`` says why and nothing changed.
    @discardableResult
    public func restoreDefaultShortcuts() -> Bool {
        isConfirmingRestore = false
        backupName = nil
        var candidate = config
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
        reload()
        // A row of the keymap outlives the bindings, so its recording would go on without this.
        if isRecording {
            cancelRecording()
        }
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

    /// Starts recording a shortcut for a binding and suspends the global hotkeys. Recording a
    /// binding that is already recording changes nothing; recording another one moves the
    /// recording there.
    @discardableResult
    public func beginRecording(_ id: UUID) -> Bool {
        guard binding(id) != nil else {
            return reject(SettingsMessages.bindingGone())
        }
        resetError()
        pendingConflict = nil
        selectedBindingID = id
        recordingRow = nil
        recordingBindingID = id
        backend.setShortcutsSuspended(true)
        return true
    }

    /// Ends recording without a change and restores the global hotkeys. Safe to call at any
    /// time, also when nothing is recording.
    public func cancelRecording() {
        recordingBindingID = nil
        recordingRow = nil
        backend.setShortcutsSuspended(false)
        // Registering the shortcuts again can turn up problems the system reports only then
        // (a shortcut it refuses), and they were not part of the answer to a save made while
        // the hotkeys were suspended.
        let snapshot = backend.current()
        issues = snapshot.issues
        reportedInactiveBindingIDs = snapshot.inactiveBindingIDs
    }

    /// Offers a key press to the row or binding that is recording. Does nothing and answers `false`
    /// when nothing is recording.
    ///
    /// For a binding: Escape alone cancels, Delete alone clears the shortcut, anything else becomes
    /// the shortcut if the model accepts it. Recording ends in every case: a rejected shortcut shows
    /// its message in ``error``, and the person starts again. For a row, see
    /// ``beginRecording(_:)-(KeymapRowID)``.
    @discardableResult
    public func record(_ press: Shortcut) -> Bool {
        if let row = recordingRow {
            recordForRow(row, press)
            return true
        }
        guard let id = recordingBindingID else { return false }
        pressesTaken += 1
        if press.modifiers.isEmpty && press.keyCode == ShortcutText.escapeKeyCode {
            cancelRecording()
        } else if press.modifiers.isEmpty && ShortcutText.deleteKeyCodes.contains(press.keyCode) {
            setShortcut(id, to: nil)
            cancelRecording()
        } else {
            setShortcut(id, to: press)
            cancelRecording()
        }
        return true
    }

    // MARK: External changes

    /// Takes the config in effect from the backend again, because it was replaced under the
    /// model (a reload from the menu, another file loaded). A recording of a binding that is
    /// gone ends.
    public func reload() {
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
        if let selected = selectedBindingID, binding(selected) == nil {
            selectedBindingID = bindings.first?.id
        } else if selectedBindingID == nil {
            selectedBindingID = bindings.first?.id
        }
    }

    // MARK: Committing

    /// Validates `candidate`, persists it and, only then, makes it the model's state. A change that is
    /// accepted drops a pending conflict; one that is rejected shows its message at `rejection`.
    func commit(_ candidate: Config, rejection: SettingsErrorTarget = .window) -> Bool {
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

    /// Ends the recording of a binding that is no longer in the config, or of a row of a layout that is not.
    /// The built-in rows are always there.
    private func endRecordingIfTargetIsGone() {
        if let recording = recordingBindingID, binding(recording) == nil {
            cancelRecording()
        } else if let row = recordingRow, Keymap.row(row, in: bindings) == nil {
            cancelRecording()
        }
    }

    private static func message(for error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return SettingsMessages.notSaved(text)
    }
}
