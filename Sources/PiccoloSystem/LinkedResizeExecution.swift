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
    /// 4. The windows whose cell changed are sent to their new frames and the group records what they
    ///    achieved (see ``carryOut(_:display:layout:previousTargets:handles:frames:settings:)``, which
    ///    ``swapWindow(_:onlyPid:settings:)`` shares): they glide together (see ``WindowAnimator``),
    ///    then are placed with ``FrameSetter/apply(_:to:within:)``, those that shrink first, then those
    ///    that grow. A window that refused its size moves the divider to where it ended up, and the
    ///    windows whose cell changed with it are sent once more, without a glide. A window that cannot
    ///    be changed ends the move and dissolves the group.
    func moveDivider(_ direction: Direction, onlyPid: pid_t?, settings: ActionSettings) throws -> ActionOutcome {
        let planning: DividerMovePlanning
        switch try planDividerMove(direction, onlyPid: onlyPid, settings: settings) {
        case .nothingToDo(let reason, let dissolve):
            if let dissolve { groups.dissolve(display: dissolve) }
            return .dividerMove(.nothingToDo(reason))
        case .move(let found):
            planning = found
        }
        let previousTargets = planning.group.targetFrames(for: planning.group.layout, gap: settings.gap)
        let windows = carryOut(
            planning.group, display: planning.entry.display, layout: planning.layout,
            previousTargets: previousTargets, handles: planning.handles, frames: planning.frames,
            settings: settings)
        return .dividerMove(.moved(DividerMoved(display: planning.entry.display, windows: windows)))
    }

    /// A divider move planned, not yet carried out.
    struct DividerMovePlanning {
        var entry: LayoutGroups.Entry
        var group: LayoutGroup
        /// The handles and frames of the windows on screen.
        var handles: [WindowID: any WindowFrameAccess]
        var frames: [WindowID: CGRect]
        /// The layout after the move.
        var layout: TileLayout
    }

    /// What ``planDividerMove(_:onlyPid:settings:)`` found.
    enum DividerPlanning {
        case move(DividerMovePlanning)
        /// Nothing moves. `dissolve` is the display of a group that no longer holds and that the run
        /// dissolves; a plan leaves it alone.
        case nothingToDo(DividerMoveOutcome.Reason, dissolve: Int?)
    }

    /// Plans the move ``moveDivider(_:onlyPid:settings:)`` carries out: steps 1 to 3 of its list. It
    /// reads the windows on screen and touches neither a window nor a group; a group that no longer
    /// holds is reported (`dissolve`) and left for the caller to dissolve.
    ///
    /// - Throws: ``ActionExecutionError`` for a `resizeStep` that is not a positive number, and
    ///   ``WindowError`` when the windows on screen cannot be read.
    func planDividerMove(
        _ direction: Direction, onlyPid: pid_t?, settings: ActionSettings
    ) throws -> DividerPlanning {
        let step = settings.resizeStep
        guard step.isFinite, step > 0 else { throw ActionExecutionError.invalidResizeStep(step) }
        let focused: FocusedGroup
        switch try lookUpFocusedGroup(onlyPid: onlyPid) {
        case .noFocusedWindow:
            return .nothingToDo(.noFocusedWindow, dissolve: nil)
        case .noGroup:
            return .nothingToDo(.noGroup, dissolve: nil)
        case .dissolved(let breakage, let display):
            return .nothingToDo(.dissolved(breakage), dissolve: display)
        case .found(let found):
            focused = found
        }

        guard
            let layout = DividerMove.plan(
                layout: focused.group.layout, focusedCell: focused.cell, direction: direction, step: step)
        else { return .nothingToDo(.cannotMove, dissolve: nil) }
        return .move(
            DividerMovePlanning(
                entry: focused.entry, group: focused.group, handles: focused.handles, frames: focused.frames,
                layout: layout))
    }

    /// The group of the focused window, checked now, with the windows on screen.
    struct FocusedGroup {
        var entry: LayoutGroups.Entry
        var group: LayoutGroup
        /// The cell of the focused window.
        var cell: Int
        /// The handles and frames of the windows on screen.
        var handles: [WindowID: any WindowFrameAccess]
        var frames: [WindowID: CGRect]
    }

    /// What ``lookUpFocusedGroup(onlyPid:)`` found.
    enum FocusedGroupLookup {
        case found(FocusedGroup)
        /// No window has the focus, or it is one of Piccolo's own.
        case noFocusedWindow
        /// The focused window is in no group.
        case noGroup
        /// The group no longer holds. `display` is the display of the group, which the run dissolves
        /// and a plan leaves alone.
        case dissolved(LayoutGroup.Breakage, display: Int)
    }

    /// Steps 1 and 2 of ``moveDivider(_:onlyPid:settings:)``, shared with ``swapWindow(_:onlyPid:settings:)``:
    /// the group that holds the focused window, checked now. The windows on screen are read (those of
    /// `onlyPid` only, when it is given), and the group no longer holds when a member is not among them
    /// or an edge of one is more than 2 pt from the frame recorded for it. It touches neither a window
    /// nor a group.
    ///
    /// - Throws: ``WindowError`` when the windows on screen cannot be read.
    func lookUpFocusedGroup(onlyPid: pid_t?) throws -> FocusedGroupLookup {
        guard let focused = arrangement.focusedWindowID() else { return .noFocusedWindow }
        guard let entry = groups.entry(containing: focused), let cell = entry.group.cell(of: focused) else {
            return .noGroup
        }

        let onScreen = try arrangement.catalog(onlyPid)
        var handles: [WindowID: any WindowFrameAccess] = [:]
        var frames: [WindowID: CGRect] = [:]
        for window in onScreen where handles[window.candidate.id] == nil {
            handles[window.candidate.id] = window.handle
            frames[window.candidate.id] = window.candidate.frame
        }
        if let breakage = entry.group.breakage(currentFrames: frames) {
            return .dissolved(breakage, display: entry.display)
        }
        return .found(FocusedGroup(entry: entry, group: entry.group, cell: cell, handles: handles, frames: frames))
    }

    /// Sends the windows of `group` to the cells `layout` gives them and records what came of it: steps
    /// 4 and 5 of ``moveDivider(_:onlyPid:settings:)``, shared with ``swapWindow(_:onlyPid:settings:)``.
    ///
    /// 1. Only the windows whose cell changed are sent (`LayoutGroup.steps(from:to:current:)`): those
    ///    whose cell frame in `previousTargets` is not the one `layout` gives them now, and that are not
    ///    already there. They glide to their new frames together (see ``WindowAnimator``), then are
    ///    placed with ``FrameSetter/apply(_:to:within:)`` in the group's visible frame: those that shrink
    ///    first, then those that grow.
    /// 2. The group records what the windows achieved
    ///    (``LayoutGroup/recordAchieved(requested:achieved:gap:)``). When a window refused its size, the
    ///    divider is recorded where that window ended up, and the windows whose cell changed because of
    ///    it are sent to their cells once more, so that the neighbour fills the space, without a glide.
    ///    The group records the result again.
    ///
    /// A window that cannot be changed (closed meanwhile, or a failing Accessibility call) ends the
    /// run: the windows after it in the order above are left alone, so that none grows into space that
    /// is still taken. The group cannot be trusted any more: it is dissolved, and the windows that were
    /// not moved are reported with the reason. Otherwise the group is updated. Every window that was
    /// changed is noted in the window records.
    ///
    /// - Parameters:
    ///   - group: the group as it will be after the run: its windows in the cells they are sent to.
    ///   - display: the display of the group.
    ///   - layout: the layout the windows are sent to, with the orientation and the cells per row
    ///     (column) of the group's layout.
    ///   - previousTargets: the frame each cell had, in cell order, for the window that is in it now.
    ///   - handles: the windows on screen, and `frames` the frames they have now.
    /// - Returns: every window of the group in cell order, with the last frame it was asked for and the
    ///   frame it was read back at. A window that did not have to move is listed with its cell and the
    ///   frame it already had.
    func carryOut(
        _ group: LayoutGroup,
        display: Int,
        layout: TileLayout,
        previousTargets: [CGRect],
        handles: [WindowID: any WindowFrameAccess],
        frames: [WindowID: CGRect],
        settings: ActionSettings
    ) -> [ArrangedWindow] {
        var group = group
        let gap = settings.gap
        let targets = group.targetFrames(for: layout, gap: gap)
        var placements = zip(targets, group.windows).map { target, window in
            Placement(target: target, achieved: frames[window] ?? target)
        }

        var steps = group.steps(from: previousTargets, to: targets, current: placements.map(\.achieved))
        var changedCells = Set(steps.map(\.cell))
        send(steps, to: handles, within: group.visibleFrame, updating: &placements, animatingWith: settings)
        if !placements.contains(where: { $0.failure != nil }) {
            group.recordAchieved(requested: layout, achieved: placements.map(\.achieved), gap: gap)

            // A window that refused its size moved the divider to where it ended up. The windows
            // whose cell changed with it go there too.
            steps = group.steps(
                from: targets, to: group.targetFrames(for: group.layout, gap: gap),
                current: placements.map(\.achieved))
            if !steps.isEmpty {
                changedCells.formUnion(steps.map(\.cell))
                send(steps, to: handles, within: group.visibleFrame, updating: &placements)
                if !placements.contains(where: { $0.failure != nil }) {
                    group.recordAchieved(
                        requested: group.layout, achieved: placements.map(\.achieved), gap: gap)
                }
            }
        }

        if placements.contains(where: { $0.failure != nil }) {
            groups.dissolve(display: display)
        } else {
            groups.update(group, onDisplay: display)
        }
        // Only the windows whose cell changed, and that were changed, are noted.
        for cell in changedCells.sorted() where placements[cell].failure == nil {
            let window = group.windows[cell]
            if let before = frames[window] {
                records.recordChange(of: window, from: before, to: placements[cell].achieved)
            }
        }
        return zip(group.windows, placements).map { window, placement in
            ArrangedWindow(
                window: window, target: placement.target,
                result: placement.failure.map { .failed(message: $0) } ?? .placed(achieved: placement.achieved))
        }
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
