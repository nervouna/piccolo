import Foundation
import PiccoloCore

/// The kinds of action, as the editor offers them: the first choice for a binding, before
/// the parameters of the kind.
public enum ActionKind: CaseIterable, Hashable, Sendable {
    case placeWindow
    case restoreWindow
    case moveToDisplay
    case arrangeGrid
    case moveDivider
    case swapWindow

    public init(_ action: Action) {
        switch action {
        case .placeWindow: self = .placeWindow
        case .restoreWindow: self = .restoreWindow
        case .moveToDisplay: self = .moveToDisplay
        case .arrangeGrid: self = .arrangeGrid
        case .moveDivider: self = .moveDivider
        case .swapWindow: self = .swapWindow
        }
    }

    /// The name of the kind in the config file's `type` key (`placeWindow`, `moveToDisplay`,
    /// `arrangeGrid`, `moveDivider`, `swapWindow`).
    public var configName: String {
        switch self {
        case .placeWindow: "placeWindow"
        case .restoreWindow: "restoreWindow"
        case .moveToDisplay: "moveToDisplay"
        case .arrangeGrid: "arrangeGrid"
        case .moveDivider: "moveDivider"
        case .swapWindow: "swapWindow"
        }
    }

    /// The name of the kind, in the language of the running app.
    public var title: String {
        title(bundle: .module)
    }

    /// The name of the kind in the language of `bundle` (see ``ActionSummary``).
    public func title(bundle: Bundle) -> String {
        switch self {
        case .placeWindow: String(localized: "Place Window", bundle: bundle)
        case .restoreWindow: String(localized: "Restore Window", bundle: bundle)
        case .moveToDisplay: String(localized: "Move to Display", bundle: bundle)
        case .arrangeGrid: String(localized: "Arrange Grid", bundle: bundle)
        case .moveDivider: String(localized: "Move Divider", bundle: bundle)
        case .swapWindow: String(localized: "Swap Window", bundle: bundle)
        }
    }

    /// The action a binding gets when its kind is switched to this one.
    public var defaultAction: Action {
        switch self {
        case .placeWindow: .placeWindow(.preset(.leftHalf))
        case .restoreWindow: .restoreWindow
        case .moveToDisplay: .moveToDisplay(.next)
        case .arrangeGrid: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))
        case .moveDivider: .moveDivider(.left)
        case .swapWindow: .swapWindow(.left)
        }
    }
}

extension Action {
    /// The default action of a new binding: place the window in the left half.
    public static let newBindingDefault: Action = ActionKind.placeWindow.defaultAction
}
