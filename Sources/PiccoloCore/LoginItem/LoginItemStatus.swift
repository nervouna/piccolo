import Foundation

/// What the system says about starting Piccolo at login.
///
/// The raw value is the name the debug control channel uses.
public enum LoginItemStatus: String, CaseIterable, Sendable, Codable {
    /// Registered and allowed: Piccolo starts at login.
    case enabled
    /// Not a login item.
    case notRegistered
    /// Registered, but the user has to allow it in System Settings (Login Items) before it
    /// starts at login. The system sets this when the user switched Piccolo off there, and the
    /// first time an app registers on some systems.
    case requiresApproval
    /// The system does not know this app as a login item.
    case notFound

    /// Whether Piccolo has asked to be a login item, whether or not the system lets it start yet:
    /// the state the "Launch at login" switch shows as on.
    public var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

/// A login item could not be registered or unregistered. Carries the system's own message.
public struct LoginItemError: Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
