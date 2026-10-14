import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore

/// The commands about linked resize: `action.run` with a `moveDivider` action, and `groups.list`.
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
        let windows = try entries.map { entry -> ArrangedWindow in
            guard let number = entry["window"]?.intValue, let target = entry["target"]?.rectValue else {
                throw AcceptanceFailure("Piccolo's moveDivider answer lists a malformed window: \(entry)")
            }
            return ArrangedWindow(
                windowNumber: number, target: target, achieved: entry["achieved"]?.rectValue,
                error: entry["error"]?.stringValue)
        }
        return .moved(display: display, windows: windows)
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
        var layout: TileLayout
        /// In cell order (row-major).
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
                let rows = entry["layout"]?["rows"]?.arrayValue,
                let windows = entry["windows"]?.arrayValue
            else {
                throw AcceptanceFailure("Piccolo's groups.list lists a malformed group: \(entry)")
            }
            let layoutRows = try rows.map { row -> TileLayout.Row in
                guard let height = row["height"]?.doubleValue,
                    let widths = row["widths"]?.arrayValue?.compactMap(\.doubleValue)
                else {
                    throw AcceptanceFailure("Piccolo's groups.list lists a malformed row: \(row)")
                }
                return TileLayout.Row(height: height, widths: widths)
            }
            let members = try windows.map { window -> GroupWindow in
                guard let number = window["window"]?.intValue, let frame = window["frame"]?.rectValue else {
                    throw AcceptanceFailure("Piccolo's groups.list lists a malformed window: \(window)")
                }
                return GroupWindow(windowNumber: number, frame: frame)
            }
            return GroupInfo(
                display: display, visibleFrame: visibleFrame, layout: TileLayout(rows: layoutRows),
                windows: members)
        }
    }
}
