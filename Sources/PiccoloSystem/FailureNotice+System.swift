import PiccoloCore

/// What a hotkey run produced, mapped to the notice the user gets, if any.
extension FailureNotice {
    /// The notice for an error thrown by a run. `nil` for errors that are not the user's to fix at
    /// the keyboard: a config error (`ActionExecutionError`, `ActionPlanningError`) is reported in
    /// Settings, and anything unknown stays in the log.
    public init?(error: any Error) {
        switch error {
        case let error as WindowError:
            self.init(windowError: error)
        case let error as ArrangePlannerError:
            self.init(arrangePlannerError: error)
        default:
            return nil
        }
    }

    public init(windowError: WindowError) {
        switch windowError {
        case .notTrusted: self = .accessibilityNotGranted
        case .noFrontmostApplication, .noFocusedWindow: self = .noWindow
        case .ownWindow: self = .ownWindow
        case .windowGone, .attributeNotSettable, .accessibility: self = .windowNotChangeable
        }
    }

    /// The notice for what `action` produced. `nil` for a success, and for a `placeWindow` that had
    /// nothing to do.
    public init?(outcome: ActionOutcome, for action: Action) {
        switch outcome {
        case .placed:
            return nil
        case .nothingToDo:
            switch action {
            case .moveToDisplay: self = .noOtherDisplay
            case .arrangeGrid: self = .nothingToArrange
            case .restoreWindow: self = .nothingToRestore
            case .placeWindow, .moveDivider, .swapWindow: return nil
            }
        case .arranged(let arranged):
            guard arranged.windows.contains(where: \.failed) else { return nil }
            self = .windowNotChangeable
        case .dividerMove(.moved(let moved)):
            guard moved.windows.contains(where: \.failed) else { return nil }
            self = .windowNotChangeable
        case .dividerMove(.nothingToDo(let reason)):
            switch reason {
            case .noFocusedWindow: self = .noWindow
            case .noGroup: self = .noGroup
            case .dissolved: self = .dissolved
            case .cannotMove: self = .cannotMove
            }
        case .swap(.swapped(_, let windows)):
            guard windows.contains(where: \.failed) else { return nil }
            self = .windowNotChangeable
        case .swap(.nothingToDo(let reason)):
            switch reason {
            case .noFocusedWindow: self = .noWindow
            case .noGroup: self = .noGroup
            case .dissolved: self = .dissolved
            case .noNeighbour: self = .noNeighbour
            }
        }
    }
}

extension ArrangedWindow {
    fileprivate var failed: Bool {
        if case .failed = result { return true }
        return false
    }
}
