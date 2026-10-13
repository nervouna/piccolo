import Foundation

/// JSON settings shared by everything that writes control messages or CLI output.
enum ControlJSON {
    /// Compact output with sorted keys and unescaped slashes.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// A command sent to a control server: `{"command": String, "params": Object}`.
public struct ControlRequest: Codable, Sendable, Equatable {
    public var command: String
    public var params: [String: JSONValue]

    public init(command: String, params: [String: JSONValue] = [:]) {
        self.command = command
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case params
    }

    /// `params` may be missing or null, both mean "no params". Anything but an
    /// object is rejected.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        params = try container.decodeIfPresent([String: JSONValue].self, forKey: .params) ?? [:]
    }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(ControlRequest.self, from: data)
    }

    public func encoded() throws -> Data {
        try ControlJSON.encoder().encode(self)
    }
}

/// A server's answer: `{"ok": Bool, "result": Any?, "error": String?}`.
///
/// A successful response may omit `result`. A failed one carries `error`.
public struct ControlResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var result: JSONValue?
    public var error: String?

    public init(ok: Bool, result: JSONValue? = nil, error: String? = nil) {
        self.ok = ok
        self.result = result
        self.error = error
    }

    /// A null result is the same as no result.
    public static func success(_ result: JSONValue? = nil) -> ControlResponse {
        ControlResponse(ok: true, result: result == .null ? nil : result)
    }

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, error: message)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case result
        case error
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        // `"result": null` and a missing result both mean "no result".
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        if result == .null { result = nil }
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(ControlResponse.self, from: data)
    }

    public func encoded() throws -> Data {
        try ControlJSON.encoder().encode(self)
    }
}
