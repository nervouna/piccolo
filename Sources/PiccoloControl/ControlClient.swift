import Foundation

/// Sends requests to a ``ControlServer`` by service name. Each call is synchronous
/// and opens its own connection, so a client has no state and no lifetime to manage.
public struct ControlClient: Sendable {
    public static let defaultTimeout: TimeInterval = 5

    public let serviceName: String
    /// How long to wait for the reply, in seconds.
    public let timeout: TimeInterval

    public init(serviceName: String, timeout: TimeInterval = ControlClient.defaultTimeout) {
        self.serviceName = serviceName
        self.timeout = timeout
    }

    /// Sends `request` and returns the server's response.
    ///
    /// A command that ran and failed is a response with `ok == false`, not an error.
    ///
    /// - Throws: ``ControlError`` when no server is running, when it does not answer
    ///   in time, or when the exchange breaks.
    public func send(_ request: ControlRequest) throws -> ControlResponse {
        let payload: Data
        do {
            payload = try request.encoded()
        } catch {
            throw ControlError.invalidRequest(error.localizedDescription)
        }

        let reply = try sendRaw(payload)
        do {
            return try ControlResponse(decoding: reply)
        } catch {
            let excerpt = String(decoding: reply.prefix(200), as: UTF8.self)
            throw ControlError.invalidResponse(excerpt)
        }
    }

    public func send(
        command: String, params: [String: JSONValue] = [:]
    ) throws -> ControlResponse {
        try send(ControlRequest(command: command, params: params))
    }

    /// Delivers bytes and returns the raw reply. Exposed to tests, which use it to
    /// send input no well-behaved client would produce.
    func sendRaw(_ payload: Data) throws -> Data {
        guard let remote = CFMessagePortCreateRemote(nil, serviceName as CFString) else {
            throw ControlError.noServer(serviceName: serviceName)
        }
        defer { CFMessagePortInvalidate(remote) }

        // A timeout of zero would send without waiting for the reply.
        let seconds = max(timeout, 0.001)
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            remote, ControlWire.messageID, payload as CFData, seconds, seconds,
            ControlWire.replyMode, &reply)
        let replyData = reply?.takeRetainedValue()

        switch status {
        case Int32(kCFMessagePortSuccess):
            guard let replyData else {
                throw ControlError.invalidResponse("the server sent an empty reply")
            }
            return replyData as Data
        case Int32(kCFMessagePortSendTimeout), Int32(kCFMessagePortReceiveTimeout):
            throw ControlError.timeout(serviceName: serviceName, seconds: timeout)
        case Int32(kCFMessagePortIsInvalid):
            throw ControlError.noServer(serviceName: serviceName)
        default:
            throw ControlError.transport(serviceName: serviceName, code: status)
        }
    }
}
