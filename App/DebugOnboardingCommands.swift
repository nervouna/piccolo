#if DEBUG
import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloUI

/// The control commands about the onboarding guide: `onboarding.open`, `onboarding.close`,
/// `onboarding.state`, `onboarding.continue`, `onboarding.skip` and `onboarding.setSeen`. Debug builds
/// only, like the control server itself.
///
/// They drive the same model and panel as the menu's "Getting Started…" and the buttons of the guide.
/// None of them activates Piccolo.
extension DebugControlServer {
    private struct SeenParams: Decodable {
        var seen: Bool
    }

    /// Registers the commands. Every one answers the state, `{visible, step, done: [step],
    /// moveBindingID?, arrangeBindingID?, seen, frame?}`:
    ///
    /// - `visible`: whether the guide is open and its panel on screen.
    /// - `step`: `accessibility`, `moveWindow`, `arrange` or `done`; `done`: the steps that are done.
    /// - `moveBindingID`, `arrangeBindingID`: the bindings steps 2 and 3 ask the user to press.
    /// - `seen`: the stored `OnboardingSeen` flag.
    /// - `frame`: the panel's frame in canonical coordinates, while it is on screen.
    ///
    /// `onboarding.open` opens it as the menu item does (at step 1, or brings it forward when open).
    /// `onboarding.close` closes it as Skip Guide does, which stores `seen`. `onboarding.continue` presses
    /// Continue, which is Finish on the last step, and `onboarding.skip` presses Skip; both answer
    /// `ok: false` when the button is not there or not enabled. `onboarding.setSeen {seen}` sets the stored
    /// flag, so that a test can put back what it found.
    nonisolated static func registerOnboardingCommands(in router: inout ControlRouter) {
        router.register("onboarding.open") { _ in
            onMainActor {
                OnboardingController.shared.show()
                return onboardingState()
            }
        }

        router.register("onboarding.close") { _ in
            onMainActor {
                OnboardingController.shared.close()
                return onboardingState()
            }
        }

        router.register("onboarding.state") { _ in
            onMainActor { onboardingState() }
        }

        router.register("onboarding.continue") { _ in
            try onMainActor {
                let model = OnboardingController.shared.model
                guard model.continueStep() else {
                    throw ControlCommandError.failed(
                        model.isOpen ? "Continue is not enabled at step \(model.flow.step.rawValue)" : "the guide is not open")
                }
                return onboardingState()
            }
        }

        router.register("onboarding.skip") { _ in
            try onMainActor {
                let model = OnboardingController.shared.model
                guard model.skipStep() else {
                    throw ControlCommandError.failed(
                        model.isOpen ? "step \(model.flow.step.rawValue) has no Skip button" : "the guide is not open")
                }
                return onboardingState()
            }
        }

        router.register("onboarding.setSeen") { params in
            let seen = try params.decode(SeenParams.self).seen
            return onMainActor {
                OnboardingController.shared.model.setSeen(seen)
                return onboardingState()
            }
        }
    }

    @MainActor
    private static func onboardingState() -> JSONValue {
        let controller = OnboardingController.shared
        let flow = controller.model.flow
        var state: [String: JSONValue] = [
            "visible": .bool(controller.isVisible),
            "step": .string(flow.step.rawValue),
            "done": .array(
                OnboardingStep.allCases.filter { flow.completed.contains($0) }.map { .string($0.rawValue) }),
            "seen": .bool(controller.model.seen),
        ]
        if let move = flow.move {
            state["moveBindingID"] = .string(move.id.uuidString)
        }
        if let arrange = flow.arrange {
            state["arrangeBindingID"] = .string(arrange.id.uuidString)
        }
        if let frame = controller.frame {
            state["frame"] = JSONValue(rect: frame)
        }
        return .object(state)
    }
}
#endif
