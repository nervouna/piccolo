import Foundation
import Testing

@testable import PiccoloControl

@Suite("Control messages")
struct ControlMessageTests {
    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    // MARK: Request

    @Test("a request without params encodes an empty params object")
    func requestEncodingEmptyParams() throws {
        let data = try ControlRequest(command: "status").encoded()
        #expect(text(data) == #"{"command":"status","params":{}}"#)
    }

    @Test("a request with params encodes them with sorted keys")
    func requestEncodingParams() throws {
        let request = ControlRequest(
            command: "window.setFocusedFrame",
            params: ["y": 200, "x": 200, "width": 900, "height": 600])
        #expect(
            text(try request.encoded())
                == #"{"command":"window.setFocusedFrame","params":{"height":600,"width":900,"x":200,"y":200}}"#
        )
    }

    @Test("a request decodes from its wire form")
    func requestDecoding() throws {
        let data = Data(#"{"command":"echo","params":{"a":1,"b":[true,null]}}"#.utf8)
        let request = try ControlRequest(decoding: data)
        #expect(request.command == "echo")
        #expect(request.params == ["a": .int(1), "b": [true, nil]])
    }

    @Test("missing or null params decode as empty")
    func requestDecodingWithoutParams() throws {
        #expect(try ControlRequest(decoding: Data(#"{"command":"status"}"#.utf8)).params == [:])
        #expect(
            try ControlRequest(decoding: Data(#"{"command":"status","params":null}"#.utf8)).params
                == [:])
    }

    @Test(
        "malformed requests are rejected",
        arguments: [
            "",
            "not json",
            "[]",
            #"{"params":{}}"#,
            #"{"command":3}"#,
            #"{"command":"x","params":[1]}"#,
            #"{"command":"x","params":"p"}"#,
        ])
    func requestDecodingFailures(json: String) {
        #expect(throws: (any Error).self) {
            try ControlRequest(decoding: Data(json.utf8))
        }
    }

    @Test("a request survives an encode/decode round trip")
    func requestRoundTrip() throws {
        let request = ControlRequest(command: "c", params: ["k": ["nested": 1.5]])
        #expect(try ControlRequest(decoding: request.encoded()) == request)
    }

    // MARK: Response

    @Test("a success response carries ok and result")
    func successEncoding() throws {
        let response = ControlResponse.success(["frame": ["x": 1]])
        #expect(text(try response.encoded()) == #"{"ok":true,"result":{"frame":{"x":1}}}"#)
    }

    @Test("a success response without a result omits the key")
    func successWithoutResult() throws {
        #expect(text(try ControlResponse.success().encoded()) == #"{"ok":true}"#)
    }

    @Test("a failure response carries ok false and the message")
    func failureEncoding() throws {
        let response = ControlResponse.failure("boom")
        #expect(text(try response.encoded()) == #"{"error":"boom","ok":false}"#)
    }

    @Test(
        "responses decode from their wire form",
        arguments: [
            (#"{"ok":true,"result":[1,2]}"#, ControlResponse.success([1, 2])),
            (#"{"ok":true,"result":"s"}"#, ControlResponse.success("s")),
            (#"{"ok":true}"#, ControlResponse.success()),
            (#"{"ok":true,"result":null}"#, ControlResponse.success()),
            (#"{"ok":false,"error":"no"}"#, ControlResponse.failure("no")),
        ])
    func responseDecoding(json: String, expected: ControlResponse) throws {
        #expect(try ControlResponse(decoding: Data(json.utf8)) == expected)
    }

    @Test(
        "malformed responses are rejected",
        arguments: ["", "nope", "[]", #"{"result":1}"#, #"{"ok":"yes"}"#])
    func responseDecodingFailures(json: String) {
        #expect(throws: (any Error).self) {
            try ControlResponse(decoding: Data(json.utf8))
        }
    }

    @Test("a response survives an encode/decode round trip")
    func responseRoundTrip() throws {
        for response in [
            ControlResponse.success(["a": [1, "b", nil]]),
            ControlResponse.success(),
            ControlResponse.failure("x"),
        ] {
            #expect(try ControlResponse(decoding: response.encoded()) == response)
        }
    }
}
