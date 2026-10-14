import Foundation

/// The settings of the config that an action needs when it runs. Built from the config in effect
/// when a shortcut is pressed, or when a control command runs an action.
public struct ActionSettings: Equatable, Sendable {
    /// Fraction of the screen a linked resize moves a divider by.
    public var resizeStep: Double
    /// How long a window takes to move to its new place.
    public var animation: WindowAnimation
    /// Where the windows of a grid go when there are fewer windows than cells.
    public var gridFillOrder: GridFillOrder

    public init(
        resizeStep: Double = Config.defaultResizeStep,
        animation: WindowAnimation = Config.defaultAnimation,
        gridFillOrder: GridFillOrder = Config.defaultGridFillOrder
    ) {
        self.resizeStep = resizeStep
        self.animation = animation
        self.gridFillOrder = gridFillOrder
    }

    /// The action settings of `config`: the fields an action reads, not the bindings.
    public init(_ config: Config) {
        self.init(
            resizeStep: config.resizeStep,
            animation: config.animation,
            gridFillOrder: config.gridFillOrder)
    }

    /// The settings of `Config.default`.
    public static let `default` = ActionSettings(Config.default)
}
