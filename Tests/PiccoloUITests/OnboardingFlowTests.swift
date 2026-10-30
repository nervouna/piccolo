import Foundation
import PiccoloCore
import Testing

@testable import PiccoloUI

/// The steps of the onboarding guide as a pure state machine: the choice of the bindings it asks the
/// user to press, which hotkey outcomes complete a step, and how the steps follow each other.
@Suite("Onboarding flow")
struct OnboardingFlowTests {
    static let modifiers: Set<Modifier> = [.control, .option]

    static func key(_ code: Int) -> Shortcut { Shortcut(keyCode: code, modifiers: modifiers) }

    static let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: key(123))
    static let rightHalf = KeyBinding(action: .placeWindow(.preset(.rightHalf)), shortcut: key(124))
    static let twoByOne = KeyBinding(action: .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), shortcut: key(18))
    static let fourByFour = KeyBinding(action: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)), shortcut: key(21))

    static func config(_ bindings: [KeyBinding], preview: Bool = true) -> Config {
        Config(destinationPreview: preview, bindings: bindings)
    }

    static func flow(
        granted: Bool = true, _ bindings: [KeyBinding] = [rightHalf, leftHalf, fourByFour, twoByOne], preview: Bool = true
    ) -> OnboardingFlow {
        OnboardingFlow(accessibilityGranted: granted, config: config(bindings, preview: preview))
    }

    // MARK: Choosing the bindings

    @Test("the move step prefers leftHalf, even when another placeWindow binding comes first")
    func prefersLeftHalf() {
        let flow = Self.flow()
        #expect(flow.move?.id == Self.leftHalf.id)
        #expect(flow.move?.shortcut == Self.leftHalf.shortcut)
    }

    @Test("without leftHalf the move step takes the first placeWindow binding with a shortcut")
    func moveFallback() {
        let noShortcut = KeyBinding(action: .placeWindow(.preset(.topHalf)), shortcut: nil)
        let flow = Self.flow([noShortcut, Self.rightHalf, Self.twoByOne])
        #expect(flow.move?.id == Self.rightHalf.id)
    }

    @Test("a leftHalf binding without a shortcut is not chosen")
    func leftHalfWithoutShortcut() {
        let silent = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: nil)
        let flow = Self.flow([silent, Self.rightHalf])
        #expect(flow.move?.id == Self.rightHalf.id)
    }

    @Test("the arrange step prefers 2 windows in 1 × 2, else the first arrangeGrid binding with a shortcut")
    func arrangeChoice() {
        #expect(Self.flow().arrange?.id == Self.twoByOne.id)
        #expect(Self.flow([Self.fourByFour, Self.leftHalf]).arrange?.id == Self.fourByFour.id)
        let noShortcut = KeyBinding(action: .arrangeGrid(GridSpec(count: 3, rows: 1, columns: 3)), shortcut: nil)
        #expect(Self.flow([noShortcut, Self.fourByFour]).arrange?.id == Self.fourByFour.id)
    }

    @Test("with no binding at all both steps have no binding")
    func noBindings() {
        let flow = Self.flow([])
        #expect(flow.move == nil)
        #expect(flow.arrange == nil)
        let others = Self.flow([KeyBinding(action: .restoreWindow, shortcut: Self.key(15))])
        #expect(others.move == nil && others.arrange == nil)
    }

    @Test("the preview sentence follows destinationPreview")
    func previewFlag() {
        #expect(Self.flow(preview: true).destinationPreview)
        #expect(!Self.flow(preview: false).destinationPreview)
    }

    // MARK: Steps and transitions

    @Test("the guide starts at Accessibility, done when the grant is there")
    func start() {
        let granted = Self.flow(granted: true)
        #expect(granted.step == .accessibility)
        #expect(granted.completed == [.accessibility])
        #expect(granted.canContinue)
        let waiting = Self.flow(granted: false)
        #expect(waiting.completed.isEmpty)
        #expect(!waiting.canContinue)
    }

    @Test("the grant arriving completes the Accessibility step; losing it takes the check away")
    func grantArrives() {
        var flow = Self.flow(granted: false)
        flow.setAccessibility(true)
        #expect(flow.completed == [.accessibility])
        #expect(flow.canContinue)
        flow.setAccessibility(false)
        #expect(flow.completed.isEmpty)
    }

    @Test("Continue works only when the step is done, and moves on")
    func continueNeedsDone() {
        var flow = Self.flow(granted: false)
        let result1 = flow.continueStep()
        #expect(!result1)
        #expect(flow.step == .accessibility)
        flow.setAccessibility(true)
        let result2 = flow.continueStep()
        #expect(result2)
        #expect(flow.step == .moveWindow)
        let result3 = flow.continueStep()
        #expect(!result3)
        #expect(flow.step == .moveWindow)
    }

    @Test("Skip moves on without the step being done, through steps 1 to 3 only")
    func skipMovesOn() {
        var flow = Self.flow(granted: false)
        let result4 = flow.skipStep()
        #expect(result4)
        #expect(flow.step == .moveWindow)
        let result5 = flow.skipStep()
        #expect(result5)
        #expect(flow.step == .arrange)
        let result6 = flow.skipStep()
        #expect(result6)
        #expect(flow.step == .done)
        let result7 = flow.skipStep()
        #expect(!result7)
        #expect(flow.step == .done)
        #expect(flow.canContinue, "the last step has Finish at any time")
    }

    @Test("a done step advances by itself, once, and only the step it was scheduled for")
    func autoAdvance() {
        var flow = Self.flow()
        let result8 = flow.autoAdvance(from: .accessibility)
        #expect(result8)
        #expect(flow.step == .moveWindow)
        let result9 = flow.autoAdvance(from: .accessibility)
        #expect(!result9, "the step moved on already")
        let result10 = flow.autoAdvance(from: .moveWindow)
        #expect(!result10, "the move step is not done")
        #expect(flow.step == .moveWindow)
    }

    // MARK: Outcomes

    private func atMove(_ flow: OnboardingFlow = Self.flow()) -> OnboardingFlow {
        var flow = flow
        _ = flow.skipStep()
        return flow
    }

    private func atArrange(_ flow: OnboardingFlow = Self.flow()) -> OnboardingFlow {
        var flow = atMove(flow)
        _ = flow.skipStep()
        return flow
    }

    @Test("a placed window from the chosen binding completes the move step")
    func placedCompletes() {
        var flow = atMove()
        let result11 = flow.hotkeyRan(bindingID: Self.leftHalf.id, outcome: .placed)
        #expect(result11)
        #expect(flow.completed.contains(.moveWindow))
        #expect(flow.canContinue)
    }

    @Test("nothing to do and other outcomes do not complete the move step")
    func otherOutcomesDoNot() {
        var flow = atMove()
        let result12 = flow.hotkeyRan(bindingID: Self.leftHalf.id, outcome: .nothingToDo)
        #expect(!result12)
        let result13 = flow.hotkeyRan(bindingID: Self.leftHalf.id, outcome: .other)
        #expect(!result13)
        let result14 = flow.hotkeyRan(bindingID: Self.leftHalf.id, outcome: .arranged(placed: 2))
        #expect(!result14)
        #expect(!flow.completed.contains(.moveWindow))
    }

    @Test("another binding does not complete the move step")
    func otherBindingDoesNot() {
        var flow = atMove()
        let result15 = flow.hotkeyRan(bindingID: Self.rightHalf.id, outcome: .placed)
        #expect(!result15)
        #expect(!flow.completed.contains(.moveWindow))
    }

    @Test("an arrangement with at least one window placed completes the arrange step; none placed does not")
    func arrangeCompletes() {
        var flow = atArrange()
        let result16 = flow.hotkeyRan(bindingID: Self.twoByOne.id, outcome: .arranged(placed: 0))
        #expect(!result16)
        let result17 = flow.hotkeyRan(bindingID: Self.twoByOne.id, outcome: .nothingToDo)
        #expect(!result17)
        let result18 = flow.hotkeyRan(bindingID: Self.twoByOne.id, outcome: .placed)
        #expect(!result18)
        let result19 = flow.hotkeyRan(bindingID: Self.fourByFour.id, outcome: .arranged(placed: 4))
        #expect(!result19)
        #expect(!flow.completed.contains(.arrange))
        let result20 = flow.hotkeyRan(bindingID: Self.twoByOne.id, outcome: .arranged(placed: 1))
        #expect(result20)
        #expect(flow.completed.contains(.arrange))
    }

    @Test("a run counts for the step that is showing, not for an earlier or later one")
    func onlyTheCurrentStep() {
        var flow = Self.flow()
        let result21 = flow.hotkeyRan(bindingID: Self.leftHalf.id, outcome: .placed)
        #expect(!result21, "the guide is at step 1")
        var arrange = atArrange()
        let result22 = arrange.hotkeyRan(bindingID: Self.leftHalf.id, outcome: .placed)
        #expect(!result22, "the guide is at step 3")
    }

    @Test("steps 2 and 3 do not complete without the Accessibility grant")
    func needsTheGrant() {
        var flow = Self.flow(granted: false)
        _ = flow.skipStep()
        #expect(flow.step == .moveWindow)
        let result23 = flow.hotkeyRan(bindingID: Self.leftHalf.id, outcome: .placed)
        #expect(!result23)
        #expect(!flow.canContinue)
        #expect(!flow.hasGrantForShortcutSteps)
        flow.setAccessibility(true)
        #expect(flow.hasGrantForShortcutSteps)
        let result24 = flow.hotkeyRan(bindingID: Self.leftHalf.id, outcome: .placed)
        #expect(result24)
    }

    @Test("without a binding the steps cannot be completed by a run, and Skip is the way on")
    func noBindingSteps() {
        var flow = atMove(Self.flow([]))
        let result25 = flow.hotkeyRan(bindingID: UUID(), outcome: .placed)
        #expect(!result25)
        let result26 = flow.skipStep()
        #expect(result26)
        #expect(flow.step == .arrange)
    }

    // MARK: When it opens at launch

    @Test(
        "the guide opens at launch on a first launch that was never finished or skipped, and nowhere else",
        arguments: [
            (true, false, true),  // first launch, never seen
            (false, false, false),  // an existing config file
            (true, true, false),  // first launch again (config deleted), but seen
            (false, true, false),
        ])
    func launchRule(wrote: Bool, seen: Bool, opens: Bool) {
        #expect(OnboardingFlow.shouldOpenAtLaunch(wroteDefaultShortcuts: wrote, seen: seen) == opens)
    }
}
