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
    ///   fixture's pid so that they never move anybody's real windows, and an optional `animation`
    ///   (`"off"`, `"fast"`, `"medium"` or `"slow"`) that replaces the config's animation for this
    ///   call; an unknown value is refused before anything moves. The call returns once the windows
    ///   have glided and been placed. The result is
    ///   `{"target", "achieved"}` for a placement, `{"nothingToDo": true}`, or for `arrangeGrid`
    ///   `{"display": index, "windows": [{"window", "target", "achieved"} | {"window", "target", "error"}]}`.
    ///   A `moveDivider` action runs as its shortcut would, with the resize step of the loaded config, on
    ///   the group of the focused window; `onlyPid` also restricts it (a group with a window of another
    ///   process is dissolved, not moved). The result is `{"moved": true, "display": index, "windows":
    ///   [...]}` as for `arrangeGrid`, in cell order, or `{"nothingToDo": true, "reason": "noFocusedWindow" |
    ///   "noGroup" | "dissolved" | "cannotMove", "message": text}`, where `dissolved` adds `"window"` (the
    ///   number of the first window that broke the group) and `"cause"` (`"missing"` or `"moved"`).
    ///   A `swapWindow` action exchanges the focused window with its neighbour on that side in its group,
    ///   as its shortcut would; `onlyPid` restricts it as it does `moveDivider`. The result is
    ///   `{"swapped": true, "display": index, "windows": [...]}` as for `moveDivider`, every window of
    ///   the group in cell order after the swap, or `{"nothingToDo": true, "reason": "noFocusedWindow" |
    ///   "noGroup" | "dissolved" | "noNeighbour", "message": text}`, where `dissolved` adds `"window"`
    ///   and `"cause"` as for `moveDivider`.
    /// - `focus.history`: `{"windows": [window numbers]}`, most recently focused first.
    /// - `groups.list`: the groups of windows Piccolo arranged and still tracks, one per display (after a
    ///   swap the windows are listed in their exchanged order):
    ///   `[{"display": index, "visibleFrame": rect, "layout": {"rows": [{"height", "widths": [...]}]},
    ///   "windows": [{"window": number, "frame": rect}]}]`, the windows in cell order with the frames
    ///   recorded for them. A row layout (rows first) is written as `{"rows": [...]}` and its cells are
    ///   numbered row by row; a column layout (`gridFillOrder` columns) is written as
    ///   `{"columns": [{"width", "heights": [...]}]}` and its cells are numbered column by column, top to
    ///   bottom within a column. Empty when there is none.
    nonisolated static func registerArrangeCommands(
        in router: inout ControlRouter, executor: @escaping @Sendable () -> ActionExecutor
    ) {
        router.register("action.run") { params in
            let action = try params.decode(Action.self)
            let pid = try onlyPid(in: params)
            let animation = try animationParam(in: params)
            // The settings are those of the config in effect, as for a shortcut, except that the
            // optional `animation` param replaces the config's animation for this call. A divider
            // move uses the resize step, arrangeGrid the grid fill order, and every action the animation.
            var settings = onMainActor { ActionSettings(ConfigController.shared.config) }
            if let animation { settings.animation = animation }
            return json(for: try executor().run(action, onlyPid: pid, settings: settings))
        }

        router.register("groups.list") { _ in
            .array(executor().linkedGroups.map(json(for:)))
        }

        router.register("focus.history") { _ in
            ["windows": .array(executor().focusHistory.map { .int(Int($0.rawValue)) })]
        }
    }

    /// The optional `animation` param: `off`, `fast`, `medium` or `slow`, the names of the config file.
    private nonisolated static func animationParam(in params: [String: JSONValue]) throws -> WindowAnimation? {
        guard let value = params["animation"], value != .null else { return nil }
        let names = WindowAnimation.allCases.map(\.rawValue).joined(separator: ", ")
        guard let name = value.stringValue, let animation = WindowAnimation(rawValue: name) else {
            throw ControlCommandError.invalidParams("animation must be one of \(names)")
        }
        return animation
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
        case .swap(.swapped(let display, let windows)):
            return [
                "swapped": .bool(true),
                "display": .int(display),
                "windows": .array(windows.map(json(for:))),
            ]
        case .swap(.nothingToDo(let reason)):
            return json(for: reason)
        }
    }

    private nonisolated static func json(for reason: DividerMoveOutcome.Reason) -> JSONValue {
        switch reason {
        case .noFocusedWindow:
            return nothingToDo(reason: "noFocusedWindow", message: reason.message)
        case .noGroup:
            return nothingToDo(reason: "noGroup", message: reason.message)
        case .dissolved(let breakage):
            return dissolved(breakage, message: reason.message)
        case .cannotMove:
            return nothingToDo(reason: "cannotMove", message: reason.message)
        }
    }

    private nonisolated static func json(for reason: SwapOutcome.Reason) -> JSONValue {
        switch reason {
        case .noFocusedWindow:
            return nothingToDo(reason: "noFocusedWindow", message: reason.message)
        case .noGroup:
            return nothingToDo(reason: "noGroup", message: reason.message)
        case .dissolved(let breakage):
            return dissolved(breakage, message: reason.message)
        case .noNeighbour:
            return nothingToDo(reason: "noNeighbour", message: reason.message)
        }
    }

    private nonisolated static func nothingToDo(reason: String, message: String) -> JSONValue {
        ["nothingToDo": .bool(true), "reason": .string(reason), "message": .string(message)]
    }

    /// The answer for a group that no longer held: the cause (`missing` or `moved`) and the window.
    private nonisolated static func dissolved(_ breakage: LayoutGroup.Breakage, message: String) -> JSONValue {
        var entry: [String: JSONValue] = [
            "nothingToDo": .bool(true),
            "reason": .string("dissolved"),
            "message": .string(message),
        ]
        switch breakage {
        case .missing(let window):
            entry["cause"] = .string("missing")
            entry["window"] = .int(Int(window.rawValue))
        case .moved(let window):
            entry["cause"] = .string("moved")
            entry["window"] = .int(Int(window.rawValue))
        }
        return .object(entry)
    }

    private nonisolated static func json(for entry: LayoutGroups.Entry) -> JSONValue {
        let group = entry.group
        let layout: JSONValue
        switch group.layout.orientation {
        case .rows:
            layout = [
                "rows": .array(group.layout.rows.map { row -> JSONValue in
                    [
                        "height": .double(row.height),
                        "widths": .array(row.widths.map { .double($0) }),
                    ]
                })
            ]
        case .columns:
            layout = [
                "columns": .array(group.layout.columns.map { column -> JSONValue in
                    [
                        "width": .double(column.width),
                        "heights": .array(column.heights.map { .double($0) }),
                    ]
                })
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
            "layout": layout,
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
