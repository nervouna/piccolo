import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

@MainActor
@Suite("Hotkey registrar")
struct HotkeyRegistrarTests {
    private let backend = FakeHotkeyBackend()
    private let registrar: HotkeyRegistrar

    init() {
        registrar = HotkeyRegistrar(backend: backend)
    }

    private let all: Set<Modifier> = [.control, .option, .shift, .command]

    private func registration(_ keyCode: Int, _ modifiers: Set<Modifier>? = nil) -> ShortcutPlan.Registration {
        ShortcutPlan.Registration(
            id: UUID(), shortcut: Shortcut(keyCode: keyCode, modifiers: modifiers ?? all))
    }

    /// A handler that records the IDs it is called with.
    private final class Pressed {
        var ids: [UUID] = []
    }

    // MARK: Empty plan

    @Test("an empty plan registers nothing and reports nothing")
    func emptyPlan() {
        let refusals = registrar.apply([]) { _ in }
        #expect(refusals.isEmpty)
        #expect(registrar.registered.isEmpty)
        #expect(backend.calls.isEmpty)
    }

    @Test("an empty plan releases everything that was registered")
    func emptyPlanReleasesEverything() {
        registrar.apply([registration(FunctionKey.f13), registration(FunctionKey.f14)]) { _ in }
        #expect(backend.live.count == 2)

        let refusals = registrar.apply([]) { _ in }
        #expect(refusals.isEmpty)
        #expect(registrar.registered.isEmpty)
        #expect(backend.live.isEmpty)
    }

    // MARK: Registering

    @Test("every shortcut of the plan is registered, in order")
    func registersEverything() {
        let plan = [registration(FunctionKey.f13), registration(FunctionKey.f14), registration(FunctionKey.f15)]
        let refusals = registrar.apply(plan) { _ in }

        #expect(refusals.isEmpty)
        #expect(registrar.registered == plan)
        #expect(backend.liveShortcuts == plan.map(\.shortcut))
    }

    @Test("the backend gets the whole shortcut, key code and modifiers")
    func backendGetsTheShortcut() {
        let plan = [registration(FunctionKey.f16, [.command, .shift])]
        registrar.apply(plan) { _ in }

        guard case .register(let shortcut, _)? = backend.calls.first else {
            Issue.record("the backend was not asked to register anything: \(backend.calls)")
            return
        }
        #expect(shortcut == Shortcut(keyCode: FunctionKey.f16, modifiers: [.command, .shift]))
    }

    // MARK: Replacing

    @Test("a second plan replaces the first: afterwards exactly its shortcuts are registered")
    func replaces() {
        let first = [registration(FunctionKey.f13), registration(FunctionKey.f14)]
        let second = [registration(FunctionKey.f15), registration(FunctionKey.f16)]

        registrar.apply(first) { _ in }
        let refusals = registrar.apply(second) { _ in }

        #expect(refusals.isEmpty)
        #expect(registrar.registered == second)
        #expect(backend.liveShortcuts == second.map(\.shortcut))
    }

    @Test("a shortcut that stays in the plan is registered again without being refused")
    func replacingKeepsAShortcut() {
        let kept = registration(FunctionKey.f13)
        let dropped = registration(FunctionKey.f14)
        registrar.apply([kept, dropped]) { _ in }

        // The same shortcut under a new binding ID, as when the config is reloaded.
        let again = ShortcutPlan.Registration(id: UUID(), shortcut: kept.shortcut)
        let refusals = registrar.apply([again]) { _ in }

        #expect(refusals.isEmpty, "the old registration was not released before the new one: \(refusals)")
        #expect(registrar.registered == [again])
        #expect(backend.liveShortcuts == [kept.shortcut])
    }

    @Test("applying the same plan twice leaves it registered")
    func applyingTwice() {
        let plan = [registration(FunctionKey.f13), registration(FunctionKey.f14)]
        registrar.apply(plan) { _ in }
        let refusals = registrar.apply(plan) { _ in }

        #expect(refusals.isEmpty)
        #expect(registrar.registered == plan)
        #expect(backend.live.count == 2)
    }

    // MARK: Refusals

    @Test("a refused shortcut is reported with its binding ID and the reason, and the others still register")
    func refusedShortcut() {
        let good1 = registration(FunctionKey.f13)
        let bad = registration(FunctionKey.f14)
        let good2 = registration(FunctionKey.f15)
        backend.refuse(bad.shortcut, reason: "taken by the system")

        let refusals = registrar.apply([good1, bad, good2]) { _ in }

        #expect(refusals == [HotkeyRegistrar.Refusal(id: bad.id, reason: "taken by the system")])
        #expect(registrar.registered == [good1, good2])
        #expect(backend.liveShortcuts == [good1.shortcut, good2.shortcut])
    }

    @Test("every refusal is reported, in input order")
    func severalRefusals() {
        let a = registration(FunctionKey.f13)
        let b = registration(FunctionKey.f14)
        let c = registration(FunctionKey.f15)
        backend.refuse(a.shortcut, reason: "first")
        backend.refuse(c.shortcut, reason: "third")

        let refusals = registrar.apply([a, b, c]) { _ in }

        #expect(
            refusals == [
                HotkeyRegistrar.Refusal(id: a.id, reason: "first"),
                HotkeyRegistrar.Refusal(id: c.id, reason: "third"),
            ])
        #expect(registrar.registered == [b])
    }

    @Test("a shortcut the plan lists twice is refused the second time")
    func duplicateInPlan() {
        let first = registration(FunctionKey.f13)
        let second = ShortcutPlan.Registration(id: UUID(), shortcut: first.shortcut)

        let refusals = registrar.apply([first, second]) { _ in }

        #expect(refusals.map(\.id) == [second.id])
        #expect(registrar.registered == [first])
    }

    @Test("a refusal of the earlier plan does not carry over")
    func refusalsDoNotCarryOver() {
        let bad = registration(FunctionKey.f13)
        backend.refuse(bad.shortcut, reason: "taken")
        #expect(registrar.apply([bad]) { _ in }.count == 1)

        let good = registration(FunctionKey.f14)
        #expect(registrar.apply([good]) { _ in }.isEmpty)
        #expect(registrar.registered == [good])
    }

    // MARK: Pressing

    @Test("pressing a shortcut calls the handler with the ID of its binding")
    func pressCallsHandler() {
        let a = registration(FunctionKey.f13)
        let b = registration(FunctionKey.f14)
        let pressed = Pressed()
        registrar.apply([a, b]) { pressed.ids.append($0) }

        backend.press(b.shortcut)
        backend.press(a.shortcut)
        backend.press(b.shortcut)

        #expect(pressed.ids == [b.id, a.id, b.id])
    }

    @Test("after a replace only the new handler is called, for the new bindings")
    func pressAfterReplace() {
        let old = registration(FunctionKey.f13)
        let new = registration(FunctionKey.f14)
        let oldPressed = Pressed()
        let newPressed = Pressed()

        registrar.apply([old]) { oldPressed.ids.append($0) }
        registrar.apply([new]) { newPressed.ids.append($0) }
        backend.press(old.shortcut)
        backend.press(new.shortcut)

        #expect(oldPressed.ids.isEmpty)
        #expect(newPressed.ids == [new.id])
    }

    @Test("a press the system delivers for a released shortcut is ignored, even if the shortcut was registered again")
    func stalePress() throws {
        let kept = registration(FunctionKey.f13)
        let pressed = Pressed()
        registrar.apply([kept]) { pressed.ids.append($0) }
        let staleID = try #require(backend.hotkeyID(of: kept.shortcut))

        let again = ShortcutPlan.Registration(id: UUID(), shortcut: kept.shortcut)
        registrar.apply([again]) { pressed.ids.append($0) }
        backend.pressStale(hotkeyID: staleID)

        #expect(pressed.ids.isEmpty, "a press for the old registration reached the handler: \(pressed.ids)")

        backend.press(kept.shortcut)
        #expect(pressed.ids == [again.id])
    }

    @Test("a refused shortcut never reaches the handler")
    func refusedShortcutIsNotPressable() {
        let bad = registration(FunctionKey.f13)
        backend.refuse(bad.shortcut, reason: "taken")
        let pressed = Pressed()
        registrar.apply([bad]) { pressed.ids.append($0) }

        backend.press(bad.shortcut)

        #expect(pressed.ids.isEmpty)
    }
}
