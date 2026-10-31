import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore

/// What `settings.state` and the keymap commands answer with about the keymap: the rows, the row that
/// records, the conflict and the places of errors and of the sheet. The rest of the state is
/// ``SettingsState``.
struct KeymapState: Decodable, Equatable {
    struct Row: Decodable, Equatable {
        struct Entry: Decodable, Equatable {
            var bindingID: UUID
            var shortcutText: String
            var active: Bool
        }

        /// The row's name: `placeWindow.leftHalf`, `restoreWindow`, ... or a layout binding's UUID.
        var row: String
        /// The section's name: `halves`, `quarters`, `thirds`, `other`, `displays`, `grids`, `dividers`,
        /// `swaps` or `customAreas`.
        var section: String
        var name: String
        var editable: Bool
        /// The bindings of the row that have a shortcut.
        var shortcuts: [Entry]
        var recording: Bool
    }

    struct Conflict: Decodable, Equatable {
        var row: String
        var shortcutText: String
        var ownerBindingID: UUID
        var ownerName: String
    }

    var rows: [Row]
    /// The name of the row that is waiting for a key press.
    var recordingRow: String?
    var conflict: Conflict?
    var error: String?
    /// `{"row": name}`, `{"field": "gap" | "resizeStep"}` or `"window"`.
    var errorTarget: JSONValue?
    /// `{"new": section}` or `{"edit": id}`.
    var layoutEditor: JSONValue?
    var bindings: [SettingsState.Binding]
    var search: String
}

/// The keymap commands of the Debug control channel.
extension PiccoloClient {
    func keymapState() throws -> KeymapState {
        try decodeKeymapState(try send("settings.state"), of: "settings.state")
    }

    @discardableResult
    func keymapBeginRecording(_ row: String) throws -> KeymapState {
        try keymapCommand("settings.beginRecording", ["row": .string(row)])
    }

    /// `settings.beginRecording` with a row that must be refused. Returns the message.
    func keymapBeginRecordingExpectingRefusal(_ row: String) throws -> String {
        try keymapExpectingRefusal("settings.beginRecording", ["row": .string(row)])
    }

    /// `settings.record`, answering the raw response (for refusals).
    func keymapRecordRaw(_ row: String, _ shortcut: Shortcut) throws -> ControlResponse {
        try sendRaw(
            "settings.record",
            [
                "row": .string(row),
                "keyCode": .int(shortcut.keyCode),
                "modifiers": .array(shortcut.modifiers.map(\.rawValue).sorted().map { .string($0) }),
            ])
    }

    @discardableResult
    func keymapClearShortcut(_ row: String) throws -> KeymapState {
        try keymapCommand("settings.clearShortcut", ["row": .string(row)])
    }

    @discardableResult
    func keymapResolveConflict(replace: Bool) throws -> KeymapState {
        try keymapCommand("settings.resolveConflict", ["replace": .bool(replace)])
    }

    /// `settings.resolveConflict` with no conflict pending, which must be refused. Returns the message.
    func keymapResolveConflictExpectingRefusal(replace: Bool) throws -> String {
        try keymapExpectingRefusal("settings.resolveConflict", ["replace": .bool(replace)])
    }

    @discardableResult
    func keymapAddLayout(_ action: Action) throws -> KeymapState {
        try keymapCommand("settings.addLayout", ["action": try JSONValue(encoding: action)])
    }

    /// `settings.addLayout` with an action that must be refused. Returns the message.
    func keymapAddLayoutExpectingRefusal(_ action: Action) throws -> String {
        try keymapExpectingRefusal("settings.addLayout", ["action": try JSONValue(encoding: action)])
    }

    @discardableResult
    func keymapUpdateLayout(_ id: UUID, _ action: Action) throws -> KeymapState {
        try keymapCommand(
            "settings.updateLayout", ["id": .string(id.uuidString), "action": try JSONValue(encoding: action)])
    }

    /// `settings.updateLayout` with an action that must be refused. Returns the message.
    func keymapUpdateLayoutExpectingRefusal(_ id: UUID, _ action: Action) throws -> String {
        try keymapExpectingRefusal(
            "settings.updateLayout", ["id": .string(id.uuidString), "action": try JSONValue(encoding: action)])
    }

    /// `settings.editLayout` for the sheet of an existing layout row.
    @discardableResult
    func keymapEditLayout(row: String) throws -> KeymapState {
        try keymapCommand("settings.editLayout", ["row": .string(row)])
    }

    /// `settings.editLayout` for the sheet of a new grid (`grids`) or custom area (`customAreas`).
    @discardableResult
    func keymapEditLayout(new section: String) throws -> KeymapState {
        try keymapCommand("settings.editLayout", ["new": .string(section)])
    }

    @discardableResult
    func keymapDismissLayoutEditor() throws -> KeymapState {
        try keymapCommand("settings.dismissLayoutEditor")
    }

    // MARK: Helpers

    private func keymapCommand(_ command: String, _ params: [String: JSONValue] = [:]) throws -> KeymapState {
        try decodeKeymapState(try send(command, params), of: command)
    }

    /// A command that must answer `ok: false`. Returns the reason.
    private func keymapExpectingRefusal(_ command: String, _ params: [String: JSONValue]) throws -> String {
        let response = try sendRaw(command, params)
        guard !response.ok else {
            throw AcceptanceFailure(
                "\(command) accepted \(params), which should have been refused; it answered \(String(describing: response.result))"
            )
        }
        guard let message = response.error, !message.isEmpty else {
            throw AcceptanceFailure("\(command) refused \(params) without saying why")
        }
        return message
    }

    func decodeKeymapState(_ result: JSONValue, of command: String) throws -> KeymapState {
        do {
            return try result.decode(KeymapState.self)
        } catch {
            throw AcceptanceFailure("Piccolo's \(command) answer is malformed (\(error)): \(result)")
        }
    }
}

extension SettingsSession {
    /// `settings.record` once Piccolo is frontmost with the Settings window key. A refusal for that reason
    /// leaves nothing behind (no key was posted), so it is tried again, handing Piccolo to LaunchServices
    /// in between, until `timeout`; any other failure ends the wait.
    func record(_ row: String, _ shortcut: Shortcut, timeout: TimeInterval = 20) async throws -> KeymapState {
        try await bringPiccoloForward()
        let piccolo = self.piccolo
        return try await eventually(
            "settings.record of \(shortcut) on \(row) to be accepted", timeout: timeout, interval: 0.25
        ) {
            let response = try piccolo.keymapRecordRaw(row, shortcut)
            if response.ok {
                return .satisfied(try piccolo.decodeKeymapState(response.result ?? .null, of: "settings.record"))
            }
            let message = response.error ?? "no reason given"
            guard message.contains("frontmost") || message.contains("key window") else {
                throw AcceptanceFailure("settings.record was refused: \(message)")
            }
            // Not in front yet: try to bring it forward again, then look again.
            if let bundle = try? piccolo.bundlePath() { try? Shell.open([bundle]) }
            return .unsatisfied(message)
        }
    }
}
