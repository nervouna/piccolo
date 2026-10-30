import CoreGraphics
import Foundation
import PiccoloCore

/// A frame an action would send a window to.
public struct Destination: Equatable, Sendable {
    /// In canonical coordinates.
    public var frame: CGRect
    /// The window the frame is for. Known for an arrangement and a divider move, which act on windows
    /// other than the focused one; `nil` for the focused window of a single-window action.
    public var window: WindowID?

    public init(frame: CGRect, window: WindowID? = nil) {
        self.frame = frame
        self.window = window
    }
}

extension ActionExecutor {
    /// Where `action` would send windows, planned the way the run plans it and without sending any:
    /// no window is changed, no group is recorded, updated or dissolved. This is what the destination
    /// preview shows while a shortcut is held.
    ///
    /// - `placeWindow`, `moveToDisplay` and `restoreWindow`: the target frame of the focused window
    ///   (for a cycling preset, the next step); none when there is nothing to do (`moveToDisplay` with
    ///   one display, `restoreWindow` with nothing to restore). Planning only reads the window records.
    /// - `arrangeGrid`: the cell of every window of the arrangement, in cell order (the most recently
    ///   focused window first), each with its window; none when there is no window to arrange.
    /// - `moveDivider`: the frame of every window of the focused window's group after the move, in cell
    ///   order, each with its window. None when there is no group, when the group no longer holds (the
    ///   run dissolves it, this does not) or when the divider cannot move.
    ///
    /// Like a run, it reads the focused window and the windows on screen, which can take a while, so it
    /// belongs off the main thread, on the queue the actions run on. The parameters mean what they
    /// mean for ``run(_:onlyPid:settings:)``.
    ///
    /// - Throws: what the run would throw while planning: ``ActionPlanningError``,
    ///   ``ArrangePlannerError``, ``ActionExecutionError`` and ``WindowError``.
    public func destinations(
        for action: Action, onlyPid: pid_t? = nil, settings: ActionSettings = .default
    ) throws -> [Destination] {
        switch action {
        case .arrangeGrid(let grid):
            guard let planning = try planArrangement(grid, onlyPid: onlyPid, settings: settings) else {
                return []
            }
            return planning.plan.assignments.map { Destination(frame: $0.frame, window: $0.window) }

        case .moveDivider(let direction):
            switch try planDividerMove(direction, onlyPid: onlyPid, settings: settings) {
            case .nothingToDo:
                return []
            case .move(let planning):
                let frames = planning.group.targetFrames(for: planning.layout)
                return zip(planning.group.windows, frames).map { Destination(frame: $1, window: $0) }
            }

        case .placeWindow, .moveToDisplay, .restoreWindow:
            switch try planSingleWindow(action).plan {
            case .nothingToDo:
                return []
            case .place(let target, _):
                return [Destination(frame: target)]
            }
        }
    }
}
