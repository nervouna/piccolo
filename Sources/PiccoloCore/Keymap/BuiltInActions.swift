import Foundation

/// The sections of the Shortcuts tab's keymap, in the order the tab lists them. The raw value is the
/// section's name on the debug control channel.
public enum KeymapSection: String, CaseIterable, Equatable, Hashable, Sendable {
    case halves
    case quarters
    case thirds
    case other
    case displays
    /// Arrange Grid: one row per grid binding.
    case grids
    case dividers
    case swaps
    /// Custom Areas: one row per custom-frame binding.
    case customAreas

    /// The section an action is listed in.
    public init(of action: Action) {
        switch action {
        case .placeWindow(.preset(let preset)):
            switch preset {
            case .leftHalf, .rightHalf, .topHalf, .bottomHalf: self = .halves
            case .topLeft, .topRight, .bottomLeft, .bottomRight: self = .quarters
            case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds: self = .thirds
            case .maximize, .center: self = .other
            }
        case .placeWindow(.custom): self = .customAreas
        case .restoreWindow: self = .other
        case .moveToDisplay: self = .displays
        case .arrangeGrid: self = .grids
        case .moveDivider: self = .dividers
        case .swapWindow: self = .swaps
        }
    }
}

/// The actions every install lists, bound or not.
public enum BuiltInActions {
    /// The 30 built-in actions in the order of the keymap: the 15 presets, Restore Window, the six
    /// display directions (next, previous, left, right, up, down), then the four directions of Move
    /// Divider and of Swap Window (left, right, up, down).
    public static let all: [Action] =
        [
            Preset.leftHalf, .rightHalf, .topHalf, .bottomHalf,
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds,
            .maximize, .center,
        ].map { Action.placeWindow(.preset($0)) }
        + [Action.restoreWindow]
        + [
            DisplayDirection.next, .previous, .left, .right, .up, .down,
        ].map { Action.moveToDisplay($0) }
        + [Direction.left, .right, .up, .down].map { Action.moveDivider($0) }
        + [Direction.left, .right, .up, .down].map { Action.swapWindow($0) }
}

extension Action {
    /// Whether the action is one of ``BuiltInActions/all``: false only for a grid (`arrangeGrid`) and a
    /// custom frame (`placeWindow(.custom)`), which are layouts the user defines.
    public var isBuiltIn: Bool {
        switch self {
        case .arrangeGrid, .placeWindow(.custom): false
        case .placeWindow(.preset), .moveToDisplay, .moveDivider, .restoreWindow, .swapWindow: true
        }
    }
}
