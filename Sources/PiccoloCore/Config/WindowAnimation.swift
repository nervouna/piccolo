import Foundation

/// How long a window takes to move to its new place. The raw values are the vocabulary of the
/// config file (`animation`).
public enum WindowAnimation: String, Codable, CaseIterable, Sendable {
    case off
    case fast
    case medium
    case slow

    /// The length of the move in seconds: zero for ``off``.
    public var duration: TimeInterval {
        switch self {
        case .off: 0
        case .fast: 0.15
        case .medium: 0.25
        case .slow: 0.4
        }
    }
}
