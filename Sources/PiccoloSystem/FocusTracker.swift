import Foundation
import PiccoloCore
import os

/// Tells a ``FocusTracker`` that the focused window may have changed. Live, the events are
/// application activations and focused or main window changes inside the active application
/// (``SystemFocusEvents``); tests use a fake.
protocol FocusEventSource: Sendable {
    /// Starts delivering events. `onChange` may be called on any thread, at any time after this
    /// returns, as often as the source likes: an event only means "look again".
    func start(onChange: @escaping @Sendable () -> Void)
}

/// Keeps a ``FocusHistory`` up to date: which windows were focused, most recent first.
///
/// The tracker is thin on purpose. An event carries no information, it only triggers a look at the
/// window that has the focus now, and the order is kept by `FocusHistory`. Looking again at an
/// unchanged focus changes nothing, so that events may arrive late, twice, or in a burst.
///
/// The look happens on the tracker's own serial queue, in the order the events arrived: a slow
/// application delays later looks but never runs two at once.
public final class FocusTracker: Sendable {
    private struct State {
        var history: FocusHistory
        var started = false
    }

    private let source: any FocusEventSource
    private let focusedWindow: @Sendable () -> WindowID?
    private let queue = DispatchQueue(label: "io.damao.piccolo.focus-tracker")
    private let state: OSAllocatedUnfairLock<State>

    /// Tracks the focus of the live system: the first call to ``start()`` records the focused window
    /// and begins to listen for changes.
    public static let shared = FocusTracker(
        source: SystemFocusEvents(), focusedWindow: { FocusedWindow.currentWindowID() })

    /// - Parameters:
    ///   - source: Where events come from.
    ///   - focusedWindow: The window that has the focus now, or `nil` when there is none or it is
    ///     not worth tracking. It may block, and is only called on the tracker's queue.
    ///   - capacity: How many windows the history remembers.
    init(
        source: any FocusEventSource, focusedWindow: @escaping @Sendable () -> WindowID?,
        capacity: Int = 256
    ) {
        self.source = source
        self.focusedWindow = focusedWindow
        self.state = OSAllocatedUnfairLock(initialState: State(history: FocusHistory(capacity: capacity)))
    }

    /// Records the window that has the focus now and keeps recording as it changes. Only the first
    /// call does anything.
    public func start() {
        let first = state.withLock { state -> Bool in
            defer { state.started = true }
            return !state.started
        }
        guard first else { return }
        source.start { [weak self] in
            guard let self else { return }
            queue.async { self.look() }
        }
        queue.async { self.look() }
    }

    /// The windows focused so far, most recent first.
    public var history: FocusHistory {
        state.withLock { $0.history }
    }

    /// Waits until every look requested so far is done. For tests.
    func settle() {
        queue.sync {}
    }

    private func look() {
        guard let window = focusedWindow() else { return }
        state.withLock { $0.history.recordFocus(window) }
    }
}
