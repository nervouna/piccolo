import Foundation
import Testing

@testable import PiccoloControl

/// Client and server talk over a real CFMessagePort inside the test process. Every
/// test uses its own service name, so tests can run in parallel and never touch a
/// running Piccolo.
@Suite("Control channel round trip")
struct ControlRoundTripTests {
    private func uniqueServiceName() -> String {
        "io.damao.piccolo.control.test.\(UUID().uuidString)"
    }

    private func makeEchoRouter() -> ControlRouter {
        var router = ControlRouter()
        router.register("echo") { params in .object(params) }
        router.register("fail") { _ in throw ControlCommandError.failed("it broke") }
        router.register("slow") { _ in
            Thread.sleep(forTimeInterval: 1.0)
            return "late"
        }
        return router
    }

    private func startServer(
        _ name: String, router: ControlRouter? = nil
    ) throws -> ControlServer {
        let router = router ?? makeEchoRouter()
        return try ControlServer(serviceName: name) { router.handle($0) }
    }

    @Test("a request reaches the server and the response comes back")
    func roundTrip() throws {
        let name = uniqueServiceName()
        let server = try startServer(name)
        defer { server.stop() }

        let client = ControlClient(serviceName: name)
        let response = try client.send(
            ControlRequest(command: "echo", params: ["a": 1, "b": ["c", true]]))
        #expect(response == .success(["a": 1, "b": ["c", true]]))
    }

    @Test("a handler failure is returned as a failure response, not thrown")
    func handlerFailure() throws {
        let name = uniqueServiceName()
        let server = try startServer(name)
        defer { server.stop() }

        let response = try ControlClient(serviceName: name).send(command: "fail")
        #expect(response == .failure("it broke"))
    }

    @Test("an unknown command is a failure response")
    func unknownCommand() throws {
        let name = uniqueServiceName()
        let server = try startServer(name)
        defer { server.stop() }

        let response = try ControlClient(serviceName: name).send(command: "nope")
        #expect(response.ok == false)
        #expect(response.error?.contains("unknown command") == true)
    }

    @Test("many sequential requests on one server all succeed")
    func sequentialRequests() throws {
        let name = uniqueServiceName()
        let server = try startServer(name)
        defer { server.stop() }

        let client = ControlClient(serviceName: name)
        for index in 0..<50 {
            let response = try client.send(command: "echo", params: ["i": .int(index)])
            #expect(response == .success(["i": .int(index)]))
        }
    }

    @Test("a large payload round trips intact")
    func largePayload() throws {
        let name = uniqueServiceName()
        let server = try startServer(name)
        defer { server.stop() }

        let big = String(repeating: "piccolo ", count: 40_000)  // ~320 KB
        let response = try ControlClient(serviceName: name).send(
            command: "echo", params: ["big": .string(big)])
        #expect(response == .success(["big": .string(big)]))
    }

    @Test("several servers with different names coexist")
    func severalServers() throws {
        let nameA = uniqueServiceName()
        let nameB = uniqueServiceName()
        var routerA = ControlRouter()
        routerA.register("who") { _ in "a" }
        var routerB = ControlRouter()
        routerB.register("who") { _ in "b" }
        let serverA = try startServer(nameA, router: routerA)
        let serverB = try startServer(nameB, router: routerB)
        defer {
            serverA.stop()
            serverB.stop()
        }

        #expect(try ControlClient(serviceName: nameA).send(command: "who") == .success("a"))
        #expect(try ControlClient(serviceName: nameB).send(command: "who") == .success("b"))
    }

    @Test("garbage bytes get an invalid-request failure response")
    func garbageRequest() throws {
        let name = uniqueServiceName()
        let server = try startServer(name)
        defer { server.stop() }

        let reply = try ControlClient(serviceName: name).sendRaw(Data("not json".utf8))
        let response = try ControlResponse(decoding: reply)
        #expect(response.ok == false)
        #expect(response.error?.contains("invalid request") == true)
    }

    // MARK: Failure modes

    @Test("with no server running the client fails with a clear no-server error")
    func noServer() {
        let name = uniqueServiceName()
        let error = #expect(throws: ControlError.self) {
            try ControlClient(serviceName: name).send(command: "status")
        }
        #expect(error == .noServer(serviceName: name))
        #expect(error?.errorDescription?.contains("no server") == true)
        #expect(error?.errorDescription?.contains(name) == true)
    }

    @Test("after the server stops the client sees no server again")
    func serverStopped() throws {
        let name = uniqueServiceName()
        let server = try startServer(name)
        let client = ControlClient(serviceName: name)
        #expect(try client.send(command: "echo").ok)

        server.stop()
        #expect(throws: ControlError.noServer(serviceName: name)) {
            try client.send(command: "echo")
        }
    }

    @Test("a second server for the same name fails to start")
    func duplicateName() throws {
        let name = uniqueServiceName()
        let first = try startServer(name)
        defer { first.stop() }

        #expect(throws: ControlError.self) {
            try startServer(name)
        }
        // The first server keeps working.
        #expect(try ControlClient(serviceName: name).send(command: "echo").ok)
    }

    @Test("the name can be reused once the first server stopped")
    func restart() throws {
        let name = uniqueServiceName()
        let first = try startServer(name)
        first.stop()

        let second = try startServer(name)
        defer { second.stop() }
        #expect(try ControlClient(serviceName: name).send(command: "echo").ok)
    }

    @Test("a slow handler makes the client time out")
    func clientTimeout() throws {
        let name = uniqueServiceName()
        let server = try startServer(name)
        defer { server.stop() }

        let client = ControlClient(serviceName: name, timeout: 0.2)
        let started = Date()
        let error = #expect(throws: ControlError.self) {
            try client.send(command: "slow")
        }
        #expect(Date().timeIntervalSince(started) < 0.9)
        guard case .timeout(let timedOutName, let seconds)? = error else {
            Issue.record("expected a timeout error, got \(String(describing: error))")
            return
        }
        #expect(timedOutName == name)
        #expect(seconds == 0.2)
    }

    @Test("the default timeout is five seconds")
    func defaultTimeout() {
        #expect(ControlClient.defaultTimeout == 5)
        #expect(ControlClient(serviceName: "x").timeout == 5)
    }
}
