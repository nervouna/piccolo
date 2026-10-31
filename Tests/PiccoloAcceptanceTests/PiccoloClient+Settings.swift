import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore

/// What `settings.state` and the other `settings.*` commands answer with.
struct SettingsState: Decodable, Equatable {
    struct Binding: Decodable, Equatable {
        var id: UUID
        var action: Action
        var summary: String
        var shortcut: Shortcut?
        var shortcutText: String?
        /// The kind's name in the config file: `placeWindow`, `moveToDisplay`, `arrangeGrid`, `moveDivider`, `swapWindow`.
        var section: String
        /// Whether the list shows the binding under the current search.
        var visible: Bool
        /// False only for a shortcut that is not registered.
        var active: Bool
    }

    /// The text in the search field.
    var search: String

    var isOpen: Bool
    /// Whether Piccolo is the active application (`NSApp.isActive`).
    var isActive: Bool
    /// Whether the Settings window is the key window of the active application.
    var isKey: Bool
    var bindings: [Binding]
    var resizeStep: Double
    /// The window animation, by its name in the config file: `off`, `fast`, `medium` or `slow`.
    var animation: String
    /// The grid fill order, by its name in the config file: `rows` or `columns`.
    var gridFillOrder: String
    var destinationPreview: Bool
    /// The window gap in points.
    var gap: Int
    var issues: [String]
    var error: String?
    var recordingBindingID: UUID?
    /// The binding the list has selected, if any.
    var selectedBindingID: UUID?
    /// The tab the window shows: `shortcuts` or `general`.
    var tab: String
    /// What the system says about starting Piccolo at login, by the name of `LoginItemStatus`.
    var loginItem: String
    /// The language chosen for the interface: `system`, or one of the codes `en`, `zh-Hans`, `zh-Hant`,
    /// `ja`, `fr`, `es`, `pt-BR` and `de`. It applies the next time Piccolo starts.
    var language: String
    /// The language the running Piccolo shows its texts in: one of the eight codes, never `system`.
    var effectiveLanguage: String
    /// Whether the chosen language differs from the effective one, so that a restart is needed.
    var restartRequired: Bool
    /// Why the last restart could not be arranged, if it could not.
    var restartError: String?
}

/// The Settings window commands of the Debug control channel.
extension PiccoloClient {
    /// The process ID of the Debug Piccolo (`status`).
    func pid() throws -> pid_t {
        let result = try send("status")
        guard let pid = result["pid"]?.intValue else {
            throw AcceptanceFailure("Piccolo's status has no pid: \(result)")
        }
        return pid_t(pid)
    }

    /// The path of the Piccolo bundle that is running (`status`), which is what `open` is given
    /// to hand the app to LaunchServices.
    func bundlePath() throws -> String {
        let result = try send("status")
        guard let path = result["bundlePath"]?.stringValue, !path.isEmpty else {
            throw AcceptanceFailure("Piccolo's status has no bundlePath: \(result)")
        }
        return path
    }

    // MARK: Window

    @discardableResult
    func settingsOpen() throws -> SettingsState {
        try settingsCommand("settings.open")
    }

    @discardableResult
    func settingsClose() throws -> SettingsState {
        try settingsCommand("settings.close")
    }

    func settingsState() throws -> SettingsState {
        try settingsCommand("settings.state")
    }

    // MARK: View state

    @discardableResult
    func settingsSelect(_ id: UUID) throws -> SettingsState {
        try settingsCommand("settings.select", ["id": .string(id.uuidString)])
    }

    /// `settings.select` with an ID that must be refused. Returns the message.
    func settingsSelectExpectingRefusal(_ id: UUID) throws -> String {
        try settingsExpectingRefusal("settings.select", ["id": .string(id.uuidString)])
    }

    @discardableResult
    func settingsSetSearch(_ text: String) throws -> SettingsState {
        try settingsCommand("settings.setSearch", ["text": .string(text)])
    }

    @discardableResult
    func settingsShowTab(_ tab: String) throws -> SettingsState {
        try settingsCommand("settings.showTab", ["tab": .string(tab)])
    }

    /// `settings.showTab` with a tab that must be refused. Returns the message.
    func settingsShowTabExpectingRefusal(_ tab: String) throws -> String {
        try settingsExpectingRefusal("settings.showTab", ["tab": .string(tab)])
    }

    // MARK: Edits

    @discardableResult
    func settingsAddBinding() throws -> SettingsState {
        try settingsCommand("settings.addBinding")
    }

    @discardableResult
    func settingsRemoveBinding(_ id: UUID) throws -> SettingsState {
        try settingsCommand("settings.removeBinding", ["id": .string(id.uuidString)])
    }

    @discardableResult
    func settingsUpdateAction(_ id: UUID, _ action: Action) throws -> SettingsState {
        try settingsCommand("settings.updateAction", updateParams(id, action))
    }

    /// `settings.updateAction` with an action that must be rejected. Returns the message.
    func settingsUpdateActionExpectingRejection(_ id: UUID, _ action: Action) throws -> String {
        try settingsExpectingRefusal("settings.updateAction", updateParams(id, action))
    }

    /// `settings.restoreDefaults`: replaces the bindings with the default shortcuts without the alert.
    /// Answers the state and the name of the copy kept next to the config file (`nil` when there was no file).
    func settingsRestoreDefaults() throws -> (state: SettingsState, backup: String?) {
        let result = try send("settings.restoreDefaults")
        return (try decodeState(result, of: "settings.restoreDefaults"), result["backup"]?.stringValue)
    }

    @discardableResult
    func settingsSetResizeStep(_ value: Double) throws -> SettingsState {
        try settingsCommand("settings.setResizeStep", ["value": .double(value)])
    }

    /// `settings.setResizeStep` with a value that must be rejected. Returns the message.
    func settingsSetResizeStepExpectingRejection(_ value: Double) throws -> String {
        try settingsExpectingRefusal("settings.setResizeStep", ["value": .double(value)])
    }

    /// `settings.setGap`: the window gap in points.
    @discardableResult
    func settingsSetGap(_ value: Int) throws -> SettingsState {
        try settingsCommand("settings.setGap", ["value": .int(value)])
    }

    /// `settings.setGap` with a value that must be rejected. Returns the message.
    func settingsSetGapExpectingRejection(_ value: Int) throws -> String {
        try settingsExpectingRefusal("settings.setGap", ["value": .int(value)])
    }

    /// `settings.setAnimation` with a name of the config file (`off`, `fast`, `medium` or `slow`).
    @discardableResult
    func settingsSetAnimation(_ name: String) throws -> SettingsState {
        try settingsCommand("settings.setAnimation", ["value": .string(name)])
    }

    /// `settings.setAnimation` with a name that must be refused. Returns the message.
    func settingsSetAnimationExpectingRefusal(_ name: String) throws -> String {
        try settingsExpectingRefusal("settings.setAnimation", ["value": .string(name)])
    }

    /// `settings.setGridFillOrder` with a name of the config file (`rows` or `columns`).
    @discardableResult
    func settingsSetGridFillOrder(_ name: String) throws -> SettingsState {
        try settingsCommand("settings.setGridFillOrder", ["value": .string(name)])
    }

    /// `settings.setDestinationPreview`.
    @discardableResult
    func settingsSetDestinationPreview(_ enabled: Bool) throws -> SettingsState {
        try settingsCommand("settings.setDestinationPreview", ["enabled": .bool(enabled)])
    }

    /// `settings.setLanguage` with `system` or a code of the interface languages.
    @discardableResult
    func settingsSetLanguage(_ language: String) throws -> SettingsState {
        try settingsCommand("settings.setLanguage", ["language": .string(language)])
    }

    /// `settings.setLanguage` with a value that must be refused. Returns the message.
    func settingsSetLanguageExpectingRefusal(_ language: String) throws -> String {
        try settingsExpectingRefusal("settings.setLanguage", ["language": .string(language)])
    }

    /// `settings.restartNow`: the code path of the Restart Now button. Piccolo answers first and quits a
    /// moment later, so the answer comes from the process that is about to be replaced.
    @discardableResult
    func settingsRestartNow() throws -> SettingsState {
        try settingsCommand("settings.restartNow")
    }

    // MARK: Recording

    @discardableResult
    func settingsBeginRecording(_ id: UUID) throws -> SettingsState {
        try settingsCommand("settings.beginRecording", ["id": .string(id.uuidString)])
    }

    @discardableResult
    func settingsCancelRecording() throws -> SettingsState {
        try settingsCommand("settings.cancelRecording")
    }

    /// One `settings.record`: a refusal (Piccolo not frontmost, Settings not key) is an error.
    /// A shortcut the model rejects is not: it comes back in the state's `error`.
    func settingsRecord(_ id: UUID, _ shortcut: Shortcut) throws -> SettingsState {
        try settingsCommand("settings.record", recordParams(id, shortcut))
    }

    /// `settings.record`, answering the raw response (for refusals).
    func settingsRecordRaw(_ id: UUID, _ shortcut: Shortcut) throws -> ControlResponse {
        try sendRaw("settings.record", recordParams(id, shortcut))
    }

    // MARK: Helpers

    private func updateParams(_ id: UUID, _ action: Action) throws -> [String: JSONValue] {
        let encoded = try JSONValue(encoding: action)
        return ["id": .string(id.uuidString), "action": encoded]
    }

    private func recordParams(_ id: UUID, _ shortcut: Shortcut) -> [String: JSONValue] {
        [
            "id": .string(id.uuidString),
            "keyCode": .int(shortcut.keyCode),
            "modifiers": .array(shortcut.modifiers.map(\.rawValue).sorted().map { .string($0) }),
        ]
    }

    private func settingsCommand(_ command: String, _ params: [String: JSONValue] = [:]) throws -> SettingsState {
        try decodeState(try send(command, params), of: command)
    }

    /// A command that must answer `ok: false`. Returns the reason.
    private func settingsExpectingRefusal(_ command: String, _ params: [String: JSONValue]) throws -> String {
        let response = try sendRaw(command, params)
        guard !response.ok else {
            throw AcceptanceFailure(
                "\(command) accepted \(params), which should have been rejected; it answered \(String(describing: response.result))"
            )
        }
        guard let message = response.error, !message.isEmpty else {
            throw AcceptanceFailure("\(command) rejected \(params) without saying why")
        }
        return message
    }

    func decodeState(_ result: JSONValue, of command: String) throws -> SettingsState {
        do {
            return try result.decode(SettingsState.self)
        } catch {
            throw AcceptanceFailure("Piccolo's \(command) answer is malformed (\(error)): \(result)")
        }
    }
}
