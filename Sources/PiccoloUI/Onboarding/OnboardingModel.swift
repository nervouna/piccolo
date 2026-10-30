import Foundation
import Observation
import PiccoloCore

/// Where the guide remembers that it was finished or skipped. The app plugs in ``OnboardingDefaults``;
/// tests use one in memory.
@MainActor
public protocol OnboardingStore: AnyObject {
    var isSeen: Bool { get }
    func setSeen(_ seen: Bool)
}

/// The flag as macOS stores it: a boolean `OnboardingSeen` in the app's own defaults domain
/// (`io.damao.piccolo`, the standard defaults of the app).
public struct OnboardingDefaults {
    /// The key of the flag.
    public static let key = "OnboardingSeen"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isSeen: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func setSeen(_ seen: Bool) {
        defaults.set(seen, forKey: Self.key)
        // The app may be quit right after.
        defaults.synchronize()
    }
}

/// The model of the guide window: the flow, whether the guide is open, the stored flag, and the timer
/// of the advance after a done step.
///
/// "Finish", "Skip Guide" and closing the window all end in ``skipGuide()`` or ``finish()``, which
/// store that the guide was seen and close it. Opening it again starts at step 1.
@MainActor
@Observable
public final class OnboardingModel {
    /// Seconds a done step stays before the guide moves on by itself.
    public static let advanceDelay: TimeInterval = 1.0

    /// Runs `work` after `delay` seconds on the main actor.
    public typealias Scheduler = @MainActor (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    public private(set) var flow: OnboardingFlow
    public private(set) var isOpen = false

    /// Called after the guide opened or closed. The window follows it.
    @ObservationIgnored public var onOpenChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private let store: any OnboardingStore
    @ObservationIgnored private let schedule: Scheduler

    public init(
        store: any OnboardingStore,
        schedule: @escaping Scheduler = { delay, work in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                work()
            }
        }
    ) {
        self.store = store
        self.schedule = schedule
        flow = OnboardingFlow(accessibilityGranted: false, config: Config(bindings: []))
    }

    /// Whether the guide was finished or skipped before.
    public var seen: Bool {
        store.isSeen
    }

    /// Stores the flag as it is, for the debug channel.
    public func setSeen(_ seen: Bool) {
        store.setSeen(seen)
    }

    /// Whether the guide opens at launch (see ``OnboardingFlow/shouldOpenAtLaunch(wroteDefaultShortcuts:seen:)``).
    public func shouldOpenAtLaunch(wroteDefaultShortcuts: Bool) -> Bool {
        OnboardingFlow.shouldOpenAtLaunch(wroteDefaultShortcuts: wroteDefaultShortcuts, seen: seen)
    }

    // MARK: Opening and closing

    /// Opens the guide at step 1, or leaves it as it is when it is open already. Works whatever is stored.
    public func open(accessibilityGranted: Bool, config: Config) {
        guard !isOpen else { return }
        flow = OnboardingFlow(accessibilityGranted: accessibilityGranted, config: config)
        isOpen = true
        onOpenChange?(true)
        scheduleAdvanceIfDone()
    }

    /// Skip Guide, and closing the window: stores that the guide was seen and closes it.
    public func skipGuide() {
        close()
    }

    /// Finish: the same as ``skipGuide()`` at the end.
    public func finish() {
        close()
    }

    private func close() {
        store.setSeen(true)
        guard isOpen else { return }
        isOpen = false
        onOpenChange?(false)
    }

    // MARK: Buttons

    /// Continue, or Finish on the last step. Answers whether it did something.
    @discardableResult
    public func continueStep() -> Bool {
        guard isOpen else { return false }
        if flow.step == .done {
            finish()
            return true
        }
        guard flow.continueStep() else { return false }
        scheduleAdvanceIfDone()
        return true
    }

    /// Skip. Answers whether it did something.
    @discardableResult
    public func skipStep() -> Bool {
        guard isOpen, flow.skipStep() else { return false }
        scheduleAdvanceIfDone()
        return true
    }

    // MARK: Events

    /// The grant arrived or went away.
    public func setAccessibility(_ granted: Bool) {
        guard isOpen, flow.accessibilityGranted != granted else { return }
        flow.setAccessibility(granted)
        scheduleAdvanceIfDone()
    }

    /// A config was loaded.
    public func configChanged(_ config: Config) {
        guard isOpen else { return }
        flow.updateConfig(config)
    }

    /// A hotkey ran its binding's action.
    public func hotkeyRan(bindingID: UUID, outcome: OnboardingRunOutcome) {
        guard isOpen, flow.hotkeyRan(bindingID: bindingID, outcome: outcome) else { return }
        scheduleAdvanceIfDone()
    }

    private func scheduleAdvanceIfDone() {
        let step = flow.step
        guard isOpen, step != .done, flow.isCurrentDone else { return }
        schedule(Self.advanceDelay) { [weak self] in
            guard let self, self.isOpen, self.flow.autoAdvance(from: step) else { return }
            self.scheduleAdvanceIfDone()
        }
    }
}
