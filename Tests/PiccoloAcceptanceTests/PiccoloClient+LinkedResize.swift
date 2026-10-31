import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore

/// The commands about linked resize: `action.run` with a `moveDivider` or a `swapWindow` action, and
/// `groups.list`.
extension PiccoloClient {
    /// Why `moveDivider` left every window where it was, as `action.run` reports it.
    struct DividerNothingToDo: Equatable {
        /// `noFocusedWindow`, `noGroup`, `dissolved` or `cannotMove`.
        var reason: String
        /// For `dissolved`: `missing` (a member is gone) or `moved` (a member is not where it was put).
        var cause: String?
        /// For `dissolved`: the window that broke the group.
        var windowNumber: Int?
        var message: String
    }

    /// What `action.run` answered to a `moveDivider` action.
    enum MoveDividerResult: Equatable {
        /// The divider moved. The windows of the group in cell order, each with the frame it was
        /// last sent to and the frame read back.
        case moved(display: Int, windows: [ArrangedWindow])
        case nothingToDo(DividerNothingToDo)
    }

    /// `action.run` with a `moveDivider` action, restricted to the windows of one process.
    ///
    /// `onlyPid` is not optional on purpose: a group that holds a window of another process is
    /// dissolved by the app instead of moved, so no acceptance test can move a window that is not
    /// the fixture's. The step is the one of the config in effect (see `withLinkedResize`).
    func moveDivider(_ direction: Direction, onlyPid: pid_t) throws -> MoveDividerResult {
        var params: [String: JSONValue]
        do {
            params = try JSONValue(encoding: Action.moveDivider(direction)).objectValue ?? [:]
        } catch {
            throw AcceptanceFailure("the direction \(direction) cannot be encoded: \(error)")
        }
        params["onlyPid"] = .int(Int(onlyPid))
        let result = try send("action.run", params)

        if result["nothingToDo"]?.boolValue == true {
            guard let reason = result["reason"]?.stringValue, let message = result["message"]?.stringValue else {
                throw AcceptanceFailure("Piccolo's moveDivider answer has nothingToDo but no reason: \(result)")
            }
            return .nothingToDo(
                DividerNothingToDo(
                    reason: reason, cause: result["cause"]?.stringValue,
                    windowNumber: result["window"]?.intValue, message: message))
        }
        guard result["moved"]?.boolValue == true, let display = result["display"]?.intValue,
            let entries = result["windows"]?.arrayValue
        else {
            throw AcceptanceFailure("Piccolo's moveDivider answer is neither moved nor nothingToDo: \(result)")
        }
        return .moved(display: display, windows: try Self.arrangedWindows(entries, answer: "moveDivider"))
    }

    /// The windows of a `moveDivider` or `swapWindow` answer, in cell order.
    private static func arrangedWindows(_ entries: [JSONValue], answer: String) throws -> [ArrangedWindow] {
        try entries.map { entry -> ArrangedWindow in
            guard let number = entry["window"]?.intValue, let target = entry["target"]?.rectValue else {
                throw AcceptanceFailure("Piccolo's \(answer) answer lists a malformed window: \(entry)")
            }
            return ArrangedWindow(
                windowNumber: number, target: target, achieved: entry["achieved"]?.rectValue,
                error: entry["error"]?.stringValue)
        }
    }

    /// Why `swapWindow` left every window where it was, as `action.run` reports it: the same shape as
    /// for `moveDivider`, with the reasons `noFocusedWindow`, `noGroup`, `dissolved` and `noNeighbour`.
    typealias SwapNothingToDo = DividerNothingToDo

    /// What `action.run` answered to a `swapWindow` action.
    enum SwapWindowResult: Equatable {
        /// The windows traded cells. The windows of the group in cell order after the swap, each with
        /// the frame it was last sent to and the frame read back.
        case swapped(display: Int, windows: [ArrangedWindow])
        case nothingToDo(SwapNothingToDo)
    }

    /// `action.run` with a `swapWindow` action, restricted to the windows of one process.
    ///
    /// `onlyPid` is not optional on purpose, as for `moveDivider`: a group that holds a window of
    /// another process is dissolved by the app instead of swapped.
    func swapWindow(_ direction: Direction, onlyPid: pid_t) throws -> SwapWindowResult {
        var params: [String: JSONValue]
        do {
            params = try JSONValue(encoding: Action.swapWindow(direction)).objectValue ?? [:]
        } catch {
            throw AcceptanceFailure("the direction \(direction) cannot be encoded: \(error)")
        }
        params["onlyPid"] = .int(Int(onlyPid))
        let result = try send("action.run", params)

        if result["nothingToDo"]?.boolValue == true {
            guard let reason = result["reason"]?.stringValue, let message = result["message"]?.stringValue else {
                throw AcceptanceFailure("Piccolo's swapWindow answer has nothingToDo but no reason: \(result)")
            }
            return .nothingToDo(
                SwapNothingToDo(
                    reason: reason, cause: result["cause"]?.stringValue,
                    windowNumber: result["window"]?.intValue, message: message))
        }
        guard result["swapped"]?.boolValue == true, let display = result["display"]?.intValue,
            let entries = result["windows"]?.arrayValue
        else {
            throw AcceptanceFailure("Piccolo's swapWindow answer is neither swapped nor nothingToDo: \(result)")
        }
        return .swapped(display: display, windows: try Self.arrangedWindows(entries, answer: "swapWindow"))
    }

    /// A window of a group, with the frame the group recorded for it.
    struct GroupWindow: Equatable {
        var windowNumber: Int
        var frame: CGRect
    }

    /// A group of windows Piccolo tracks, as `groups.list` reports it.
    struct GroupInfo: Equatable {
        var display: Int
        var visibleFrame: CGRect
        /// A row layout when the group was arranged rows first, a column layout when it was arranged
        /// columns first.
        var layout: TileLayout
        /// In cell order: row-major for a row layout, column-major for a column layout.
        var windows: [GroupWindow]
    }

    /// `groups.list`: the groups of windows Piccolo arranged and still tracks, one per display.
    func groups() throws -> [GroupInfo] {
        let result = try send("groups.list")
        guard let entries = result.arrayValue else {
            throw AcceptanceFailure("Piccolo's groups.list answer is not an array: \(result)")
        }
        return try entries.map { entry in
            guard let display = entry["display"]?.intValue,
                let visibleFrame = entry["visibleFrame"]?.rectValue,
                let layoutEntry = entry["layout"],
                let windows = entry["windows"]?.arrayValue
            else {
                throw AcceptanceFailure("Piccolo's groups.list lists a malformed group: \(entry)")
            }
            let layout = try Self.layout(from: layoutEntry)
            let members = try windows.map { window -> GroupWindow in
                guard let number = window["window"]?.intValue, let frame = window["frame"]?.rectValue else {
                    throw AcceptanceFailure("Piccolo's groups.list lists a malformed window: \(window)")
                }
                return GroupWindow(windowNumber: number, frame: frame)
            }
            return GroupInfo(display: display, visibleFrame: visibleFrame, layout: layout, windows: members)
        }
    }

    /// A layout as `groups.list` writes it: `{"rows": [{"height", "widths"}]}` for a row layout,
    /// `{"columns": [{"width", "heights"}]}` for a column layout. Exactly one of the two keys.
    private static func layout(from entry: JSONValue) throws -> TileLayout {
        switch (entry["rows"]?.arrayValue, entry["columns"]?.arrayValue) {
        case (let rows?, nil):
            return TileLayout(rows: try rows.map { row -> TileLayout.Row in
                guard let height = row["height"]?.doubleValue,
                    let widths = row["widths"]?.arrayValue?.compactMap(\.doubleValue)
                else {
                    throw AcceptanceFailure("Piccolo's groups.list lists a malformed row: \(row)")
                }
                return TileLayout.Row(height: height, widths: widths)
            })
        case (nil, let columns?):
            return TileLayout(columns: try columns.map { column -> TileLayout.Column in
                guard let width = column["width"]?.doubleValue,
                    let heights = column["heights"]?.arrayValue?.compactMap(\.doubleValue)
                else {
                    throw AcceptanceFailure("Piccolo's groups.list lists a malformed column: \(column)")
                }
                return TileLayout.Column(width: width, heights: heights)
            })
        default:
            throw AcceptanceFailure("Piccolo's groups.list lists a layout with neither or both of rows and columns: \(entry)")
        }
    }
}
