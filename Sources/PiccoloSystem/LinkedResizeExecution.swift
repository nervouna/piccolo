import CoreGraphics
import Foundation
import PiccoloCore

/// What a `moveDivider` run did.
public enum DividerMoveOutcome: Equatable, Sendable {
    /// The divider moved. The group is recorded again where its windows ended up.
    case moved(DividerMoved)
    /// Nothing moved, and that is a success: the reason says why.
    case nothingToDo(Reason)

    /// Why a `moveDivider` run left every window where it was.
    public enum Reason: Equatable, Sendable {
        /// No window has the focus, or it is one of Piccolo's own.
        case noFocusedWindow
        /// The focused window is in no group: Piccolo did not arrange it with others, or the group
        /// was dissolved before.
        case noGroup
        /// The focused window's group no longer held, so it was dissolved: a member was closed,
        /// left the screen or was moved.
        case dissolved(LayoutGroup.Breakage)
        /// The divider cannot move that way: the window that would shrink is at its smallest
        /// (10% of the display), or there is no divider in that direction.
        case cannotMove

        /// A sentence for logs and the control channel.
        public var message: String {
            switch self {
            case .noFocusedWindow:
                return "no window has the focus"
            case .noGroup:
                return "the focused window is not in a group Piccolo arranged"
            case .dissolved(.missing(let window)):
                return "the group was dissolved: window \(window.rawValue) is no longer on screen"
            case .dissolved(.moved(let window)):
                return "the group was dissolved: window \(window.rawValue) is no longer where Piccolo put it"
            case .cannotMove:
                return "the divider cannot move that way: a window is at its smallest, or there is no divider"
            }
        }
    }
}

/// A divider move that sent windows to new frames.
public struct DividerMoved: Equatable, Sendable {
    /// The display the group was arranged on, as an index into the displays the arrangement was
    /// planned on.
    public var display: Int
    /// Every window of the group in cell order, with the last frame it was asked for
    /// and the frame it was read back at. A window that did not have to move is listed with its
    /// cell and the frame it already had. A window that could not be changed, or was not moved
    /// because an earlier one could not, has no achieved frame, and the group is dissolved.
    public var windows: [ArrangedWindow]

    public init(display: Int, windows: [ArrangedWindow]) {
        self.display = display
        self.windows = windows
    }
}

extension ActionExecutor {
    /// Moves a divider of the group that holds the focused window.
    ///
    /// 1. The group is the one containing the focused window. Without a focused window, or without
    ///    a group, there is nothing to do.
    /// 2. The group is checked now, not earlier: the windows on screen are read, and the group is
    ///    dissolved when a member is not among them or an edge of one is more than 2 pt from the
    ///    frame recorded for it.
    /// 3. `DividerMove.plan` gives the new layout, one `settings.resizeStep` away. Without one (a
    ///    window at its smallest, no divider in that direction) there is nothing to do.
    /// 4. The windows whose cell changed glide to their new frames together (see ``WindowAnimator``),
    ///    then are sent there with ``FrameSetter/apply(_:to:within:)`` in the group's visible frame:
    ///    those that shrink first, then those that grow, so that no two windows overlap while it
    ///    happens.
    /// 5. The group records what the windows achieved (``LayoutGroup/recordAchieved(requested:achieved:)``).
    ///    When a window refused its size, the divider is recorded where that window ended up, and
    ///    the windows whose cell changed because of it are sent to their cells once more, so that
    ///    the neighbour fills the space, without a glide. The group records the result again.
    ///
    /// A window that cannot be changed (closed meanwhile, or a failing Accessibility call) ends the
    /// move: the windows after it in the order above are left alone, so that none grows into space
    /// that is still taken. The group cannot be trusted any more: it is dissolved, and the windows
    /// that were not moved are reported with the reason.
    func moveDivider(_ direction: Direction, onlyPid: pid_t?, settings: ActionSettings) throws -> ActionOutcome {
        let step = settings.resizeStep
        guard step.isFinite, step > 0 else { throw ActionExecutionError.invalidResizeStep(step) }
        guard let focused = arrangement.focusedWindowID() else {
            return .dividerMove(.nothingToDo(.noFocusedWindow))
        }
        guard let entry = groups.entry(containing: focused), let cell = entry.group.cell(of: focused) else {
            return .dividerMove(.nothingToDo(.noGroup))
        }
        var group = entry.group

        let onScreen = try arrangement.catalog(onlyPid)
        var handles: [WindowID: any WindowFrameAccess] = [:]
        var frames: [WindowID: CGRect] = [:]
        for window in onScreen where handles[window.candidate.id] == nil {
            handles[window.candidate.id] = window.handle
            frames[window.candidate.id] = window.candidate.frame
        }
        if let breakage = group.breakage(currentFrames: frames) {
            groups.dissolve(display: entry.display)
            return .dividerMove(.nothingToDo(.dissolved(breakage)))
        }

        guard
            let layout = DividerMove.plan(
                layout: group.layout, focusedCell: cell, direction: direction, step: step)
        else { return .dividerMove(.nothingToDo(.cannotMove)) }

        let previousTargets = group.targetFrames(for: group.layout)
        let targets = group.targetFrames(for: layout)
        var placements = zip(targets, group.windows).map { target, window in
            Placement(target: target, achieved: frames[window] ?? target)
        }

        var steps = group.steps(from: previousTargets, to: targets, current: placements.map(\.achieved))
        send(steps, to: handles, within: group.visibleFrame, updating: &placements, animatingWith: settings)
        if !placements.contains(where: { $0.failure != nil }) {
            group.recordAchieved(requested: layout, achieved: placements.map(\.achieved))

            // A window that refused its size moved the divider to where it ended up. The windows
            // whose cell changed with it go there too.
            steps = group.steps(
                from: targets, to: group.targetFrames(for: group.layout),
                current: placements.map(\.achieved))
            if !steps.isEmpty {
                send(steps, to: handles, within: group.visibleFrame, updating: &placements)
                if !placements.contains(where: { $0.failure != nil }) {
                    group.recordAchieved(requested: group.layout, achieved: placements.map(\.achieved))
                }
            }
        }

        if placements.contains(where: { $0.failure != nil }) {
            groups.dissolve(display: entry.display)
        } else {
            groups.update(group, onDisplay: entry.display)
        }
        let windows = zip(group.windows, placements).map { window, placement in
            ArrangedWindow(
                window: window, target: placement.target,
                result: placement.failure.map { .failed(message: $0) } ?? .placed(achieved: placement.achieved))
        }
        return .dividerMove(.moved(DividerMoved(display: entry.display, windows: windows)))
    }

    /// What is known about one window of the group during a move.
    private struct Placement {
        /// The last frame the window was asked to take.
        var target: CGRect
        /// The last frame it was read at.
        var achieved: CGRect
        /// Set when the window could not be changed.
        var failure: String?
    }

    /// Sends each step's window to its target, in the order given, and records what came of it.
    ///
    /// The order is only safe when every step before has been done, so a step that fails ends the
    /// run: the windows after it are not touched, and are reported as not moved.
    ///
    /// With `settings`, the windows first glide together to their targets over the duration of
    /// `settings.animation`, the ones that shrink getting their step of every tick before the ones that
    /// grow (the order of `steps`). The glide keeps the order's rule too: once a window is dropped from
    /// it (it failed, or was too slow), the windows behind it stop. The windows are then sent to their
    /// targets as without animation, in the order given.
    private func send(
        _ steps: [LayoutGroup.Step],
        to handles: [WindowID: any WindowFrameAccess],
        within visibleFrame: CGRect,
        updating placements: inout [Placement],
        animatingWith settings: ActionSettings? = nil
    ) {
        if let settings {
            glide(
                steps.compactMap { step in
                    handles[step.window].map {
                        AnimatedWindow(window: $0, start: placements[step.cell].achieved, target: step.target)
                    }
                },
                settings: settings, displays: [Display(frame: visibleFrame, visibleFrame: visibleFrame)],
                ordered: true)
        }
        var failed: WindowID?
        for step in steps {
            placements[step.cell].target = step.target
            if let failed {
                placements[step.cell].failure =
                    "not moved: window \(failed.rawValue) could not be changed before it"
                continue
            }
            do {
                guard let handle = handles[step.window] else { throw WindowError.windowGone }
                placements[step.cell].achieved = try FrameSetter.apply(
                    step.target, to: handle, within: visibleFrame)
            } catch {
                placements[step.cell].failure = Self.message(for: error)
                failed = step.window
            }
        }
    }
}
