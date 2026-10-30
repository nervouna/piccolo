import Foundation
import PiccoloCore

/// The steps of the onboarding guide, in order. The raw value is the name the debug control channel uses.
public enum OnboardingStep: String, CaseIterable, Sendable, Codable {
    /// Piccolo needs the Accessibility grant to move windows.
    case accessibility
    /// Press the shortcut of a `leftHalf` binding.
    case moveWindow
    /// Click two windows in turn and press the shortcut of an `arrangeGrid` binding.
    case arrange
    /// Every shortcut can be changed in Settings.
    case done
}

/// What a hotkey run came to, as far as the guide cares. The app maps `ActionOutcome` to it.
public enum OnboardingRunOutcome: Equatable, Sendable {
    /// A single window was placed.
    case placed
    /// An arrangement ran; `placed` of its windows reached their cells.
    case arranged(placed: Int)
    /// The action found nothing to do.
    case nothingToDo
    /// Any other result (a divider move).
    case other
}

/// The binding a step asks the user to press, and the shortcut to draw.
public struct OnboardingTarget: Equatable, Sendable {
    public var id: UUID
    public var shortcut: Shortcut

    public init(id: UUID, shortcut: Shortcut) {
        self.id = id
        self.shortcut = shortcut
    }
}

/// The state of the onboarding guide, without a window: the step it shows, which steps are done, the
/// bindings the steps ask for and the rules for what completes a step.
///
/// A step is completed only while it is the one showing, and steps 2 and 3 only while the
/// Accessibility grant is there. The auto-advance after about a second belongs to ``OnboardingModel``,
/// which owns the timer; the flow only says whether the advance applies (``autoAdvance(from:)``).
public struct OnboardingFlow: Equatable, Sendable {
    public private(set) var step: OnboardingStep
    /// The steps that are done. ``OnboardingStep/accessibility`` follows the grant at all times.
    public private(set) var completed: Set<OnboardingStep>
    public private(set) var accessibilityGranted: Bool
    /// The binding of step 2, or `nil` when no `placeWindow` binding has a shortcut.
    public private(set) var move: OnboardingTarget?
    /// The binding of step 3, or `nil` when no `arrangeGrid` binding has a shortcut.
    public private(set) var arrange: OnboardingTarget?
    /// Whether the config in effect shows the destination preview of a held shortcut.
    public private(set) var destinationPreview: Bool

    public init(accessibilityGranted: Bool, config: Config) {
        step = .accessibility
        completed = accessibilityGranted ? [.accessibility] : []
        self.accessibilityGranted = accessibilityGranted
        move = Self.moveTarget(in: config)
        arrange = Self.arrangeTarget(in: config)
        destinationPreview = config.destinationPreview
    }

    // MARK: Reading

    /// Whether the step that is showing is done.
    public var isCurrentDone: Bool {
        completed.contains(step)
    }

    /// Whether Continue (Finish on the last step) is enabled.
    public var canContinue: Bool {
        step == .done || isCurrentDone
    }

    /// Whether steps 2 and 3 can work: they need the Accessibility grant.
    public var hasGrantForShortcutSteps: Bool {
        accessibilityGranted
    }

    /// Whether the guide opens at launch: on a first launch (the default shortcuts were written to a
    /// missing config file) when it was never finished or skipped. An existing user never sees it there.
    public static func shouldOpenAtLaunch(wroteDefaultShortcuts: Bool, seen: Bool) -> Bool {
        wroteDefaultShortcuts && !seen
    }

    // MARK: Choosing the bindings

    /// The first `placeWindow` `leftHalf` binding with a shortcut; without one, the first `placeWindow`
    /// binding with a shortcut.
    static func moveTarget(in config: Config) -> OnboardingTarget? {
        let candidates = config.bindings.filter { binding in
            if case .placeWindow = binding.action { return binding.shortcut != nil }
            return false
        }
        let chosen =
            candidates.first { $0.action == .placeWindow(.preset(.leftHalf)) } ?? candidates.first
        return chosen.flatMap(target)
    }

    /// The first `arrangeGrid` binding for 2 windows in 1 × 2 with a shortcut; without one, the first
    /// `arrangeGrid` binding with a shortcut.
    static func arrangeTarget(in config: Config) -> OnboardingTarget? {
        let candidates = config.bindings.filter { binding in
            if case .arrangeGrid = binding.action { return binding.shortcut != nil }
            return false
        }
        let preferred = Action.arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2))
        let chosen = candidates.first { $0.action == preferred } ?? candidates.first
        return chosen.flatMap(target)
    }

    private static func target(_ binding: KeyBinding) -> OnboardingTarget? {
        binding.shortcut.map { OnboardingTarget(id: binding.id, shortcut: $0) }
    }

    // MARK: Changes

    /// Takes the bindings and the preview setting from a config that has been loaded.
    public mutating func updateConfig(_ config: Config) {
        move = Self.moveTarget(in: config)
        arrange = Self.arrangeTarget(in: config)
        destinationPreview = config.destinationPreview
    }

    /// The grant arrived (or went away). Step 1 is done as long as the grant is there.
    public mutating func setAccessibility(_ granted: Bool) {
        accessibilityGranted = granted
        if granted {
            completed.insert(.accessibility)
        } else {
            completed.remove(.accessibility)
        }
    }

    /// A hotkey of binding `bindingID` ran its action with `outcome`. Completes the showing step when
    /// it is the step's binding and the run did what the step asks: a placed window, or an
    /// arrangement that placed at least one window. Answers whether the step was completed by it.
    @discardableResult
    public mutating func hotkeyRan(bindingID: UUID, outcome: OnboardingRunOutcome) -> Bool {
        guard accessibilityGranted, !completed.contains(step) else { return false }
        switch (step, outcome) {
        case (.moveWindow, .placed):
            guard bindingID == move?.id else { return false }
        case (.arrange, .arranged(let placed)):
            guard bindingID == arrange?.id, placed >= 1 else { return false }
        default:
            return false
        }
        completed.insert(step)
        return true
    }

    /// Continue: moves on when the step is done. Answers whether it did (the last step has no next).
    @discardableResult
    public mutating func continueStep() -> Bool {
        guard canContinue, step != .done else { return false }
        return moveOn()
    }

    /// Skip: moves on without the step being done. Steps 1 to 3 only.
    @discardableResult
    public mutating func skipStep() -> Bool {
        guard step != .done else { return false }
        return moveOn()
    }

    /// The advance that follows a done step by itself: applies only when `scheduledFor` is still the
    /// showing step and it is done.
    @discardableResult
    public mutating func autoAdvance(from scheduledFor: OnboardingStep) -> Bool {
        guard step == scheduledFor, step != .done, isCurrentDone else { return false }
        return moveOn()
    }

    private mutating func moveOn() -> Bool {
        guard let index = OnboardingStep.allCases.firstIndex(of: step),
            index + 1 < OnboardingStep.allCases.count
        else { return false }
        step = OnboardingStep.allCases[index + 1]
        return true
    }
}
