import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore

/// The installed Debug build of Piccolo, driven over its control channel.
struct PiccoloClient: Sendable {
    /// Accessibility calls have a 2 s messaging timeout each and a window operation makes
    /// several, so the client waits well beyond the default.
    private let client = ControlClient(serviceName: ControlServiceName.piccolo, timeout: 15)

    /// Sends a command and returns the server's response, whether it succeeded or not. Only a
    /// failure of the channel itself is an error.
    func sendRaw(_ command: String, _ params: [String: JSONValue] = [:]) throws -> ControlResponse {
        do {
            return try client.send(command: command, params: params)
        } catch {
            var isRetryable = true
            if case ControlError.noServer = error { isRetryable = false }
            throw AcceptanceFailure(
                "Piccolo command '\(command)' failed: \(error.localizedDescription). "
                    + "Is the Debug build installed and running? scripts/accept.sh does that.",
                isRetryable: isRetryable)
        }
    }

    /// Sends a command and returns its result; a failure response is an error.
    func send(_ command: String, _ params: [String: JSONValue] = [:]) throws -> JSONValue {
        let response = try sendRaw(command, params)
        guard response.ok else {
            throw AcceptanceFailure(
                "Piccolo command '\(command)' was refused: \(response.error ?? "no reason given")")
        }
        return response.result ?? .null
    }

    /// `status`: whether Piccolo is trusted for Accessibility.
    func axTrusted() throws -> Bool {
        let result = try send("status")
        guard let trusted = result["axTrusted"]?.boolValue else {
            throw AcceptanceFailure("Piccolo's status has no axTrusted flag: \(result)")
        }
        return trusted
    }

    /// `window.focusedFrame`: the focused window of the app Piccolo considers frontmost.
    func focusedWindow() throws -> (pid: pid_t, frame: CGRect) {
        let result = try send("window.focusedFrame")
        guard let pid = result["pid"]?.intValue, let frame = result["frame"]?.rectValue else {
            throw AcceptanceFailure("Piccolo's focusedFrame answer is malformed: \(result)")
        }
        return (pid_t(pid), frame)
    }

    /// `window.setFocusedFrame`: moves and resizes the focused window and returns the frame
    /// Piccolo read back afterwards.
    func setFocusedFrame(_ frame: CGRect) throws -> CGRect {
        // A rect is {x, y, width, height}, which is also the shape of the command's params.
        let result = try send("window.setFocusedFrame", JSONValue(rect: frame).objectValue ?? [:])
        guard let achieved = result["frame"]?.rectValue else {
            throw AcceptanceFailure("Piccolo's setFocusedFrame answer has no frame: \(result)")
        }
        return achieved
    }

    // MARK: Actions

    /// What `action.run` answered.
    enum ActionResult: Equatable {
        /// The window was sent to `target` and read back at `achieved`.
        case placed(target: CGRect, achieved: CGRect)
        case nothingToDo
    }

    /// `action.run` with an action written the way the config file writes it.
    func runAction(_ action: Action) throws -> ActionResult {
        let params: [String: JSONValue]
        do {
            params = try JSONValue(encoding: action).objectValue ?? [:]
        } catch {
            throw AcceptanceFailure("the action \(action) cannot be encoded: \(error)")
        }
        return try runAction(params: params)
    }

    /// `action.run` with arbitrary params; a failure response is an error.
    func runAction(params: [String: JSONValue]) throws -> ActionResult {
        let result = try send("action.run", params)
        if result["nothingToDo"]?.boolValue == true { return .nothingToDo }
        guard let target = result["target"]?.rectValue, let achieved = result["achieved"]?.rectValue else {
            throw AcceptanceFailure("Piccolo's action.run answer has neither frames nor nothingToDo: \(result)")
        }
        return .placed(target: target, achieved: achieved)
    }

    /// `action.run` with params that must be refused. Returns the reason; an answer that says
    /// `ok: true` is a failure.
    func runActionExpectingRefusal(params: [String: JSONValue]) throws -> String {
        let response = try sendRaw("action.run", params)
        guard !response.ok else {
            throw AcceptanceFailure(
                "action.run accepted \(params), which should have been refused; it answered \(String(describing: response.result))"
            )
        }
        guard let message = response.error, !message.isEmpty else {
            throw AcceptanceFailure("action.run refused \(params) without saying why")
        }
        return message
    }
}
