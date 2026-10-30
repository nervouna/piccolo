import Foundation
import PiccoloCore
import Testing

@testable import PiccoloUI

/// A seen flag in memory.
@MainActor
final class FakeOnboardingStore: OnboardingStore {
    var isSeen: Bool
    private(set) var isSeenStored: Bool
    private(set) var writes: [Bool] = []
    private(set) var clears = 0

    init(seen: Bool = false) {
        isSeen = seen
        isSeenStored = seen
    }

    func setSeen(_ seen: Bool) {
        writes.append(seen)
        isSeen = seen
        isSeenStored = true
    }

    func clearSeen() {
        clears += 1
        isSeen = false
        isSeenStored = false
    }
}

/// The model around the flow: opening, closing, the stored flag, and the one-second auto-advance.
@MainActor
@Suite("Onboarding model")
struct OnboardingModelTests {
    final class Scheduler {
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
        func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
            pending.append((delay, work))
        }
        @MainActor func fireAll() {
            let work = pending
            pending = []
            for item in work { item.work() }
        }
    }

    let store = FakeOnboardingStore()
    let scheduler = Scheduler()
    let config = Config(bindings: [OnboardingFlowTests.leftHalf, OnboardingFlowTests.twoByOne])

    func model() -> OnboardingModel {
        OnboardingModel(store: store) { [scheduler] delay, work in scheduler.schedule(delay, work) }
    }

    @Test("opening shows step 1, done when granted, and schedules the advance after about a second")
    func open() {
        let model = model()
        model.open(accessibilityGranted: true, config: config)
        #expect(model.isOpen)
        #expect(model.flow.step == .accessibility)
        #expect(model.flow.completed == [.accessibility])
        #expect(scheduler.pending.map(\.delay) == [1.0])
        scheduler.fireAll()
        #expect(model.flow.step == .moveWindow)
    }

    @Test("opening while it is open leaves it at its current step")
    func openAgain() {
        let model = model()
        model.open(accessibilityGranted: true, config: config)
        scheduler.fireAll()
        model.open(accessibilityGranted: true, config: config)
        #expect(model.flow.step == .moveWindow)
        #expect(scheduler.pending.isEmpty)
    }

    @Test("Skip Guide and closing store that it was seen and close it; the next opening starts again")
    func skipGuide() {
        let model = model()
        model.open(accessibilityGranted: false, config: config)
        _ = model.skipStep()
        model.skipGuide()
        #expect(!model.isOpen)
        #expect(store.isSeen)
        model.open(accessibilityGranted: false, config: config)
        #expect(model.flow.step == .accessibility)
    }

    @Test("Finish stores that it was seen and closes it")
    func finish() {
        let model = model()
        model.open(accessibilityGranted: true, config: config)
        _ = model.skipStep()
        _ = model.skipStep()
        _ = model.skipStep()
        #expect(model.flow.step == .done)
        model.finish()
        #expect(!model.isOpen)
        #expect(store.isSeen)
    }

    @Test("opening from the menu works whatever is stored")
    func openWhenSeen() {
        store.isSeen = true
        let model = model()
        model.open(accessibilityGranted: true, config: config)
        #expect(model.isOpen)
    }

    @Test("a hotkey run completes the step and the model advances it after a second")
    func runAdvances() {
        let model = model()
        model.open(accessibilityGranted: true, config: config)
        scheduler.fireAll()
        model.hotkeyRan(bindingID: OnboardingFlowTests.leftHalf.id, outcome: .placed)
        #expect(model.flow.completed.contains(.moveWindow))
        #expect(model.flow.step == .moveWindow)
        #expect(scheduler.pending.count == 1)
        scheduler.fireAll()
        #expect(model.flow.step == .arrange)
    }

    @Test("a run while the guide is closed does nothing")
    func runWhileClosed() {
        let model = model()
        model.hotkeyRan(bindingID: OnboardingFlowTests.leftHalf.id, outcome: .placed)
        #expect(!model.isOpen)
        #expect(scheduler.pending.isEmpty)
    }

    @Test("the grant arriving while the guide waits completes step 1 and advances it")
    func grantWhileOpen() {
        let model = model()
        model.open(accessibilityGranted: false, config: config)
        #expect(scheduler.pending.isEmpty)
        model.setAccessibility(true)
        #expect(scheduler.pending.count == 1)
        scheduler.fireAll()
        #expect(model.flow.step == .moveWindow)
    }

    @Test("the auto-advance of a guide that was closed meanwhile does nothing")
    func advanceAfterClose() {
        let model = model()
        model.open(accessibilityGranted: true, config: config)
        model.skipGuide()
        scheduler.fireAll()
        #expect(model.flow.step == .accessibility)
    }

    @Test("the defaults store writes a boolean under OnboardingSeen")
    func defaultsStore() throws {
        let suite = "io.damao.piccolo.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored = OnboardingDefaults(defaults: defaults)
        #expect(!stored.isSeen)
        #expect(defaults.object(forKey: "OnboardingSeen") == nil)
        stored.setSeen(true)
        #expect(stored.isSeen)
        #expect(defaults.object(forKey: "OnboardingSeen") as? Bool == true)
        stored.setSeen(false)
        #expect(!stored.isSeen)
    }

    @Test("the defaults store removes OnboardingSeen when cleared, so that it reads as never written")
    func defaultsStoreClear() throws {
        let suite = "io.damao.piccolo.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored = OnboardingDefaults(defaults: defaults)
        #expect(!stored.isSeenStored)
        stored.setSeen(false)
        #expect(stored.isSeenStored)
        stored.clearSeen()
        #expect(!stored.isSeenStored)
        #expect(!stored.isSeen)
        #expect(defaults.object(forKey: "OnboardingSeen") == nil)
    }

    @Test("setSeen(nil) on the model removes the stored flag, and a Bool writes it")
    func modelSetSeenNilRemoves() {
        let store = FakeOnboardingStore()
        let model = OnboardingModel(store: store)
        #expect(!model.seenStored)
        model.setSeen(false)
        #expect(model.seenStored)
        #expect(store.writes == [false])
        model.setSeen(nil)
        #expect(!model.seenStored)
        #expect(store.clears == 1)
        #expect(!model.seen)
    }
}
