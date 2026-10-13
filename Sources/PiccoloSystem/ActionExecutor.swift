import CoreGraphics
import Foundation
import PiccoloCore

/// What running an action did.
public enum ActionOutcome: Equatable, Sendable {
    /// The window was sent to `target`; `achieved` is the frame read back afterwards. They differ
    /// when the window refused the size, or was shifted back inside the display.
    case placed(target: CGRect, achieved: CGRect)
    /// The action needed no change, for example `moveToDisplay` with a single display, or
    /// `arrangeGrid` with no window to arrange.
    case nothingToDo
    /// `arrangeGrid` sent windows to their cells, or tried to.
    case arranged(ArrangeOutcome)
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
/// The window, the displays and the windows to arrange come from closures, so that the whole flow
/// runs against fakes in tests. ``live`` reads the real focused window, screens and windows.
///
/// A run is synchronous and blocks on Accessibility calls, so it belongs off the main thread.
public struct ActionExecutor: Sendable {
    /// Finds the window to act on, fresh for every run.
    public typealias WindowProvider = @Sendable () throws -> any WindowFrameAccess
    /// Lists the displays in canonical coordinates, the primary display first.
    public typealias DisplaysProvider = @Sendable () throws -> [Display]

    let windowProvider: WindowProvider
    let displaysProvider: DisplaysProvider
    let arrangement: ArrangementSource

    /// - Parameter arrangement: Where `arrangeGrid` finds the windows to arrange. The default has
    ///   none, so that `arrangeGrid` has nothing to do.
    public init(
        window: @escaping WindowProvider,
        displays: @escaping DisplaysProvider,
        arrangement: ArrangementSource = .none
    ) {
        self.windowProvider = window
        self.displaysProvider = displays
        self.arrangement = arrangement
    }

    /// The focused window of the frontmost application, on the attached displays, arranging the
    /// windows on screen in the order the focus tracker saw them focused.
    ///
    /// The first use starts the focus tracker, which keeps listening for the rest of the process's
    /// life.
    public static let live = ActionExecutor(
        window: { try FocusedWindow.current() },
        displays: { Screens.currentDisplays() },
        arrangement: .live)

    /// The windows focused so far, most recent first. Empty until the tracker has seen a window.
    public var focusHistory: [WindowID] {
        arrangement.history().order
    }

    /// Runs `action` on the focused window; `arrangeGrid` runs on the windows on screen.
    ///
    /// - Parameter onlyPid: Restricts the windows `arrangeGrid` may move to those of this process.
    ///   The other actions ignore it: they only touch the focused window.
    /// - Throws: ``ActionExecutionError/notImplemented(actionType:)`` for `moveDivider`, before
    ///   anything is touched; ``ActionPlanningError`` for an action that cannot be planned;
    ///   ``ArrangePlannerError`` for a grid that cannot be arranged; ``WindowError`` when a window
    ///   cannot be found, read or changed. A window of an arrangement that cannot be changed is not
    ///   an error: it is reported in the outcome, and the other windows are still moved.
    public func run(_ action: Action, onlyPid: pid_t? = nil) throws -> ActionOutcome {
        switch action {
        case .arrangeGrid(let grid):
            return try arrange(grid, onlyPid: onlyPid)
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
