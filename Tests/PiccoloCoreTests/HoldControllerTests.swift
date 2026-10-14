import Foundation
import Testing

@testable import PiccoloCore

/// A timer that fires when the test says so.
@MainActor
final class ManualHoldTimer: HoldTimer {
    struct Scheduled {
        var delay: TimeInterval
        var fire: @MainActor () -> Void
        var isCancelled = false
    }

    private(set) var scheduled: [Scheduled] = []

    func schedule(
        after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void {
        scheduled.append(Scheduled(delay: delay, fire: fire))
        let index = scheduled.count - 1
        return { [unowned self] in scheduled[index].isCancelled = true }
    }

    /// Fires every timer that was started and not cancelled, as if their time had come. A timer fires
    /// at most once.
    func fireDue() {
        for index in scheduled.indices where !scheduled[index].isCancelled {
            scheduled[index].isCancelled = true
            scheduled[index].fire()
        }
    }

    /// How many timers are waiting to fire.
    var pending: Int {
        scheduled.filter { !$0.isCancelled }.count
    }
}

@MainActor
@Suite("Hold controller")
struct HoldControllerTests {
    private let a = UUID()
    private let b = UUID()
    private let timer = ManualHoldTimer()
    private let controller: HoldController
    private final class Seen {
        var effects: [HoldRules.Effect] = []
    }
    private let seen = Seen()

    init() {
        controller = HoldController(timer: timer)
        let seen = seen
        controller.onEffect = { seen.effects.append($0) }
    }

    @Test("a press starts a timer of 0.2 s and delivers no effect")
    func pressStartsTimer() {
        controller.send(.press(a))
        #expect(timer.scheduled.count == 1)
        #expect(timer.scheduled.first?.delay == 0.2)
        #expect(seen.effects.isEmpty)
    }

    @Test("a tap: the release runs the action, no preview is shown, and the timer is cancelled")
    func tap() {
        controller.send(.press(a))
        controller.send(.release(a))
        #expect(seen.effects == [.run(a)])
        #expect(timer.pending == 0)

        timer.fireDue()
        #expect(seen.effects == [.run(a)], "a timer that was cancelled must not show a preview")
    }

    @Test("a hold: the timer shows the preview, the release hides it and runs the action")
    func hold() {
        controller.send(.press(a))
        timer.fireDue()
        #expect(seen.effects == [.showPreview(a)])
        #expect(controller.held?.phase == .previewing)

        controller.send(.release(a))
        #expect(seen.effects == [.showPreview(a), .hidePreview, .run(a)])
        #expect(controller.held == nil)
    }

    @Test("Escape while held: the preview is hidden, the release runs nothing")
    func escape() {
        controller.send(.press(a))
        timer.fireDue()
        controller.send(.escape)
        controller.send(.release(a))

        #expect(seen.effects == [.showPreview(a), .hidePreview])
        #expect(controller.last == HoldRules.Outcome(id: a, result: .cancelled, previewShown: true))
    }

    @Test("another shortcut takes over: the first one's timer is cancelled and the second one gets a timer")
    func takeOver() {
        controller.send(.press(a))
        controller.send(.press(b))
        #expect(timer.pending == 1, "only the new hold's timer may be waiting")

        timer.fireDue()
        #expect(seen.effects == [.showPreview(b)])
    }

    @Test("a press of the held shortcut (its release was lost) replaces the timer: only the new hold's timer waits")
    func pressOfHeld() {
        controller.send(.press(a))
        controller.send(.press(a))
        #expect(timer.scheduled.count == 2)
        #expect(timer.pending == 1)

        timer.fireDue()
        #expect(seen.effects == [.showPreview(a)], "one preview, from the new hold")
    }

    @Test("cancel-all stops the timer and hides a preview that shows")
    func cancelAll() {
        controller.send(.press(a))
        timer.fireDue()
        controller.send(.cancelAll)
        #expect(seen.effects == [.showPreview(a), .hidePreview])

        controller.send(.press(b))
        controller.send(.cancelAll)
        #expect(timer.pending == 0)
    }

    @Test("switching the preview off cancels the hold; a press then runs at once")
    func switchingOff() {
        controller.send(.press(a))
        timer.fireDue()
        controller.setPreviewEnabled(false)
        #expect(seen.effects == [.showPreview(a), .hidePreview])
        #expect(controller.isPreviewEnabled == false)

        controller.send(.press(b))
        #expect(seen.effects.last == .run(b))
        #expect(timer.pending == 0)
    }

    @Test("with the preview off a press never starts a timer")
    func previewOffNoTimer() {
        let off = HoldController(timer: timer, isPreviewEnabled: false)
        off.send(.press(a))
        #expect(timer.scheduled.isEmpty)
    }
}
