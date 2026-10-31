import AppKit
import Observation
import PiccoloCore
import PiccoloSystem
import PiccoloUI

/// The stored "seen" flag of the guide: `OnboardingSeen` in Piccolo's own defaults domain.
@MainActor
final class DefaultsOnboardingStore: OnboardingStore {
    private let defaults = OnboardingDefaults()

    var isSeen: Bool {
        defaults.isSeen
    }

    var isSeenStored: Bool {
        defaults.isSeenStored
    }

    func setSeen(_ seen: Bool) {
        defaults.setSeen(seen)
    }

    func clearSeen() {
        defaults.clearSeen()
    }
}

/// The onboarding guide of the running app: one model, one panel.
///
/// It opens at launch on a first launch that was never finished or skipped (`start(wroteDefaults:)`),
/// and from the menu's "Getting Started…" (`show()`). Hotkey runs reach it through
/// ``hotkeyRan(bindingID:outcome:)``, called by `ConfigController` on the main thread; `action.run` on
/// the control channel does not.
///
/// The panel never activates Piccolo (see `OnboardingPanel`), so the application the user works in stays
/// frontmost and the shortcuts the guide asks for act on its focused window.
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()

    let model: OnboardingModel
    private let panel: OnboardingPanel

    private init() {
        let model = OnboardingModel(store: DefaultsOnboardingStore())
        self.model = model
        panel = OnboardingPanel(
            model: model,
            host: OnboardingHost(
                openAccessibilitySettings: { AccessibilityPermission().openSettings() },
                openSettings: { SettingsController.shared.show() }))
        model.onOpenChange = { [weak self] isOpen in
            guard let self else { return }
            if isOpen {
                self.panel.show(in: self.visibleFrameOfDisplayWithMouse())
                self.observeAccessibility()
            } else {
                self.panel.hide()
            }
        }
        ConfigController.shared.onLoad = { [weak self] in
            guard let self else { return }
            self.model.configChanged(ConfigController.shared.config)
        }
    }

    /// Opens the guide when the launch was a first one (`wroteDefaults`) and it was never seen.
    func start(wroteDefaults: Bool) {
        if model.shouldOpenAtLaunch(wroteDefaultShortcuts: wroteDefaults) {
            show()
        }
    }

    /// Opens the guide at step 1, or brings it forward at its current step when it is open.
    func show() {
        if model.isOpen {
            panel.show(in: visibleFrameOfDisplayWithMouse())
            return
        }
        model.open(
            accessibilityGranted: AccessibilityStatus.shared.isTrusted, config: ConfigController.shared.config)
    }

    /// Closes the guide as Skip Guide does: stores that it was seen.
    func close() {
        model.skipGuide()
    }

    var isVisible: Bool { panel.isVisible }

    /// The panel's frame in canonical coordinates, while it is on screen.
    var frame: CGRect? { panel.canonicalFrame }

    /// A hotkey ran the action of a binding without failing.
    func hotkeyRan(bindingID: UUID, outcome: ActionOutcome) {
        model.hotkeyRan(bindingID: bindingID, outcome: Self.runOutcome(of: outcome))
    }

    static func runOutcome(of outcome: ActionOutcome) -> OnboardingRunOutcome {
        switch outcome {
        case .placed:
            return .placed
        case .arranged(let arranged):
            let placed = arranged.windows.filter {
                if case .placed = $0.result { return true }
                return false
            }.count
            return .arranged(placed: placed)
        case .nothingToDo:
            return .nothingToDo
        case .dividerMove, .swap:
            return .other
        }
    }

    /// Follows the Accessibility grant for as long as the guide is open, so that step 1 is done as
    /// soon as the grant is there, without a restart.
    private func observeAccessibility() {
        guard model.isOpen else { return }
        withObservationTracking {
            _ = AccessibilityStatus.shared.isTrusted
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.model.isOpen else { return }
                self.model.setAccessibility(AccessibilityStatus.shared.isTrusted)
                self.observeAccessibility()
            }
        }
    }

    /// The visible frame, in canonical coordinates, of the display with the mouse.
    private func visibleFrameOfDisplayWithMouse() -> CGRect {
        let screens = Screens.current()
        guard let primary = screens.first else { return .zero }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
        let screen = screens.first { $0.frame.contains(point) } ?? primary
        return screen.visibleFrame
    }
}
