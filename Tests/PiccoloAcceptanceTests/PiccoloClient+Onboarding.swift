import CoreGraphics
import Foundation
import PiccoloControl

/// The commands about the onboarding guide.
extension PiccoloClient {
    /// What `onboarding.state` and the other `onboarding.*` commands answer.
    struct OnboardingState: Equatable {
        var visible: Bool
        /// `accessibility`, `moveWindow`, `arrange` or `done`.
        var step: String
        var done: [String]
        var moveBindingID: UUID?
        var arrangeBindingID: UUID?
        var seen: Bool
        /// The panel's frame in canonical coordinates, while it is on screen.
        var frame: CGRect?
    }

    func onboardingState() throws -> OnboardingState {
        try onboardingCommand("onboarding.state")
    }

    @discardableResult
    func onboardingOpen() throws -> OnboardingState {
        try onboardingCommand("onboarding.open")
    }

    @discardableResult
    func onboardingClose() throws -> OnboardingState {
        try onboardingCommand("onboarding.close")
    }

    @discardableResult
    func onboardingContinue() throws -> OnboardingState {
        try onboardingCommand("onboarding.continue")
    }

    @discardableResult
    func onboardingSkip() throws -> OnboardingState {
        try onboardingCommand("onboarding.skip")
    }

    @discardableResult
    func onboardingSetSeen(_ seen: Bool) throws -> OnboardingState {
        try onboardingCommand("onboarding.setSeen", ["seen": .bool(seen)])
    }

    private func onboardingCommand(_ command: String, _ params: [String: JSONValue] = [:]) throws -> OnboardingState {
        let result = try send(command, params)
        guard let visible = result["visible"]?.boolValue, let step = result["step"]?.stringValue,
            let done = result["done"]?.arrayValue?.compactMap({ $0.stringValue }),
            let seen = result["seen"]?.boolValue
        else {
            throw AcceptanceFailure("\(command) answered something that is not an onboarding state: \(result)")
        }
        return OnboardingState(
            visible: visible, step: step, done: done,
            moveBindingID: result["moveBindingID"]?.stringValue.flatMap { UUID(uuidString: $0) },
            arrangeBindingID: result["arrangeBindingID"]?.stringValue.flatMap { UUID(uuidString: $0) },
            seen: seen, frame: result["frame"]?.rectValue)
    }
}
