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
    }

    var isOpen: Bool
    var bindings: [Binding]
    var resizeStep: Double
    var issues: [String]
    var error: String?
    var recordingBindingID: UUID?
    /// The binding the list has selected, if any.
    var selectedBindingID: UUID?
    /// The tab the window shows: `shortcuts` or `general`.
    var tab: String
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

    @discardableResult
    func settingsSetResizeStep(_ value: Double) throws -> SettingsState {
        try settingsCommand("settings.setResizeStep", ["value": .double(value)])
    }

    /// `settings.setResizeStep` with a value that must be rejected. Returns the message.
    func settingsSetResizeStepExpectingRejection(_ value: Double) throws -> String {
        try settingsExpectingRefusal("settings.setResizeStep", ["value": .double(value)])
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
