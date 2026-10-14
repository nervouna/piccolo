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
    ///   A `moveDivider` action runs as its shortcut would, with the resize step of the loaded config, on
    ///   the group of the focused window; `onlyPid` also restricts it (a group with a window of another
    ///   process is dissolved, not moved). The result is `{"moved": true, "display": index, "windows":
    ///   [...]}` as for `arrangeGrid`, in cell order, or `{"nothingToDo": true, "reason": "noFocusedWindow" |
    ///   "noGroup" | "dissolved" | "cannotMove", "message": text}`, where `dissolved` adds `"window"` (the
    ///   number of the first window that broke the group) and `"cause"` (`"missing"` or `"moved"`).
    /// - `focus.history`: `{"windows": [window numbers]}`, most recently focused first.
    /// - `groups.list`: the groups of windows Piccolo arranged and still tracks, one per display:
    ///   `[{"display": index, "visibleFrame": rect, "layout": {"rows": [{"height", "widths": [...]}]},
    ///   "windows": [{"window": number, "frame": rect}]}]`, the windows in cell order (row-major) with the
    ///   frames recorded for them. Empty when there is none.
    nonisolated static func registerArrangeCommands(
        in router: inout ControlRouter, executor: @escaping @Sendable () -> ActionExecutor
    ) {
        router.register("action.run") { params in
            let action = try params.decode(Action.self)
            let pid = try onlyPid(in: params)
            // The settings are those of the config in effect, as for a shortcut. Only a divider move
            // uses the resize step; no action reads the animation or the fill order yet.
            let settings = onMainActor { ActionSettings(ConfigController.shared.config) }
            return json(for: try executor().run(action, onlyPid: pid, settings: settings))
        }

        router.register("groups.list") { _ in
            .array(executor().linkedGroups.map(json(for:)))
        }

        router.register("focus.history") { _ in
            ["windows": .array(executor().focusHistory.map { .int(Int($0.rawValue)) })]
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
        case .dividerMove(.moved(let moved)):
            return [
                "moved": .bool(true),
                "display": .int(moved.display),
                "windows": .array(moved.windows.map(json(for:))),
            ]
        case .dividerMove(.nothingToDo(let reason)):
            return json(for: reason)
        }
    }

    private nonisolated static func json(for reason: DividerMoveOutcome.Reason) -> JSONValue {
        var entry: [String: JSONValue] = [
            "nothingToDo": .bool(true),
            "message": .string(reason.message),
        ]
        switch reason {
        case .noFocusedWindow:
            entry["reason"] = .string("noFocusedWindow")
        case .noGroup:
            entry["reason"] = .string("noGroup")
        case .dissolved(.missing(let window)):
            entry["reason"] = .string("dissolved")
            entry["cause"] = .string("missing")
            entry["window"] = .int(Int(window.rawValue))
        case .dissolved(.moved(let window)):
            entry["reason"] = .string("dissolved")
            entry["cause"] = .string("moved")
            entry["window"] = .int(Int(window.rawValue))
        case .cannotMove:
            entry["reason"] = .string("cannotMove")
        }
        return .object(entry)
    }

    private nonisolated static func json(for entry: LayoutGroups.Entry) -> JSONValue {
        let group = entry.group
        let rows = group.layout.rows.map { row -> JSONValue in
            [
                "height": .double(row.height),
                "widths": .array(row.widths.map { .double($0) }),
            ]
        }
        let windows = zip(group.windows, group.frames).map { window, frame -> JSONValue in
            [
                "window": .int(Int(window.rawValue)),
                "frame": JSONValue(rect: frame),
            ]
        }
        return [
            "display": .int(entry.display),
            "visibleFrame": JSONValue(rect: group.visibleFrame),
            "layout": ["rows": .array(rows)],
            "windows": .array(windows),
        ]
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
