import Foundation
import Testing

@testable import PiccoloCore

/// The rules for a shortcut that is held, as events in and effects out. The timer is not part of the
/// rules: they ask for one with `startTimer(token)` and are told it fired with `timerFired(token)`.
@Suite("Hold rules")
struct HoldRulesTests {
    private let a = UUID()
    private let b = UUID()

    /// Rules with the preview on, the setting a fresh config has.
    private func previewOn() -> HoldRules { HoldRules(isPreviewEnabled: true) }
    private func previewOff() -> HoldRules { HoldRules(isPreviewEnabled: false) }

    /// The token of the timer the last press asked for.
    private func token(of effects: [HoldRules.Effect]) throws -> Int {
        for effect in effects {
            if case .startTimer(let token) = effect { return token }
        }
        throw Failure("no timer was asked for in \(effects)")
    }

    private struct Failure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    // MARK: Preview off

    @Test("preview off: a press runs the action at once")
    func offPressRuns() {
        var rules = previewOff()
        #expect(rules.handle(.press(a)) == [.run(a)])
        #expect(rules.held == nil)
    }

    @Test("preview off: a release is ignored")
    func offReleaseIgnored() {
        var rules = previewOff()
        _ = rules.handle(.press(a))
        #expect(rules.handle(.release(a)) == [])
        #expect(rules.handle(.release(b)) == [])
    }

    @Test("preview off: every press runs, also a repeated one")
    func offEveryPressRuns() {
        var rules = previewOff()
        #expect(rules.handle(.press(a)) == [.run(a)])
        #expect(rules.handle(.press(a)) == [.run(a)])
        #expect(rules.handle(.press(b)) == [.run(b)])
    }

    @Test("preview off: Escape and a timer do nothing")
    func offEscapeIgnored() {
        var rules = previewOff()
        _ = rules.handle(.press(a))
        #expect(rules.handle(.escape) == [])
        #expect(rules.handle(.timerFired(1)) == [])
    }

    @Test("preview off: the press is recorded as a run without a preview")
    func offLast() {
        var rules = previewOff()
        _ = rules.handle(.press(a))
        #expect(rules.last == HoldRules.Outcome(id: a, result: .ran, previewShown: false))
    }

    // MARK: Tap

    @Test("preview on: a press asks for the timer and runs nothing")
    func onPressStartsTimer() throws {
        var rules = previewOn()
        let effects = rules.handle(.press(a))
        #expect(effects.count == 1)
        _ = try token(of: effects)
        #expect(rules.held?.id == a)
        #expect(rules.held?.phase == .waiting)
    }

    @Test("a tap: released before the timer fires, it runs the action on release and shows no preview")
    func tap() throws {
        var rules = previewOn()
        _ = rules.handle(.press(a))
        #expect(rules.handle(.release(a)) == [.run(a)])
        #expect(rules.held == nil)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .ran, previewShown: false))
    }

    @Test("a timer that fires after a tap does nothing")
    func lateTimerAfterTap() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.release(a))
        #expect(rules.handle(.timerFired(timer)) == [])
    }

    // MARK: Hold

    @Test("a hold: when the timer fires the preview for the shortcut is shown")
    func holdShowsPreview() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        #expect(rules.handle(.timerFired(timer)) == [.showPreview(a)])
        #expect(rules.held?.phase == .previewing)
    }

    @Test("a hold: the release hides the preview and then runs the action")
    func holdRelease() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))
        #expect(rules.handle(.release(a)) == [.hidePreview, .run(a)])
        #expect(rules.held == nil)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .ran, previewShown: true))
    }

    @Test("the timer fires only once")
    func timerOnce() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))
        #expect(rules.handle(.timerFired(timer)) == [])
    }

    @Test("a timer of an earlier hold does not show the preview of a later one")
    func staleTimer() throws {
        var rules = previewOn()
        let first = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.release(a))
        let second = try token(of: rules.handle(.press(a)))
        #expect(first != second)

        #expect(rules.handle(.timerFired(first)) == [])
        #expect(rules.held?.phase == .waiting)
        #expect(rules.handle(.timerFired(second)) == [.showPreview(a)])
    }

    // MARK: Escape

    @Test("Escape while the preview shows hides it, and the release then does nothing")
    func escapeWhilePreviewing() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))

        #expect(rules.handle(.escape) == [.hidePreview])
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))
        #expect(rules.held?.id == a, "the shortcut is still held until its release")

        #expect(rules.handle(.release(a)) == [])
        #expect(rules.held == nil)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))
    }

    @Test("Escape before the timer fires cancels the hold: no preview is shown, and the release does nothing")
    func escapeWhileWaiting() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))

        #expect(rules.handle(.escape) == [])
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: false))
        #expect(rules.handle(.timerFired(timer)) == [], "a cancelled hold shows no preview when its timer fires")
        #expect(rules.handle(.release(a)) == [])
        #expect(rules.held == nil)
    }

    @Test("Escape twice hides the preview once")
    func escapeTwice() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))
        #expect(rules.handle(.escape) == [.hidePreview])
        #expect(rules.handle(.escape) == [])
    }

    @Test("Escape with nothing held does nothing")
    func escapeNothingHeld() {
        var rules = previewOn()
        #expect(rules.handle(.escape) == [])
        #expect(rules.last == nil)
    }

    // MARK: A press of the shortcut that is held

    // The system delivers no auto-repeat for a hotkey (see CarbonHotkeyBackend), so a press of the
    // shortcut that is already held can only mean that its release was lost. The old hold is over
    // (cancelled, not run), and the press starts a new one.

    @Test("a press of the held shortcut while waiting cancels the old hold without running it and starts a new one")
    func pressOfHeldWhileWaiting() throws {
        var rules = previewOn()
        let first = try token(of: rules.handle(.press(a)))

        let effects = rules.handle(.press(a))

        #expect(!effects.contains(.run(a)))
        #expect(!effects.contains(.hidePreview), "no preview was shown yet")
        let second = try token(of: effects)
        #expect(first != second)
        #expect(rules.held?.id == a)
        #expect(rules.held?.phase == .waiting)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: false))

        // The old hold's timer is stale; the new one shows the preview.
        #expect(rules.handle(.timerFired(first)) == [])
        #expect(rules.handle(.timerFired(second)) == [.showPreview(a)])
    }

    @Test("a press of the held shortcut while the preview shows hides it and starts a new hold")
    func pressOfHeldWhilePreviewing() throws {
        var rules = previewOn()
        let first = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(first))

        let effects = rules.handle(.press(a))

        #expect(effects.first == .hidePreview)
        #expect(!effects.contains(.run(a)))
        let second = try token(of: effects)
        #expect(rules.held?.phase == .waiting)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))

        #expect(rules.handle(.timerFired(first)) == [])
        #expect(rules.handle(.timerFired(second)) == [.showPreview(a)])
        #expect(rules.handle(.release(a)) == [.hidePreview, .run(a)])
    }

    @Test("a press of the held shortcut after Escape starts a new hold, whose release runs the action")
    func pressOfHeldAfterEscape() throws {
        var rules = previewOn()
        let first = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(first))
        _ = rules.handle(.escape)

        let effects = rules.handle(.press(a))

        #expect(!effects.contains(.hidePreview), "Escape hid the preview already")
        _ = try token(of: effects)
        #expect(rules.held?.phase == .waiting)
        #expect(
            rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true),
            "the outcome Escape recorded stays until the new hold ends")

        #expect(rules.handle(.release(a)) == [.run(a)])
        #expect(rules.last == HoldRules.Outcome(id: a, result: .ran, previewShown: false))
    }

    @Test("with a lost release the shortcut is not dead: the next press and release run the action")
    func lostReleaseDoesNotKillTheShortcut() throws {
        var rules = previewOn()
        let first = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(first))
        // The release never comes. The user presses the shortcut again.
        _ = rules.handle(.press(a))

        #expect(rules.handle(.release(a)) == [.run(a)])
        #expect(rules.held == nil)
    }

    // MARK: Another shortcut

    @Test("a press of another shortcut while one is waiting cancels it without an action and takes over")
    func otherPressWhileWaiting() throws {
        var rules = previewOn()
        _ = rules.handle(.press(a))

        let effects = rules.handle(.press(b))
        #expect(!effects.contains(.run(a)))
        #expect(!effects.contains(.hidePreview), "no preview was shown yet")
        _ = try token(of: effects)
        #expect(rules.held?.id == b)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: false))
    }

    @Test("a press of another shortcut while the preview shows hides it, runs nothing, and starts the new hold")
    func otherPressWhilePreviewing() throws {
        var rules = previewOn()
        let first = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(first))

        let effects = rules.handle(.press(b))
        #expect(effects.first == .hidePreview)
        #expect(!effects.contains(.run(a)))
        let second = try token(of: effects)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))

        // The first shortcut's timer is stale; the new one shows the new preview.
        #expect(rules.handle(.timerFired(first)) == [])
        #expect(rules.handle(.timerFired(second)) == [.showPreview(b)])
        #expect(rules.handle(.release(b)) == [.hidePreview, .run(b)])
    }

    @Test("after another shortcut took over, the release of the first is ignored")
    func releaseOfTheCancelledOne() throws {
        var rules = previewOn()
        _ = rules.handle(.press(a))
        _ = rules.handle(.press(b))

        #expect(rules.handle(.release(a)) == [])
        #expect(rules.held?.id == b)
        #expect(rules.handle(.release(b)) == [.run(b)])
    }

    @Test("a press of another shortcut after Escape starts a new hold; the cancelled one stays cancelled")
    func otherPressAfterEscape() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))
        _ = rules.handle(.escape)

        let effects = rules.handle(.press(b))
        #expect(!effects.contains(.hidePreview), "the preview was hidden by Escape already")
        _ = try token(of: effects)
        #expect(rules.held?.id == b)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))
    }

    // MARK: Stray release

    @Test("a release with nothing held is ignored")
    func strayReleaseNothingHeld() {
        var rules = previewOn()
        #expect(rules.handle(.release(a)) == [])
        #expect(rules.last == nil)
    }

    @Test("a release of a shortcut that is not the held one is ignored")
    func strayReleaseOfAnother() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))

        #expect(rules.handle(.release(b)) == [])
        #expect(rules.held?.id == a)
        #expect(rules.held?.phase == .previewing, "the preview of the held shortcut stays")
    }

    // MARK: Cancel all

    @Test("cancel-all with nothing held does nothing")
    func cancelAllNothingHeld() {
        var rules = previewOn()
        #expect(rules.handle(.cancelAll) == [])
    }

    @Test("cancel-all while waiting drops the hold without running it")
    func cancelAllWaiting() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))

        #expect(rules.handle(.cancelAll) == [])
        #expect(rules.held == nil)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: false))
        #expect(rules.handle(.timerFired(timer)) == [])
        #expect(rules.handle(.release(a)) == [], "the release of a dropped hold does not run the action")
    }

    @Test("cancel-all while the preview shows hides it and drops the hold without running it")
    func cancelAllPreviewing() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))

        #expect(rules.handle(.cancelAll) == [.hidePreview])
        #expect(rules.held == nil)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))
        #expect(rules.handle(.release(a)) == [])
    }

    @Test("cancel-all after Escape drops the hold and keeps the outcome Escape recorded")
    func cancelAllAfterEscape() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))
        _ = rules.handle(.escape)

        #expect(rules.handle(.cancelAll) == [])
        #expect(rules.held == nil)
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))
    }

    @Test("after cancel-all a new press starts a new hold")
    func pressAfterCancelAll() throws {
        var rules = previewOn()
        _ = rules.handle(.press(a))
        _ = rules.handle(.cancelAll)

        let timer = try token(of: rules.handle(.press(a)))
        #expect(rules.held?.id == a)
        #expect(rules.handle(.timerFired(timer)) == [.showPreview(a)])
    }

    // MARK: Switching the preview off

    @Test("switching the preview off cancels the hold, and the next press runs at once")
    func switchingOff() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))

        #expect(rules.setPreviewEnabled(false) == [.hidePreview])
        #expect(rules.held == nil)
        #expect(rules.isPreviewEnabled == false)
        #expect(rules.handle(.press(a)) == [.run(a)])
    }

    @Test("switching the preview on or leaving it as it is cancels nothing")
    func switchingOn() throws {
        var rules = previewOff()
        #expect(rules.setPreviewEnabled(true) == [])

        _ = rules.handle(.press(a))
        #expect(rules.setPreviewEnabled(true) == [], "the setting did not change")
        #expect(rules.held?.id == a)
    }

    @Test("a press that finds the preview off while something is held cancels the hold first")
    func pressWhenSwitchedOffBehindOurBack() throws {
        var rules = previewOn()
        let timer = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(timer))
        rules.isPreviewEnabled = false

        let effects = rules.handle(.press(b))
        #expect(effects == [.hidePreview, .run(b)])
        #expect(rules.held == nil)
    }

    // MARK: Sequence

    @Test("a hold, a tap and a cancelled hold in a row each leave their own outcome")
    func sequence() throws {
        var rules = previewOn()

        let t1 = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(t1))
        #expect(rules.handle(.release(a)) == [.hidePreview, .run(a)])

        _ = rules.handle(.press(b))
        #expect(rules.handle(.release(b)) == [.run(b)])
        #expect(rules.last == HoldRules.Outcome(id: b, result: .ran, previewShown: false))

        let t3 = try token(of: rules.handle(.press(a)))
        _ = rules.handle(.timerFired(t3))
        _ = rules.handle(.escape)
        _ = rules.handle(.release(a))
        #expect(rules.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))
        #expect(rules.held == nil)
    }
}
