import Foundation

/// The user's configuration: what each shortcut does, the linked-resize step, the window animation,
/// the grid fill order, whether a held shortcut shows its destination and the window gap.
///
/// The JSON shape of this type is the on-disk format read by `ConfigStore`.
/// Key names are part of that contract.
public struct Config: Codable, Equatable, Sendable {
    /// The only format version this build reads and writes.
    public static let currentVersion = 1

    /// Linked-resize step when the file does not set one: 5% of the screen.
    public static let defaultResizeStep = 0.05
    /// Window animation when the file does not set one.
    public static let defaultAnimation = WindowAnimation.medium
    /// Grid fill order when the file does not set one.
    public static let defaultGridFillOrder = GridFillOrder.columns
    /// Destination preview when the file does not set one.
    public static let defaultDestinationPreview = true
    /// Window gap when the file does not set one: 16 points.
    public static let defaultGap = WindowGap.default

    /// Format version of the file.
    public var version: Int
    /// Fraction of the screen a linked resize moves a divider by. Valid range: `0 < resizeStep <= 0.5`.
    public var resizeStep: Double
    /// How long a window takes to move to its new place. File key `animation`.
    public var animation: WindowAnimation
    /// Where the windows of a grid go when there are fewer windows than cells. File key `gridFillOrder`.
    public var gridFillOrder: GridFillOrder
    /// Whether holding a shortcut shows where the windows will go before they move. File key
    /// `destinationPreview`.
    public var destinationPreview: Bool
    /// The space, in points, between windows Piccolo places and between them and the edges of the
    /// screen (``WindowGap``). An integer from 0 to 64. File key `gap`.
    public var gap: Int
    public var bindings: [KeyBinding]

    public init(
        version: Int = Config.currentVersion,
        resizeStep: Double = Config.defaultResizeStep,
        animation: WindowAnimation = Config.defaultAnimation,
        gridFillOrder: GridFillOrder = Config.defaultGridFillOrder,
        destinationPreview: Bool = Config.defaultDestinationPreview,
        gap: Int = Config.defaultGap,
        bindings: [KeyBinding] = []
    ) {
        self.version = version
        self.resizeStep = resizeStep
        self.animation = animation
        self.gridFillOrder = gridFillOrder
        self.destinationPreview = destinationPreview
        self.gap = gap
        self.bindings = bindings
    }

    /// Version 1, the default settings, no bindings.
    public static let `default` = Config()
}

/// One action bound to an optional shortcut.
public struct KeyBinding: Codable, Equatable, Sendable {
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
