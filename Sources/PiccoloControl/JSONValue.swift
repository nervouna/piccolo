import Foundation

/// A JSON document held as a value, used for request params and response results so
/// that the protocol can carry arbitrary payloads without `Any`.
public enum JSONValue: Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Accessors

extension JSONValue {
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// The integer value. A double with no fractional part converts losslessly.
    public var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(exactly: value)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let value):
            return Double(value)
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// The member `key` of an object, or nil for a missing key or a non-object.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not a JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Literals

extension JSONValue:
    ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Text and Codable bridging

extension JSONValue {
    /// Parses JSON text, including bare scalars.
    public static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Parses JSON text that must be an object.
    public static func parseObject(_ text: String) throws -> [String: JSONValue] {
        guard case .object(let object) = try parse(text) else {
            throw ControlCommandError.invalidParams("expected a JSON object")
        }
        return object
    }

    /// The compact form with sorted keys and unescaped slashes, so that equal values
    /// always serialize to the same text.
    public func serialized() throws -> String {
        String(decoding: try ControlJSON.encoder().encode(self), as: UTF8.self)
    }

    /// Converts any `Encodable` value.
    public init<T: Encodable>(encoding value: T) throws {
        let data = try ControlJSON.encoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Converts this value into a `Decodable` type.
    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        let data = try ControlJSON.encoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// Decodes request params into a typed value. A mismatch throws a
    /// ``ControlCommandError/invalidParams(_:)`` that names the offending parameter.
    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        do {
            return try JSONValue.object(self).decode(T.self)
        } catch let error as DecodingError {
            throw ControlCommandError.invalidParams(Self.describe(error))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, _):
            return "missing parameter '\(key.stringValue)'"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "parameter '\(path(context.codingPath))' has the wrong type"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return "\(error)"
        }
    }
}
