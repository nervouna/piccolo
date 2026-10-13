import Foundation

/// Maps command names to handlers and turns their results and errors into
/// responses, so that a server's handler is a one-liner: `router.handle(request)`.
public struct ControlRouter: Sendable {
    /// A command: receives the request's params and returns the result.
    public typealias Handler = @Sendable (_ params: [String: JSONValue]) throws -> JSONValue

    private var handlers: [String: Handler] = [:]

    public init() {}

    /// The registered command names, sorted.
    public var commands: [String] {
        handlers.keys.sorted()
    }

    /// Registers `handler` for `command`, replacing an earlier registration.
    public mutating func register(_ command: String, _ handler: @escaping Handler) {
        handlers[command] = handler
    }

    /// Runs the request's command. Never throws: unknown commands and handler errors
    /// become failure responses.
    public func handle(_ request: ControlRequest) -> ControlResponse {
        guard let handler = handlers[request.command] else {
            return .failure("unknown command '\(request.command)'")
        }
        do {
            return .success(try handler(request.params))
        } catch {
            return .failure(failureMessage(for: error))
        }
    }
}
