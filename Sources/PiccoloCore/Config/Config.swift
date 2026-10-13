import Foundation

/// The user's configuration: what each shortcut does and the linked-resize step.
///
/// The JSON shape of this type is the on-disk format read by `ConfigStore`.
/// Key names are part of that contract.
public struct Config: Codable, Equatable, Sendable {
    /// The only format version this build reads and writes.
    public static let currentVersion = 1

    /// Linked-resize step when the file does not set one: 5% of the screen.
    public static let defaultResizeStep = 0.05

    /// Format version of the file.
    public var version: Int
    /// Fraction of the screen a linked resize moves a divider by. Valid range: `0 < resizeStep <= 0.5`.
    public var resizeStep: Double
    public var bindings: [Binding]

    public init(
        version: Int = Config.currentVersion,
        resizeStep: Double = Config.defaultResizeStep,
        bindings: [Binding] = []
    ) {
        self.version = version
        self.resizeStep = resizeStep
        self.bindings = bindings
    }

    /// Version 1, default step, no bindings.
    public static let `default` = Config()
}

/// One action bound to an optional shortcut.
public struct Binding: Codable, Equatable, Sendable {
    /// Identifies the binding. Must be unique within a config.
    public var id: UUID
    public var action: Action
    /// `nil` when the binding has no shortcut. The key is then omitted from the file.
    public var shortcut: Shortcut?

    public init(id: UUID = UUID(), action: Action, shortcut: Shortcut? = nil) {
        self.id = id
        self.action = action
        self.shortcut = shortcut
    }
}
