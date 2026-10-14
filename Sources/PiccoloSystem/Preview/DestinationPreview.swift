import CoreGraphics
import Foundation
import PiccoloCore

/// Puts frames on screen as a highlight, and takes them away. ``HighlightPanels`` is the real one.
@MainActor
public protocol HighlightPresenter: AnyObject {
    /// Shows one highlight for each frame (canonical coordinates), replacing what showed before.
    func present(_ frames: [CGRect])
    /// Takes the highlight away.
    func dismiss()
}

/// The destination preview: plans where an action would send its windows, and shows that.
///
/// ``show(_:settings:bindingID:)`` hands the planning to a queue (the one the actions run on, because planning
/// reads the focused window and the windows on screen through Accessibility, which can take long),
/// and presents the frames when the plan is back. ``hide()`` takes the highlight away, and a plan that
/// comes back after it, or after another ``show(_:settings:bindingID:)``, is dropped: when the shortcut is
/// released before the planning finished, nothing is shown.
///
/// Planning errors and plans without a destination show nothing. The release still runs the action,
/// as it does without a preview.
@MainActor
public final class DestinationPreview {
    private let presenter: any HighlightPresenter
    private let queue: DispatchQueue
    private let plan: @Sendable (Action, ActionSettings) throws -> [Destination]
    /// Counts the shows and hides, so that a plan can tell that it has been overtaken.
    private var generation = 0

    /// The destinations on screen, or `nil` when nothing is shown.
    private var shown: [Destination]?
    /// The binding whose action is shown, or was asked for.
    public private(set) var bindingID: UUID?
    /// How many plans have been handed to the queue and not been dealt with yet.
    public private(set) var pendingPlans = 0
    /// Whether the latest ``show(_:settings:bindingID:)`` reached the screen. Stays set after ``hide()``.
    public private(set) var lastShowPresented = false
    /// What went wrong in the latest plan, or `nil`.
    public private(set) var lastError: String?

    /// - Parameters:
    ///   - queue: Where planning runs. A serial queue, the one the actions run on.
    ///   - plan: Plans an action with the settings in effect: the destinations it would send windows to.
    public init(
        presenter: any HighlightPresenter, queue: DispatchQueue,
        plan: @escaping @Sendable (Action, ActionSettings) throws -> [Destination]
    ) {
        self.presenter = presenter
        self.queue = queue
        self.plan = plan
    }

    /// Whether a highlight is on screen.
    public var isVisible: Bool {
        shown != nil
    }

    /// The frames on screen, in canonical coordinates. Empty when nothing is shown.
    public var frames: [CGRect] {
        shown?.map(\.frame) ?? []
    }

    /// The window each frame is for, when the action is an arrangement or a divider move; `nil` for a
    /// single-window action and when nothing is shown.
    public var windows: [WindowID]? {
        guard let shown else { return nil }
        let windows = shown.compactMap(\.window)
        return windows.count == shown.count ? windows : nil
    }

    /// Plans `action` and shows where it would send the windows, once the plan is there.
    ///
    /// - Parameter settings: The settings in effect now, as for running the action.
    public func show(_ action: Action, settings: ActionSettings, bindingID: UUID) {
        generation += 1
        let mine = generation
        self.bindingID = bindingID
        lastShowPresented = false
        lastError = nil
        pendingPlans += 1
        let plan = plan
        queue.async { [weak self] in
            let result = Result { try plan(action, settings) }
            Task { @MainActor in
                self?.planned(result, generation: mine)
            }
        }
    }

    /// Takes the highlight away, and drops a plan that is still on its way.
    public func hide() {
        generation += 1
        if shown != nil {
            shown = nil
            presenter.dismiss()
        }
    }

    private func planned(_ result: Result<[Destination], any Error>, generation plannedFor: Int) {
        pendingPlans -= 1
        guard plannedFor == generation else { return }
        switch result {
        case .failure(let error):
            lastError = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        case .success(let destinations):
            guard !destinations.isEmpty else { return }
            shown = destinations
            lastShowPresented = true
            presenter.present(destinations.map(\.frame))
        }
    }
}
