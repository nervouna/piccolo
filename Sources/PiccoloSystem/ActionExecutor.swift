import CoreGraphics
import Foundation
import PiccoloCore

/// What running an action did.
public enum ActionOutcome: Equatable, Sendable {
    /// The window was sent to `target`; `achieved` is the frame read back afterwards. They differ
    /// when the window refused the size, or was shifted back inside the display.
    case placed(target: CGRect, achieved: CGRect)
    /// The action needed no change, for example `moveToDisplay` with a single display.
    case nothingToDo
}

/// Why an action could not be run, besides ``ActionPlanningError`` and ``WindowError``, which
/// the executor passes through unchanged.
public enum ActionExecutionError: Error, Equatable, Sendable, LocalizedError {
    /// The action kind exists in the model but nothing executes it yet.
    case notImplemented(actionType: String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let actionType):
            return "the \(actionType) action is not implemented yet"
        }
    }
}

/// Runs an `Action` end to end: focused window, plan, apply, outcome.
///
/// The window and the displays come from closures, so that the whole flow runs against fakes in
/// tests. ``live`` reads the real focused window and screens.
///
/// A run is synchronous and blocks on Accessibility calls, so it belongs off the main thread.
public struct ActionExecutor: Sendable {
    /// Finds the window to act on, fresh for every run.
    public typealias WindowProvider = @Sendable () throws -> any WindowFrameAccess
    /// Lists the displays in canonical coordinates, the primary display first.
    public typealias DisplaysProvider = @Sendable () throws -> [Display]

    private let windowProvider: WindowProvider
    private let displaysProvider: DisplaysProvider

    public init(window: @escaping WindowProvider, displays: @escaping DisplaysProvider) {
        self.windowProvider = window
        self.displaysProvider = displays
    }

    /// The focused window of the frontmost application, on the attached displays.
    public static let live = ActionExecutor(
        window: { try FocusedWindow.current() },
        displays: { Screens.currentDisplays() })

    /// Runs `action` on the focused window.
    ///
    /// - Throws: ``ActionExecutionError/notImplemented(actionType:)`` for `arrangeGrid` and
    ///   `moveDivider`, before the window is touched; ``ActionPlanningError`` for an action that
    ///   cannot be planned; ``WindowError`` when the window cannot be found, read or changed.
    public func run(_ action: Action) throws -> ActionOutcome {
        switch action {
        case .arrangeGrid:
            throw ActionExecutionError.notImplemented(actionType: "arrangeGrid")
        case .moveDivider:
            throw ActionExecutionError.notImplemented(actionType: "moveDivider")
        case .placeWindow, .moveToDisplay:
            break
        }

        let window = try windowProvider()
        let windowFrame = try window.frame()
        let plan = try ActionPlanner.plan(action, windowFrame: windowFrame, displays: try displaysProvider())
        switch plan {
        case .nothingToDo:
            return .nothingToDo
        case .place(let target, let visibleFrame):
            let achieved = try FrameSetter.apply(target, to: window, within: visibleFrame)
            return .placed(target: target, achieved: achieved)
        }
    }
}
