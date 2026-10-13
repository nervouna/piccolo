import CoreGraphics
import Foundation
import PiccoloControl

/// The installed Debug build of Piccolo, driven over its control channel.
struct PiccoloClient: Sendable {
    /// Accessibility calls have a 2 s messaging timeout each and a window operation makes
    /// several, so the client waits well beyond the default.
    private let client = ControlClient(serviceName: ControlServiceName.piccolo, timeout: 15)

    /// Sends a command and returns its result; a failure response is an error.
    func send(_ command: String, _ params: [String: JSONValue] = [:]) throws -> JSONValue {
        let response: ControlResponse
        do {
            response = try client.send(command: command, params: params)
        } catch {
            var isRetryable = true
            if case ControlError.noServer = error { isRetryable = false }
            throw AcceptanceFailure(
                "Piccolo command '\(command)' failed: \(error.localizedDescription). "
                    + "Is the Debug build installed and running? scripts/accept.sh does that.",
                isRetryable: isRetryable)
        }
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
}
