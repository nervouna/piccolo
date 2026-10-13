import Foundation

/// The service names of the apps that host a control server. A client addresses a
/// server by this name only, so several apps can each host one.
public enum ControlServiceName {
    /// The Piccolo app (Debug builds only).
    public static let piccolo = "io.damao.piccolo.control"
}

/// Hosts a control channel under a service name.
///
/// The transport is a `CFMessagePort`: a Mach port registered in the current user's
/// bootstrap namespace. It is reachable by processes of the same user in the same
/// login session only and involves no network socket and no file on disk. The port
/// disappears with the process, so a crash leaves nothing stale behind.
///
/// Requests are handled one at a time on `queue`. The handler runs on that queue, not
/// on the thread that created the server.
public final class ControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ControlRequest) -> ControlResponse

    public let serviceName: String
    // Immutable after init; `CFMessagePortInvalidate` is safe from any thread.
    private let port: CFMessagePort

    /// Registers `serviceName` and starts serving.
    ///
    /// - Parameters:
    ///   - serviceName: The name clients use to find this server.
    ///   - queue: The queue the handler runs on. Defaults to a private serial queue.
    ///   - handler: Answers one request. Must not block for longer than clients wait.
    /// - Throws: ``ControlError/cannotStartServer(serviceName:reason:)`` when the name
    ///   is already taken, in this process or another one.
    public init(
        serviceName: String,
        queue: DispatchQueue? = nil,
        handler: @escaping Handler
    ) throws {
        let box = HandlerBox(handler: handler)
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<HandlerBox>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<HandlerBox>.fromOpaque(info).release()
            },
            copyDescription: nil)

        var shouldFreeInfo: DarwinBoolean = false
        let created = CFMessagePortCreateLocal(
            nil, serviceName as CFString, Callbacks.handle, &context, &shouldFreeInfo)
        // `shouldFreeInfo` also covers "returned the port an earlier server in this
        // process already owns", which must be neither used nor invalidated.
        guard let port = created, !shouldFreeInfo.boolValue else {
            throw ControlError.cannotStartServer(
                serviceName: serviceName, reason: "the name is already in use")
        }

        self.serviceName = serviceName
        self.port = port
        CFMessagePortSetDispatchQueue(
            port, queue ?? DispatchQueue(label: "io.damao.piccolo.control.server"))
    }

    /// Stops serving and frees the service name. Safe to call more than once.
    public func stop() {
        CFMessagePortInvalidate(port)
    }

    deinit {
        stop()
    }
}

/// Carries the handler through the C callback's `info` pointer. The port retains it
/// for as long as the port lives.
private final class HandlerBox: Sendable {
    let handler: ControlServer.Handler

    init(handler: @escaping ControlServer.Handler) {
        self.handler = handler
    }
}

/// Wire constants shared with ``ControlClient``.
enum ControlWire {
    static let messageID: Int32 = 1
    /// The run loop mode the client waits in for a reply. A private mode keeps the
    /// wait from running unrelated sources of the calling thread's run loop.
    static var replyMode: CFString { "io.damao.piccolo.control.reply" as CFString }
}

/// C callbacks cannot capture, and must not inherit main-actor isolation: they run on
/// the server's queue.
private enum Callbacks {
    static let handle: CFMessagePortCallBack = { _, _, data, info in
        guard let info else { return nil }
        let box = Unmanaged<HandlerBox>.fromOpaque(info).takeUnretainedValue()

        let response: ControlResponse
        do {
            let request = try ControlRequest(decoding: data.map { $0 as Data } ?? Data())
            response = box.handler(request)
        } catch {
            response = .failure("invalid request: \(error.localizedDescription)")
        }

        let reply =
            (try? response.encoded())
            ?? Data(#"{"error":"the response could not be encoded","ok":false}"#.utf8)
        return Unmanaged.passRetained(reply as CFData)
    }
}
