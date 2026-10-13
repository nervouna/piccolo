import Foundation

/// A key press: a macOS virtual key code and a set of modifiers.
public struct Shortcut: Codable, Equatable, Sendable {
    /// macOS virtual key code (`kVK_*`).
    public var keyCode: Int
    public var modifiers: Set<Modifier>

    public init(keyCode: Int, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    /// Modifiers are written sorted by name so that the file does not depend on set order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.sorted { $0.rawValue < $1.rawValue }, forKey: .modifiers)
    }
}

/// A modifier key of a shortcut. The raw value is its name in the file.
public enum Modifier: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
}
