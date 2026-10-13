import Foundation
import Testing

@testable import PiccoloControl

@Suite("ControlRouter")
struct ControlRouterTests {
    private struct SizeParams: Decodable {
        var width: Double
        var height: Double
    }

    private func makeRouter() -> ControlRouter {
        var router = ControlRouter()
        router.register("echo") { params in .object(params) }
        router.register("area") { params in
            let size = try params.decode(SizeParams.self)
            return .double(size.width * size.height)
        }
        router.register("fail") { _ in throw ControlCommandError.failed("it broke") }
        router.register("crash") { _ in throw Boom() }
        return router
    }

    private struct Boom: Error {}

    @Test("a registered command is dispatched with its params")
    func dispatch() {
        let response = makeRouter().handle(ControlRequest(command: "echo", params: ["a": 1]))
        #expect(response == .success(["a": 1]))
    }

    @Test("an unknown command fails and names the command")
    func unknownCommand() {
        let response = makeRouter().handle(ControlRequest(command: "nope"))
        #expect(response.ok == false)
        #expect(response.error?.contains("unknown command") == true)
        #expect(response.error?.contains("nope") == true)
    }

    @Test("a handler error becomes a failure response with its message")
    func handlerError() {
        let response = makeRouter().handle(ControlRequest(command: "fail"))
        #expect(response == .failure("it broke"))
    }

    @Test("an arbitrary handler error still produces a failure response")
    func arbitraryError() {
        let response = makeRouter().handle(ControlRequest(command: "crash"))
        #expect(response.ok == false)
        #expect(response.error?.isEmpty == false)
    }

    @Test("params decode into a typed value")
    func typedParams() {
        let response = makeRouter().handle(
            ControlRequest(command: "area", params: ["width": 3, "height": 4.5]))
        #expect(response == .success(.double(13.5)))
    }

    @Test("a missing param is reported by name")
    func missingParam() {
        let response = makeRouter().handle(ControlRequest(command: "area", params: ["width": 3]))
        #expect(response.ok == false)
        #expect(response.error?.contains("invalid params") == true)
        #expect(response.error?.contains("height") == true)
    }

    @Test("a param of the wrong type is reported by name")
    func wrongTypeParam() {
        let response = makeRouter().handle(
            ControlRequest(command: "area", params: ["width": "wide", "height": 1]))
        #expect(response.ok == false)
        #expect(response.error?.contains("invalid params") == true)
        #expect(response.error?.contains("width") == true)
    }

    @Test("registering a command twice replaces the first handler")
    func reRegister() {
        var router = ControlRouter()
        router.register("c") { _ in 1 }
        router.register("c") { _ in 2 }
        #expect(router.handle(ControlRequest(command: "c")) == .success(2))
    }

    @Test("the registered commands are listed in sorted order")
    func commandList() {
        #expect(makeRouter().commands == ["area", "crash", "echo", "fail"])
    }
}
