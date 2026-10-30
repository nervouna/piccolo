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
    let records: WindowRecordStore
    /// Moves the windows in small steps before they are placed (see ``WindowAnimator``). Without one
    /// nothing is animated, whatever `ActionSettings.animation` says.
    var animator: WindowAnimator?

    /// - Parameters:
    ///   - arrangement: Where `arrangeGrid` finds the windows to arrange, and `moveDivider` the
    ///     windows of a group. The default has none, so that `arrangeGrid` has nothing to do.
    ///   - groups: Where `arrangeGrid` records the groups it makes and `moveDivider` finds them. A
    ///     copy of the executor shares it.
    ///   - records: Where single-window actions, arrangements and divider moves note the windows they
    ///     changed, and `restoreWindow` and the cycling presets read them. A copy of the executor
    ///     shares it.
    ///   - animator: What animates the windows when the settings ask for it. The default has none, so
    ///     that an executor built without one places every window at once, like ``live`` does with
    ///     `ActionSettings.animation` set to `off`.
    public init(
        window: @escaping WindowProvider,
        displays: @escaping DisplaysProvider,
        arrangement: ArrangementSource = .none,
        groups: LayoutGroupStore = LayoutGroupStore(),
        records: WindowRecordStore = WindowRecordStore(),
        animator: WindowAnimator? = nil
    ) {
        self.windowProvider = window
        self.displaysProvider = displays
        self.arrangement = arrangement
        self.groups = groups
        self.records = records
        self.animator = animator
    }

    /// The focused window of the frontmost application, on the attached displays, arranging the
    /// windows on screen in the order the focus tracker saw them focused.
    ///
    /// The first use starts the focus tracker, which keeps listening for the rest of the process's
    /// life.
    public static let live = ActionExecutor(
        window: { try FocusedWindow.current() },
        displays: { Screens.currentDisplays() },
        arrangement: .live,
        animator: WindowAnimator())

    /// The windows focused so far, most recent first. Empty until the tracker has seen a window.
    public var focusHistory: [WindowID] {
        arrangement.history().order
    }

    /// What Piccolo remembers of the windows it moved, ordered by window number.
    public var windowRecords: [(window: WindowID, record: WindowRecord)] {
        records.entries
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
    ///   - settings: The settings of the config in effect. `moveDivider` uses its `resizeStep`,
    ///     `arrangeGrid` its `gridFillOrder`, and every action its `animation`: the windows glide to
    ///     their new frames over its duration and are then placed exactly as without animation (see
    ///     ``WindowAnimator``).
    /// - Throws: ``ActionExecutionError`` for a `resizeStep` that is not a positive number, before
    ///   anything is touched; ``ActionPlanningError`` for an action that cannot be planned;
    ///   ``ArrangePlannerError`` for a grid that cannot be arranged; ``WindowError`` when a window
    ///   cannot be found, read or changed. A window of an arrangement or a divider move that cannot
    ///   be changed is not an error: it is reported in the outcome, and the other windows are still
    ///   moved.
    public func run(
        _ action: Action, onlyPid: pid_t? = nil, settings: ActionSettings = .default
    ) throws -> ActionOutcome {
        switch action {
        case .arrangeGrid(let grid):
            return try arrange(grid, onlyPid: onlyPid, settings: settings)
        case .moveDivider(let direction):
            return try moveDivider(direction, onlyPid: onlyPid, settings: settings)
        case .placeWindow, .moveToDisplay, .restoreWindow:
            break
        }

        let planning = try planSingleWindow(action)
        switch planning.plan {
        case .nothingToDo:
            // A restore with nothing to go back to: the record, if any, is stale.
            if case .restoreWindow = action, let id = planning.windowID {
                records.clear(id)
            }
            return .nothingToDo
        case .place(let target, let visibleFrame):
            glide(
                [AnimatedWindow(window: planning.window, start: planning.frame, target: target)],
                settings: settings, displays: planning.displays)
            let achieved = try FrameSetter.apply(target, to: planning.window, within: visibleFrame)
            if let id = planning.windowID {
                if case .restoreWindow = action {
                    records.clear(id)
                } else {
                    records.recordChange(
                        of: id, from: planning.frame, to: achieved,
                        cycle: Self.cycleStep(of: action, target: target, visibleFrame: visibleFrame))
                }
            }
            return .placed(target: target, achieved: achieved)
        }
    }

    /// A single-window action planned: the window it acts on, where that is now, the displays and the
    /// plan. Reading only; ``run(_:onlyPid:settings:)`` and ``destinations(for:onlyPid:settings:)``
    /// both start from it.
    struct SingleWindowPlanning {
        var window: any WindowFrameAccess
        var frame: CGRect
        /// The window's number, when it has one.
        var windowID: WindowID?
        var displays: [Display]
        var plan: ActionPlan
    }

    /// The preset and step a `placeWindow` of a cycling preset placed the window at.
    static func cycleStep(of action: Action, target: CGRect, visibleFrame: CGRect) -> CycleStep? {
        guard case .placeWindow(.preset(let preset)) = action, PresetCycle.cycles(preset),
            let step = PresetCycle.step(of: preset, matching: target, in: visibleFrame)
        else { return nil }
        return CycleStep(preset: preset, step: step)
    }

    func planSingleWindow(_ action: Action) throws -> SingleWindowPlanning {
        let window = try windowProvider()
        let windowFrame = try window.frame()
        let displays = try displaysProvider()
        let windowID = window.windowID
        let record = windowID.flatMap { records.record(for: $0) }
        let plan = try ActionPlanner.plan(
            action, windowFrame: windowFrame, displays: displays, record: record)
        return SingleWindowPlanning(
            window: window, frame: windowFrame, windowID: windowID, displays: displays, plan: plan)
    }
}
