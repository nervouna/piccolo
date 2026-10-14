import Foundation
import Observation
import PiccoloCore

/// What the Settings window shows and edits: the bindings, the settings of the config (resize step,
/// window animation, grid fill order, destination preview), the problems with the config, which
/// binding is selected and which is recording a shortcut, and whether Piccolo launches at login
/// (not part of the config: the system keeps it, see ``LoginItemBackend``).
///
/// The window and the debug control commands call the same methods. Every accepted change is
/// persisted through the ``SettingsBackend`` before it shows: the model never holds a config that
/// is not saved. A rejected change (the model's own rules, or a backend that cannot save) leaves
/// everything as it was and sets ``error``; the next accepted change clears it.
///
/// While a binding is recording a shortcut the backend's global hotkeys are suspended, so that an
/// existing shortcut can be pressed to record it again. Every way recording can end (a key, a
/// cancel, the removal of the binding, a reload that lost it) restores them; whoever owns the
/// window calls ``cancelRecording()`` when the window closes or the app is deactivated.
@MainActor
@Observable
public final class SettingsModel {
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
    /// The problems found when the config was applied, one line each.
    public private(set) var issues: [String]
    /// The binding the editor shows. The list binds to it.
    public var selectedBindingID: UUID?
    /// The tab the window shows. The tab control binds to it, so that whatever sets it (a click, the
    /// debug control channel) changes what the window shows.
    public var tab: SettingsTab = .shortcuts
    /// The binding that is waiting for a key press, if any.
    public private(set) var recordingBindingID: UUID?
    /// Why the last change was rejected, until the next change is accepted.
    public private(set) var error: String?
    /// How many key presses recording has taken (Escape and Delete included). A caller that
    /// posts a key press can tell by it that the press arrived.
    public private(set) var pressesTaken = 0
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

    @ObservationIgnored private let backend: any SettingsBackend
    @ObservationIgnored private let loginItem: any LoginItemBackend
    @ObservationIgnored private let characterForKeyCode: @MainActor (Int) -> String?

    /// - Parameters:
    ///   - backend: Where the config is read from and saved to.
    ///   - loginItem: The system's login item for Piccolo.
    ///   - characterForKeyCode: The character a key produces on the current keyboard layout;
    ///     ``KeyboardLayout`` is the live lookup.
    public init(
        backend: any SettingsBackend,
        loginItem: any LoginItemBackend,
        characterForKeyCode: @escaping @MainActor (Int) -> String? = { KeyboardLayout.character(forKeyCode: $0) }
    ) {
        self.backend = backend
        self.loginItem = loginItem
        self.characterForKeyCode = characterForKeyCode
        loginItemStatus = loginItem.status
        let snapshot = backend.current()
        bindings = snapshot.config.bindings
        resizeStep = snapshot.config.resizeStep
        animation = snapshot.config.animation
        gridFillOrder = snapshot.config.gridFillOrder
        destinationPreview = snapshot.config.destinationPreview
        issues = snapshot.issues
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

    // MARK: Editing

    /// Adds a binding that places the window in the left half and has no shortcut, and selects it.
    /// Answers its ID, or `nil` when it could not be saved.
    @discardableResult
    public func addBinding() -> UUID? {
        let binding = KeyBinding(action: .newBindingDefault)
        var candidate = config
        candidate.bindings.append(binding)
        guard commit(candidate) else { return nil }
        selectedBindingID = binding.id
        return binding.id
    }

    /// Removes a binding. If it was recording, recording ends and the hotkeys come back.
    @discardableResult
    public func removeBinding(_ id: UUID) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else {
            return reject(SettingsMessages.bindingGone)
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
            return reject(SettingsMessages.bindingGone)
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
            return reject(SettingsMessages.bindingGone)
        }
        if let shortcut {
            guard shortcut.isRegistrable else {
                return reject(SettingsMessages.notRegistrable(shortcutText(for: shortcut)))
            }
            if let other = bindings.first(where: { $0.id != id && $0.shortcut == shortcut }) {
                return reject(
                    SettingsMessages.alreadyUsed(shortcutText(for: shortcut), by: summary(of: other)))
            }
        }
        var candidate = config
        candidate.bindings[index].shortcut = shortcut
        return commit(candidate)
    }

    /// Sets the linked-resize step, as a fraction of the screen: more than 0 and at most 0.5.
    @discardableResult
    public func setResizeStep(_ value: Double) -> Bool {
        var candidate = config
        candidate.resizeStep = value
        return commit(candidate)
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

    /// Forgets the errors, for example when the window closes.
    public func clearError() {
        error = nil
        loginItemError = nil
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
    /// animation, grid fill order, destination preview). The config file in use is copied next to itself
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

    // MARK: Recording

    /// Starts recording a shortcut for a binding and suspends the global hotkeys. Recording a
    /// binding that is already recording changes nothing; recording another one moves the
    /// recording there.
    @discardableResult
    public func beginRecording(_ id: UUID) -> Bool {
        guard binding(id) != nil else {
            return reject(SettingsMessages.bindingGone)
        }
        error = nil
        selectedBindingID = id
        recordingBindingID = id
        backend.setShortcutsSuspended(true)
        return true
    }

    /// Ends recording without a change and restores the global hotkeys. Safe to call at any
    /// time, also when nothing is recording.
    public func cancelRecording() {
        recordingBindingID = nil
        backend.setShortcutsSuspended(false)
        // Registering the shortcuts again can turn up problems the system reports only then
        // (a shortcut it refuses), and they were not part of the answer to a save made while
        // the hotkeys were suspended.
        issues = backend.current().issues
    }

    /// Offers a key press to the binding that is recording. Does nothing and answers `false`
    /// when nothing is recording.
    ///
    /// Escape alone cancels, Delete alone clears the shortcut, anything else becomes the
    /// shortcut if the model accepts it. Recording ends in every case: a rejected shortcut shows
    /// its message in ``error``, and the person starts again.
    @discardableResult
    public func record(_ press: Shortcut) -> Bool {
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
        issues = snapshot.issues
        error = nil
        if let recording = recordingBindingID, binding(recording) == nil {
            cancelRecording()
        }
        if let selected = selectedBindingID, binding(selected) == nil {
            selectedBindingID = bindings.first?.id
        } else if selectedBindingID == nil {
            selectedBindingID = bindings.first?.id
        }
    }

    // MARK: Committing

    /// Validates `candidate`, persists it and, only then, makes it the model's state.
    private func commit(_ candidate: Config) -> Bool {
        if candidate == config {
            error = nil
            return true
        }
        do {
            try candidate.validate()
        } catch {
            return reject(SettingsMessages.describe(error))
        }
        let newIssues: [String]
        do {
            newIssues = try backend.save(candidate)
        } catch {
            return reject(Self.message(for: error))
        }
        bindings = candidate.bindings
        resizeStep = candidate.resizeStep
        animation = candidate.animation
        gridFillOrder = candidate.gridFillOrder
        destinationPreview = candidate.destinationPreview
        issues = newIssues
        self.error = nil
        return true
    }

    /// Records the message of a rejected change. Always answers `false`.
    @discardableResult
    private func reject(_ message: String) -> Bool {
        error = message
        return false
    }

    private static func message(for error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return "The change could not be saved: \(text)"
    }
}
