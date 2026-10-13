import Foundation

/// Why a command could not be carried out. Thrown by command handlers; the
/// router turns it into a failure response.
public enum ControlCommandError: Error, Equatable, LocalizedError {
    /// The command ran and failed. The message goes to the caller unchanged.
    case failed(String)
    /// The params did not match what the command expects.
    case invalidParams(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        case .invalidParams(let message):
            return "invalid params: \(message)"
        }
    }
}

/// Why a request did not complete: failures of the channel itself, as opposed to a
/// command that ran and failed (that is a `ControlResponse` with `ok == false`).
public enum ControlError: Error, Equatable, LocalizedError {
    /// Nothing is listening on the service name.
    case noServer(serviceName: String)
    /// The server did not answer within the client's timeout.
    case timeout(serviceName: String, seconds: TimeInterval)
    /// The message could not be delivered or the reply was lost.
    case transport(serviceName: String, code: Int32)
    /// The reply was not a valid response.
    case invalidResponse(String)
    /// The server could not be started.
    case cannotStartServer(serviceName: String, reason: String)
    /// The request could not be encoded.
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .noServer(let name):
            return "no server: nothing is listening on control service '\(name)'"
        case .timeout(let name, let seconds):
            return "timeout: control service '\(name)' did not answer within \(seconds) s"
        case .transport(let name, let code):
            return "transport error \(code) talking to control service '\(name)'"
        case .invalidResponse(let detail):
            return "invalid response: \(detail)"
        case .cannotStartServer(let name, let reason):
            return "cannot start control server '\(name)': \(reason)"
        case .invalidRequest(let detail):
            return "invalid request: \(detail)"
        }
    }
}

/// The message a failure response carries for an error thrown by a handler.
func failureMessage(for error: any Error) -> String {
    if let described = (error as? any LocalizedError)?.errorDescription, !described.isEmpty {
        return described
    }
    return String(describing: error)
}
