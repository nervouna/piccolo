import Foundation

/// Calls back once, a while from now, on the main actor.
@MainActor
public protocol HoldTimer: AnyObject {
    /// Calls `fire` after `delay` seconds. The returned closure cancels the call; cancelling one that
    /// has fired already does nothing.
    func schedule(
        after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void
}

/// The timer of the live app: the main queue.
@MainActor
public final class MainQueueHoldTimer: HoldTimer {
    public init() {}

    public func schedule(
        after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated(fire)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}

/// Runs ``HoldRules`` against a timer, and hands the effects it asks for to a closure.
///
/// The controller owns the one timer a hold needs: it starts it when the rules ask for it, and stops
/// it when the hold is over. Everything happens on the main actor, in the order the events arrive.
@MainActor
public final class HoldController {
    private var rules: HoldRules
    private let timer: any HoldTimer
    private var cancelTimer: (@MainActor () -> Void)?

    /// Called for every effect except the timer, in order: run an action, show the preview, hide it.
    public var onEffect: (@MainActor (HoldRules.Effect) -> Void)?

    public init(timer: any HoldTimer, isPreviewEnabled: Bool = true) {
        self.timer = timer
        self.rules = HoldRules(isPreviewEnabled: isPreviewEnabled)
    }

    /// The shortcut that is down, if any.
    public var held: HoldRules.Held? { rules.held }
    /// What became of the last hold.
    public var last: HoldRules.Outcome? { rules.last }
    public var isPreviewEnabled: Bool { rules.isPreviewEnabled }

    /// Feeds an event to the rules and carries out what they ask for.
    public func send(_ event: HoldRules.Event) {
        apply(rules.handle(event))
    }

    /// Switches the preview on or off. Switching it off cancels what is held.
    public func setPreviewEnabled(_ enabled: Bool) {
        apply(rules.setPreviewEnabled(enabled))
    }

    private func apply(_ effects: [HoldRules.Effect]) {
        for effect in effects {
            switch effect {
            case .startTimer(let token):
                cancelTimer?()
                cancelTimer = timer.schedule(after: HoldRules.delay) { [weak self] in
                    self?.send(.timerFired(token))
                }
            case .run, .showPreview, .hidePreview:
                onEffect?(effect)
            }
        }
        if rules.held == nil {
            cancelTimer?()
            cancelTimer = nil
        }
    }
}
