import PiccoloCore

/// The four kinds of action, as the editor offers them: the first choice for a binding, before
/// the parameters of the kind.
public enum ActionKind: CaseIterable, Hashable, Sendable {
    case placeWindow
    case moveToDisplay
    case arrangeGrid
    case moveDivider

    public init(_ action: Action) {
        switch action {
        case .placeWindow: self = .placeWindow
        case .moveToDisplay: self = .moveToDisplay
        case .arrangeGrid: self = .arrangeGrid
        case .moveDivider: self = .moveDivider
        }
    }

    public var title: String {
        switch self {
        case .placeWindow: "Place Window"
        case .moveToDisplay: "Move to Display"
        case .arrangeGrid: "Arrange Grid"
        case .moveDivider: "Move Divider"
        }
    }

    /// The action a binding gets when its kind is switched to this one.
    public var defaultAction: Action {
        switch self {
        case .placeWindow: .placeWindow(.preset(.leftHalf))
        case .moveToDisplay: .moveToDisplay(.next)
        case .arrangeGrid: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))
        case .moveDivider: .moveDivider(.left)
        }
    }
}

extension Action {
    /// The default action of a new binding: place the window in the left half.
    public static let newBindingDefault: Action = ActionKind.placeWindow.defaultAction
}
