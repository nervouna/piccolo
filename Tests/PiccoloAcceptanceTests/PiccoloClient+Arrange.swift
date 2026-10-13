import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore

/// The commands about arranging windows and the focus history.
extension PiccoloClient {
    /// One window of an arrangement, as `action.run` reports it.
    struct ArrangedWindow: Equatable {
        var windowNumber: Int
        /// The cell the window was sent to.
        var target: CGRect
        /// The frame read back after the window was sent to its cell. Nil when `error` is set.
        var achieved: CGRect?
        /// Why the window could not be moved.
        var error: String?
    }

    /// What `action.run` answered to `arrangeGrid`.
    enum ArrangeResult: Equatable {
        /// The windows, most recently focused first (the one that took the top-left cell first), and
        /// the index of the display they were arranged on.
        case arranged(display: Int, windows: [ArrangedWindow])
        case nothingToDo
    }

    /// `action.run` with an `arrangeGrid` action, restricted to the windows of one process.
    ///
    /// `onlyPid` is not optional on purpose: no acceptance test may arrange the windows of the
    /// machine's owner.
    func arrangeGrid(_ grid: GridSpec, onlyPid: pid_t) throws -> ArrangeResult {
        var params: [String: JSONValue]
        do {
            params = try JSONValue(encoding: Action.arrangeGrid(grid)).objectValue ?? [:]
        } catch {
            throw AcceptanceFailure("the grid \(grid) cannot be encoded: \(error)")
        }
        params["onlyPid"] = .int(Int(onlyPid))
        return try Self.arrangeResult(from: try send("action.run", params))
    }

    /// `focus.history`: the numbers of the windows Piccolo has seen focused, most recent first.
    func focusHistory() throws -> [Int] {
        let result = try send("focus.history")
        guard let windows = result["windows"]?.arrayValue else {
            throw AcceptanceFailure("Piccolo's focus.history answer has no windows array: \(result)")
        }
        return try windows.map { entry in
            guard let number = entry.intValue else {
                throw AcceptanceFailure("Piccolo's focus.history lists \(entry), which is no window number")
            }
            return number
        }
    }

    private static func arrangeResult(from result: JSONValue) throws -> ArrangeResult {
        if result["nothingToDo"]?.boolValue == true { return .nothingToDo }
        guard let display = result["display"]?.intValue, let entries = result["windows"]?.arrayValue else {
            throw AcceptanceFailure("Piccolo's arrangeGrid answer has neither windows nor nothingToDo: \(result)")
        }
        let windows = try entries.map { entry -> ArrangedWindow in
            guard let number = entry["window"]?.intValue, let target = entry["target"]?.rectValue else {
                throw AcceptanceFailure("Piccolo's arrangeGrid answer lists a malformed window: \(entry)")
            }
            let achieved = entry["achieved"]?.rectValue
            let error = entry["error"]?.stringValue
            guard (achieved == nil) != (error == nil) else {
                throw AcceptanceFailure(
                    "Piccolo's arrangeGrid answer for window \(number) has both or neither of achieved and error: \(entry)")
            }
            return ArrangedWindow(windowNumber: number, target: target, achieved: achieved, error: error)
        }
        return .arranged(display: display, windows: windows)
    }
}
