import CoreGraphics
import Foundation
import PiccoloCore

/// What a `swapWindow` run did.
public enum SwapOutcome: Equatable, Sendable {
    /// The focused window and its neighbour traded cells. The group is recorded again with the two
    /// windows exchanged, where they ended up. `windows` lists every window of the group in cell order
    /// after the swap, with the last frame it was asked for and the frame it was read back at; a
    /// window that was not part of the swap is listed with its cell and the frame it already had. A
    /// window that could not be changed, or was not moved because an earlier one could not, has no
    /// achieved frame, and the group is dissolved.
    case swapped(display: Int, windows: [ArrangedWindow])
    /// Nothing moved, and that is a success: the reason says why.
    case nothingToDo(Reason)

    /// Why a `swapWindow` run left every window where it was.
    public enum Reason: Equatable, Sendable {
        /// No window has the focus, or it is one of Piccolo's own.
        case noFocusedWindow
        /// The focused window is in no group: Piccolo did not arrange it with others, or the group
        /// was dissolved before.
        case noGroup
        /// The focused window's group no longer held, so it was dissolved: a member was closed,
        /// left the screen or was moved.
        case dissolved(LayoutGroup.Breakage)
        /// No window of the group is on that side of the focused window. `bounced` says whether the
        /// focused window bounced towards that side and back instead (see
        /// ``ActionExecutor/swapWindow(_:onlyPid:settings:)``); the hotkey path shows a notice when it
        /// did not.
        case noNeighbour(bounced: Bool)

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
            case .noNeighbour:
                return "no window of the group is on that side: there is no neighbour to swap with"
            }
        }
    }
}

extension ActionExecutor {
    /// Exchanges the focused window with its neighbour in the group that holds it.
    ///
    /// 1. The group is the one containing the focused window, checked now (see
    ///    ``lookUpFocusedGroup(onlyPid:)``): without a focused window, without a group, or with a group
    ///    that no longer holds (it is dissolved) there is nothing to do.
    /// 2. `SwapNeighbor.neighbor(of:direction:in:)` gives the cell to swap with. Without one there is
    ///    nothing to swap, except that with `settings.animation` on (and an animator) the focused window
    ///    bounces: it goes 16 pt towards that side and back in 0.2 s, whatever the animation speed (see
    ///    ``EdgeBounce`` and ``WindowAnimator/bounce(_:from:towards:duration:)``), and ends exactly at
    ///    the frame it started at. For `up` it is squashed instead, because macOS keeps a window below
    ///    the menu bar. The group is neither recorded nor dissolved: the window is back at its recorded
    ///    frame. The outcome says whether it bounced; it did not when the animation is off, when the
    ///    executor has no animator, when the size of a window cannot be set for `up`, or when an
    ///    Accessibility call failed.
    /// 3. The two windows trade cells: each is sent to the frame of the other's cell, and takes the
    ///    size of that cell. The layout is the same, so the group stays linked. They glide together
    ///    (they pass each other, so they overlap while they do), then are placed in the group's visible
    ///    frame, the one that shrinks first. No other window of the group is touched.
    /// 4. The group is recorded with the two windows exchanged, then with what they achieved. A window
    ///    that refused the size of its new cell moves the divider to where it ended up, and the windows
    ///    whose cell changed with it are sent there once more, without a glide (see
    ///    ``carryOut(_:display:layout:previousTargets:handles:frames:settings:)``, which
    ///    ``moveDivider(_:onlyPid:settings:)`` shares). A window that cannot be changed ends the swap and
    ///    dissolves the group. Each window that was changed is noted in the window records.
    ///
    /// No window is raised or focused: the focused window keeps the focus and moves with it, so that
    /// repeated presses carry it across the group.
    func swapWindow(_ direction: Direction, onlyPid: pid_t?, settings: ActionSettings) throws -> ActionOutcome {
        let planning: SwapPlanning
        switch try planSwap(direction, onlyPid: onlyPid) {
        case .nothingToDo(let reason, let dissolve):
            if let dissolve { groups.dissolve(display: dissolve) }
            return .swap(.nothingToDo(reason))
        case .noNeighbour(let edge):
            let bounced = bounce(edge.window, from: edge.frame, towards: direction, settings: settings)
            return .swap(.nothingToDo(.noNeighbour(bounced: bounced)))
        case .swap(let found):
            planning = found
        }

        // The window now in each swapped cell came from the other one, so that is the frame its cell
        // had for it before.
        var previousTargets = planning.group.targetFrames(for: planning.group.layout, gap: settings.gap)
        previousTargets.swapAt(planning.focusedCell, planning.neighborCell)
        let windows = carryOut(
            planning.group, display: planning.entry.display, layout: planning.group.layout,
            previousTargets: previousTargets, handles: planning.handles, frames: planning.frames,
            settings: settings)
        return .swap(.swapped(display: planning.entry.display, windows: windows))
    }

    /// A swap planned, not yet carried out.
    struct SwapPlanning {
        /// The group as it is now, with its display.
        var entry: LayoutGroups.Entry
        /// The group with the two windows exchanged: the layout is the same.
        var group: LayoutGroup
        /// The cell of the focused window and the cell of its neighbour (the cells that traded).
        var focusedCell: Int
        var neighborCell: Int
        /// The handles and frames of the windows on screen.
        var handles: [WindowID: any WindowFrameAccess]
        var frames: [WindowID: CGRect]

        /// The two cells that trade, lowest first.
        var cells: [Int] { [focusedCell, neighborCell].sorted() }
    }

    /// The focused window of a group that has no neighbour on the side of the key: what the run
    /// bounces.
    struct SwapEdge {
        /// The focused window's handle and the frame it was read at.
        var window: any WindowFrameAccess
        var frame: CGRect
    }

    /// What ``planSwap(_:onlyPid:)`` found.
    enum SwapPlan {
        case swap(SwapPlanning)
        /// No window of the group is on that side of the focused window: nothing swaps, and the run
        /// may bounce `SwapEdge/window`. A plan never does.
        case noNeighbour(SwapEdge)
        /// Nothing moves, for a reason other than a missing neighbour. `dissolve` is the display of a
        /// group that no longer holds and that the run dissolves; a plan leaves it alone.
        case nothingToDo(SwapOutcome.Reason, dissolve: Int?)
    }

    /// Plans the swap ``swapWindow(_:onlyPid:settings:)`` carries out: steps 1 and 2 of its list, and
    /// the group with the two windows exchanged. It reads the windows on screen and touches neither a
    /// window nor a group; a group that no longer holds is reported (`dissolve`) and left for the
    /// caller to dissolve, and so is the bounce of a window with no neighbour.
    ///
    /// - Throws: ``WindowError`` when the windows on screen cannot be read.
    func planSwap(_ direction: Direction, onlyPid: pid_t?) throws -> SwapPlan {
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
            let neighbor = SwapNeighbor.neighbor(
                of: focused.cell, direction: direction, in: focused.group.layout)
        else {
            let window = focused.group.windows[focused.cell]
            guard let handle = focused.handles[window], let frame = focused.frames[window] else {
                // Cannot happen after the group was checked; without a handle there is nothing to bounce.
                return .nothingToDo(.noNeighbour(bounced: false), dissolve: nil)
            }
            return .noNeighbour(SwapEdge(window: handle, frame: frame))
        }
        return .swap(
            SwapPlanning(
                entry: focused.entry, group: focused.group.swappingCells(focused.cell, neighbor),
                focusedCell: focused.cell, neighborCell: neighbor, handles: focused.handles,
                frames: focused.frames))
    }
}
