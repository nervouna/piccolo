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
    /// `moveDivider` moved a divider of a group, or found nothing to move.
    case dividerMove(DividerMoveOutcome)
}

/// Why an action could not be run, besides ``ActionPlanningError`` and ``WindowError``, which
/// the executor passes through unchanged.
public enum ActionExecutionError: Error, Equatable, Sendable, LocalizedError {
    /// `moveDivider` was given a resize step that is not a positive, finite number. A loaded
    /// config never holds one; this guards the executor against a caller that does not check.
    case invalidResizeStep(Double)

    public var errorDescription: String? {
        switch self {
        case .invalidResizeStep(let value):
            return "the resize step \(value) is not a positive number"
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
    let groups: LayoutGroupStore

    /// - Parameters:
    ///   - arrangement: Where `arrangeGrid` finds the windows to arrange, and `moveDivider` the
    ///     windows of a group. The default has none, so that `arrangeGrid` has nothing to do.
    ///   - groups: Where `arrangeGrid` records the groups it makes and `moveDivider` finds them. A
    ///     copy of the executor shares it.
    public init(
        window: @escaping WindowProvider,
        displays: @escaping DisplaysProvider,
        arrangement: ArrangementSource = .none,
        groups: LayoutGroupStore = LayoutGroupStore()
    ) {
        self.windowProvider = window
        self.displaysProvider = displays
        self.arrangement = arrangement
        self.groups = groups
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

    /// The groups of windows that were arranged and are still tracked, in display order.
    public var linkedGroups: [LayoutGroups.Entry] {
        groups.entries
    }

    /// Runs `action` on the focused window; `arrangeGrid` runs on the windows on screen, and
    /// `moveDivider` on the group of the focused window.
    ///
    /// - Parameters:
    ///   - onlyPid: Restricts the windows `arrangeGrid` may move to those of this process, and
    ///     `moveDivider` too: a group with a window of another process is dissolved instead of
    ///     moved. The other actions ignore it: they only touch the focused window.
    ///   - resizeStep: The fraction of the display a divider moves by, the loaded config's
    ///     `resizeStep`. Only `moveDivider` uses it.
    /// - Throws: ``ActionExecutionError`` for a `resizeStep` that is not a positive number, before
    ///   anything is touched; ``ActionPlanningError`` for an action that cannot be planned;
    ///   ``ArrangePlannerError`` for a grid that cannot be arranged; ``WindowError`` when a window
    ///   cannot be found, read or changed. A window of an arrangement or a divider move that cannot
    ///   be changed is not an error: it is reported in the outcome, and the other windows are still
    ///   moved.
    public func run(
        _ action: Action, onlyPid: pid_t? = nil, resizeStep: Double = Config.defaultResizeStep
    ) throws -> ActionOutcome {
        switch action {
        case .arrangeGrid(let grid):
            return try arrange(grid, onlyPid: onlyPid)
        case .moveDivider(let direction):
            return try moveDivider(direction, step: resizeStep, onlyPid: onlyPid)
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
