#if DEBUG
import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem

/// The control commands about running actions and the focus history. Debug builds only, like the
/// control server itself.
extension DebugControlServer {
    /// Registers:
    ///
    /// - `action.run`: runs an action. The params are the action exactly as the config file writes it,
    ///   for example `{"type": "arrangeGrid", "count": 4, "rows": 2, "columns": 2}`, plus an optional
    ///   `onlyPid`, the process whose windows `arrangeGrid` may move and the only one: tests pass the
    ///   fixture's pid so that they never move anybody's real windows. The result is
    ///   `{"target", "achieved"}` for a placement, `{"nothingToDo": true}`, or for `arrangeGrid`
    ///   `{"display": index, "windows": [{"window", "target", "achieved"} | {"window", "target", "error"}]}`.
    /// - `focus.history`: `{"windows": [window numbers]}`, most recently focused first.
    nonisolated static func registerArrangeCommands(in router: inout ControlRouter, executor: ActionExecutor) {
        router.register("action.run") { params in
            let action = try params.decode(Action.self)
            let outcome = try executor.run(action, onlyPid: try onlyPid(in: params))
            return json(for: outcome)
        }

        router.register("focus.history") { _ in
            ["windows": .array(executor.focusHistory.map { .int(Int($0.rawValue)) })]
        }
    }

    /// The optional `onlyPid` param: a positive process ID.
    private nonisolated static func onlyPid(in params: [String: JSONValue]) throws -> pid_t? {
        guard let value = params["onlyPid"], value != .null else { return nil }
        guard let number = value.intValue, number > 0, let pid = pid_t(exactly: number) else {
            throw ControlCommandError.invalidParams("onlyPid must be a positive integer")
        }
        return pid
    }

    private nonisolated static func json(for outcome: ActionOutcome) -> JSONValue {
        switch outcome {
        case .placed(let target, let achieved):
            return [
                "target": JSONValue(rect: target),
                "achieved": JSONValue(rect: achieved),
            ]
        case .nothingToDo:
            return ["nothingToDo": .bool(true)]
        case .arranged(let arrangement):
            return [
                "display": .int(arrangement.displayIndex),
                "windows": .array(arrangement.windows.map(json(for:))),
            ]
        }
    }

    private nonisolated static func json(for window: ArrangedWindow) -> JSONValue {
        var entry: [String: JSONValue] = [
            "window": .int(Int(window.window.rawValue)),
            "target": JSONValue(rect: window.target),
        ]
        switch window.result {
        case .placed(let achieved):
            entry["achieved"] = JSONValue(rect: achieved)
        case .failed(let message):
            entry["error"] = .string(message)
        }
        return .object(entry)
    }
}
#endif
