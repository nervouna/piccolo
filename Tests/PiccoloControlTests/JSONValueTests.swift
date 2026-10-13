import CoreGraphics
import Foundation
import Testing

@testable import PiccoloControl

@Suite("JSONValue")
struct JSONValueTests {
    private func roundTrip(_ value: JSONValue) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    @Test("every case survives an encode/decode round trip")
    func roundTripAllCases() throws {
        let value: JSONValue = [
            "null": nil,
            "bool": true,
            "int": 42,
            "negative": -7,
            "double": 1.5,
            "string": "héllo \"quoted\" /slash",
            "array": [1, "two", false, nil],
            "object": ["nested": ["deep": 3.25]],
        ]
        #expect(try roundTrip(value) == value)
    }

    @Test(
        "numbers decode to int when integral and to double otherwise",
        arguments: [
            ("200", JSONValue.int(200)),
            ("-3", JSONValue.int(-3)),
            ("1.5", JSONValue.double(1.5)),
            ("0.25", JSONValue.double(0.25)),
            ("true", JSONValue.bool(true)),
            ("false", JSONValue.bool(false)),
            ("null", JSONValue.null),
            ("\"x\"", JSONValue.string("x")),
        ])
    func decodeScalars(text: String, expected: JSONValue) throws {
        #expect(try JSONValue.parse(text) == expected)
    }

    @Test("the compact serialization has sorted keys and no escaped slashes")
    func serialization() throws {
        let value: JSONValue = ["b": 1, "a": "x/y", "c": [true, nil]]
        #expect(try value.serialized() == #"{"a":"x/y","b":1,"c":[true,null]}"#)
    }

    @Test("an integral double is written without a fraction")
    func integralDoubleHasNoFraction() throws {
        #expect(try JSONValue.double(200).serialized() == "200")
        #expect(try JSONValue.double(200.5).serialized() == "200.5")
    }

    @Test("accessors convert between int and double only when lossless")
    func accessors() {
        #expect(JSONValue.int(3).doubleValue == 3.0)
        #expect(JSONValue.double(3.0).intValue == 3)
        #expect(JSONValue.double(3.5).intValue == nil)
        #expect(JSONValue.string("3").doubleValue == nil)
        #expect(JSONValue.bool(true).boolValue == true)
        #expect(JSONValue.string("a").stringValue == "a")
        #expect(JSONValue.array([1]).arrayValue == [.int(1)])
        #expect(JSONValue.object(["k": 1]).objectValue == ["k": .int(1)])
        #expect(JSONValue.object(["k": 1])["k"] == .int(1))
        #expect(JSONValue.object(["k": 1])["missing"] == nil)
        #expect(JSONValue.int(1)["k"] == nil)
    }

    @Test("parseObject accepts an object and rejects everything else")
    func parseObject() throws {
        #expect(try JSONValue.parseObject(#"{"a":1,"b":"x"}"#) == ["a": .int(1), "b": .string("x")])
        #expect(try JSONValue.parseObject("{}") == [:])
        #expect(throws: (any Error).self) { try JSONValue.parseObject("[1,2]") }
        #expect(throws: (any Error).self) { try JSONValue.parseObject("3") }
        #expect(throws: (any Error).self) { try JSONValue.parseObject("{not json") }
        #expect(throws: (any Error).self) { try JSONValue.parseObject("") }
    }

    // MARK: Codable bridge

    private struct Sample: Codable, Equatable {
        var name: String
        var count: Int
        var ratio: Double
        var tags: [String]
    }

    @Test("a Codable value converts to JSONValue and back")
    func codableBridge() throws {
        let sample = Sample(name: "n", count: 3, ratio: 0.5, tags: ["a", "b"])
        let value = try JSONValue(encoding: sample)
        #expect(value == ["name": "n", "count": 3, "ratio": 0.5, "tags": ["a", "b"]])
        #expect(try value.decode(Sample.self) == sample)
    }

    @Test("decoding a value of the wrong shape throws")
    func codableBridgeMismatch() {
        #expect(throws: (any Error).self) {
            try JSONValue.object(["name": 1]).decode(Sample.self)
        }
    }

    // MARK: CGRect

    @Test("a CGRect maps to x, y, width and height")
    func rectToJSON() throws {
        let value = JSONValue(rect: CGRect(x: 200, y: -50.5, width: 900, height: 600))
        #expect(try value.serialized() == #"{"height":600,"width":900,"x":200,"y":-50.5}"#)
    }

    @Test("a JSON object maps back to a CGRect")
    func rectFromJSON() {
        let value: JSONValue = ["x": 1, "y": 2.5, "width": 30, "height": 40]
        #expect(value.rectValue == CGRect(x: 1, y: 2.5, width: 30, height: 40))
    }

    @Test("a malformed rect object yields nil")
    func rectFromMalformedJSON() {
        #expect(JSONValue.object(["x": 1, "y": 2, "width": 3]).rectValue == nil)
        #expect(JSONValue.object(["x": 1, "y": 2, "width": 3, "height": "4"]).rectValue == nil)
        #expect(JSONValue.string("rect").rectValue == nil)
    }
}
