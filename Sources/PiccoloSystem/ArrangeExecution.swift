import CoreGraphics
import Foundation
import PiccoloCore

/// Where `arrangeGrid` finds out which windows exist and in which order they were focused.
public struct ArrangementSource: Sendable {
    /// The windows on screen, front to back; with `onlyPid`, only those of that process.
    public var catalog: @Sendable (_ onlyPid: pid_t?) throws -> [CatalogWindow]
    /// The windows focused so far, most recent first.
    public var history: @Sendable () -> FocusHistory
    /// The window that has the focus now, if any.
    public var focusedWindowID: @Sendable () -> WindowID?

    public init(
        catalog: @escaping @Sendable (_ onlyPid: pid_t?) throws -> [CatalogWindow],
        history: @escaping @Sendable () -> FocusHistory,
        focusedWindowID: @escaping @Sendable () -> WindowID?
    ) {
        self.catalog = catalog
        self.history = history
        self.focusedWindowID = focusedWindowID
    }

    /// No window and no history: `arrangeGrid` has nothing to do.
    public static let none = ArrangementSource(
        catalog: { _ in [] },
        history: { FocusHistory() },
        focusedWindowID: { nil })

    /// The windows on screen, and the history of ``FocusTracker/shared``, which starts with the
    /// first use of this value.
    public static let live: ArrangementSource = {
        let tracker = FocusTracker.shared
        tracker.start()
        return ArrangementSource(
            catalog: { try WindowCatalog.current(onlyPid: $0) },
            history: { tracker.history },
            focusedWindowID: { FocusedWindow.currentWindowID() })
    }()
}

/// What an arrangement did.
public struct ArrangeOutcome: Equatable, Sendable {
    /// The display the windows were arranged on, as an index into the displays the executor was given.
    public var displayIndex: Int
    /// One entry per window of the plan, most recently focused first: the window that took the
    /// top-left cell comes first.
    public var windows: [ArrangedWindow]

    public init(displayIndex: Int, windows: [ArrangedWindow]) {
        self.displayIndex = displayIndex
        self.windows = windows
    }
}

/// What happened to one window of an arrangement, or of a divider move (which sends the windows of
/// a group to new cells).
public struct ArrangedWindow: Equatable, Sendable {
    public var window: WindowID
    /// The cell the window was sent to.
    public var target: CGRect
    public var result: Result

    public init(window: WindowID, target: CGRect, result: Result) {
        self.window = window
        self.target = target
        self.result = result
    }

    public enum Result: Equatable, Sendable {
        /// The frame read back after the window was sent to its cell. It differs from the target
        /// when the window refused the size or had to be shifted back inside the display.
        case placed(achieved: CGRect)
        /// The window could not be changed (it was closed meanwhile, or refuses to move). The
        /// message says why.
        case failed(message: String)
    }
}

extension ActionExecutor {
    /// Arranges the most recently focused windows on one display, as `ArrangePlanner` plans it.
    ///
    /// - The display is the one containing the focused window; without a focused window, the one
    ///   containing the frontmost window of the catalog; without any window there is nothing to do.
    /// - The focused window counts as the most recently focused window, whether or not the history
    ///   has caught up with it yet.
    /// - The windows glide to their cells together over the duration of `settings.animation` (see
    ///   ``WindowAnimator``), then every window of the plan is sent to its cell with
    ///   ``FrameSetter/apply(_:to:within:)``. One that fails does not stop the others. No window is
    ///   raised or focused.
    /// - When no window failed, the windows become the linked group of the display (see
    ///   ``LayoutGroupStore``): the layout, the windows in cell order, the visible frame and the
    ///   frames read back.
    func arrange(_ grid: GridSpec, onlyPid: pid_t?, settings: ActionSettings) throws -> ActionOutcome {
        guard let planning = try planArrangement(grid, onlyPid: onlyPid, settings: settings) else {
            return .nothingToDo
        }
        let plan = planning.plan
        let windows = planning.windows
        let displays = planning.displays

        let handles = Dictionary(
            windows.map { ($0.candidate.id, $0.handle) }, uniquingKeysWith: { first, _ in first })
        let visibleFrame = displays[plan.displayIndex].visibleFrame
        // All windows glide together; the loop below then places each exactly as without animation.
        let starts = Dictionary(
            windows.map { ($0.candidate.id, $0.candidate.frame) }, uniquingKeysWith: { first, _ in first })
        glide(
            plan.assignments.compactMap { assignment in
                guard let handle = handles[assignment.window], let start = starts[assignment.window] else {
                    return nil
                }
                return AnimatedWindow(window: handle, start: start, target: assignment.frame)
            },
            settings: settings, displays: displays)
        let arranged = plan.assignments.map { assignment -> ArrangedWindow in
            let result: ArrangedWindow.Result
            do {
                guard let handle = handles[assignment.window] else { throw WindowError.windowGone }
                let achieved = try FrameSetter.apply(assignment.frame, to: handle, within: visibleFrame)
                result = .placed(achieved: achieved)
            } catch {
                result = .failed(message: Self.message(for: error))
            }
            return ArrangedWindow(window: assignment.window, target: assignment.frame, result: result)
        }
        recordGroup(of: plan, visibleFrame: visibleFrame, arranged: arranged)
        return .arranged(ArrangeOutcome(displayIndex: plan.displayIndex, windows: arranged))
    }

    /// An arrangement planned, not yet carried out.
    struct ArrangementPlanning {
        var plan: ArrangePlan
        /// The windows on screen the plan was made from; the plan's windows are among them.
        var windows: [CatalogWindow]
        var displays: [Display]
    }

    /// Plans the arrangement ``arrange(_:onlyPid:settings:)`` carries out, and touches nothing: not a
    /// window, not a group. `nil` when there is no window to arrange.
    func planArrangement(
        _ grid: GridSpec, onlyPid: pid_t?, settings: ActionSettings
    ) throws -> ArrangementPlanning? {
        let displays = try displaysProvider()
        guard !displays.isEmpty else { throw ActionPlanningError.noDisplays }

        let windows = try arrangement.catalog(onlyPid)
        let focusedFrame = try currentFocusedFrame()

        let reference = focusedFrame ?? windows.first?.candidate.frame
        let displayIndex = reference.flatMap { DisplayLayout.index(containing: $0, in: displays) } ?? 0

        var history = arrangement.history()
        if focusedFrame != nil, let focused = arrangement.focusedWindowID() {
            history.recordFocus(focused)
        }

        // Also checks the grid, so that an invalid one is refused even with nothing to arrange.
        guard
            let plan = try ArrangePlanner.plan(
                grid: grid,
                fillOrder: settings.gridFillOrder,
                displayIndex: displayIndex,
                candidates: windows.map(\.candidate),
                history: history,
                displays: displays)
        else { return nil }
        return ArrangementPlanning(plan: plan, windows: windows, displays: displays)
    }

    /// Records the windows of a successful arrangement as the group of their display, replacing
    /// the one it had. An arrangement in which any window failed records nothing.
    ///
    /// The group keeps the frames the windows were read back at, not the cells, so that a window
    /// that refused its cell is recognised where it is.
    private func recordGroup(of plan: ArrangePlan, visibleFrame: CGRect, arranged: [ArrangedWindow]) {
        let achieved = arranged.compactMap { window -> CGRect? in
            if case .placed(let frame) = window.result { return frame }
            return nil
        }
        guard achieved.count == arranged.count else { return }
        groups.record(
            LayoutGroup(
                layout: plan.layout,
                windows: plan.assignments.map(\.window),
                visibleFrame: visibleFrame,
                frames: achieved),
            onDisplay: plan.displayIndex)
    }

    /// The frame of the focused window, or `nil` when there is none.
    private func currentFocusedFrame() throws -> CGRect? {
        do {
            return try windowProvider().frame()
        } catch WindowError.noFocusedWindow, WindowError.noFrontmostApplication {
            return nil
        }
    }

    static func message(for error: any Error) -> String {
        if let described = (error as? any LocalizedError)?.errorDescription, !described.isEmpty {
            return described
        }
        return String(describing: error)
    }
}

extension FocusedWindow {
    /// The window that has the focus now, unless it is one of Piccolo's own.
    static func currentWindowID() -> WindowID? {
        guard let window = try? FocusedWindow.current(),
            window.pid != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return window.windowID
    }
}
