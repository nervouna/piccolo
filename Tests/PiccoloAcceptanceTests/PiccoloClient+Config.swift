import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem

/// The config and hotkey commands of the Debug control channel.
extension PiccoloClient {
    /// A shortcut `config.status` lists as registered.
    struct RegisteredShortcut: Decodable, Equatable {
        var id: UUID
        var keyCode: Int
        var modifiers: Set<Modifier>
    }

    /// What `config.status`, `config.load` and `config.reload` answer.
    struct ConfigStatus: Decodable, Equatable {
        var path: String
        var bindingCount: Int
        var registered: [RegisteredShortcut]
        var issues: [String]
    }

    /// `config.status`: the config Piccolo runs with.
    func configStatus() throws -> ConfigStatus {
        try decodeStatus(try send("config.status"), of: "config.status")
    }

    /// `config.load`: loads `url` instead of the default config, for this run of Piccolo only.
    @discardableResult
    func loadConfig(at url: URL) throws -> ConfigStatus {
        try decodeStatus(try send("config.load", ["path": .string(url.path)]), of: "config.load")
    }

    /// `config.reload`: loads the default config again.
    @discardableResult
    func reloadConfig() throws -> ConfigStatus {
        try decodeStatus(try send("config.reload"), of: "config.reload")
    }

    /// `hotkey.simulate`: presses the shortcut of a registered binding with real keyboard events.
    /// Answers once Piccolo has seen the hotkey fire; the action it runs may still be under way.
    func simulateHotkey(_ id: UUID) throws {
        let result = try send("hotkey.simulate", ["id": .string(id.uuidString)])
        guard result["fired"]?.boolValue == true else {
            throw AcceptanceFailure("hotkey.simulate for \(id) did not report the hotkey as fired: \(result)")
        }
    }

    /// `hotkey.simulate` for a binding that must be refused. Returns the reason; an answer that
    /// says `ok: true` is a failure.
    func simulateHotkeyExpectingRefusal(_ id: UUID) throws -> String {
        let response = try sendRaw("hotkey.simulate", ["id": .string(id.uuidString)])
        guard !response.ok else {
            throw AcceptanceFailure(
                "hotkey.simulate accepted binding \(id), which has no registered shortcut; it answered \(String(describing: response.result))"
            )
        }
        guard let message = response.error, !message.isEmpty else {
            throw AcceptanceFailure("hotkey.simulate refused binding \(id) without saying why")
        }
        return message
    }

    /// `displays`: the displays as Piccolo sees them, the primary display first.
    func displays() throws -> [ScreenInfo] {
        let result = try send("displays")
        guard let entries = result.arrayValue, !entries.isEmpty else {
            throw AcceptanceFailure("Piccolo reports no display: \(result)")
        }
        return try entries.enumerated().map { index, entry in
            guard let frame = entry["frame"]?.rectValue, let visibleFrame = entry["visibleFrame"]?.rectValue else {
                throw AcceptanceFailure("Piccolo's displays answer is malformed at index \(index): \(entry)")
            }
            return ScreenInfo(index: index, isPrimary: index == 0, frame: frame, visibleFrame: visibleFrame)
        }
    }

    private func decodeStatus(_ result: JSONValue, of command: String) throws -> ConfigStatus {
        do {
            return try result.decode(ConfigStatus.self)
        } catch {
            throw AcceptanceFailure("Piccolo's \(command) answer is malformed (\(error)): \(result)")
        }
    }
}
