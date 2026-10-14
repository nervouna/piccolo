import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

@MainActor
@Suite("Hotkey registrar: release and temporary hotkey")
struct HotkeyRegistrarReleaseTests {
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

    private final class Seen {
        var presses: [UUID] = []
        var releases: [UUID] = []
        var temporaryPresses = 0
    }

    // MARK: Release

    @Test("releasing a shortcut calls the release handler with the ID of its binding")
    func releaseCallsHandler() {
        let a = registration(FunctionKey.f13)
        let b = registration(FunctionKey.f14)
        let seen = Seen()
        registrar.apply([a, b], onRelease: { seen.releases.append($0) }, handler: { seen.presses.append($0) })

        backend.press(b.shortcut)
        backend.release(b.shortcut)
        backend.press(a.shortcut)
        backend.release(a.shortcut)

        #expect(seen.presses == [b.id, a.id])
        #expect(seen.releases == [b.id, a.id])
    }

    @Test("a registrar applied without a release handler ignores releases")
    func noReleaseHandler() {
        let a = registration(FunctionKey.f13)
        let seen = Seen()
        registrar.apply([a]) { seen.presses.append($0) }

        backend.press(a.shortcut)
        backend.release(a.shortcut)

        #expect(seen.presses == [a.id])
        #expect(seen.releases.isEmpty)
    }

    @Test("a release the system delivers for a replaced registration is ignored")
    func staleRelease() throws {
        let kept = registration(FunctionKey.f13)
        let seen = Seen()
        registrar.apply([kept], onRelease: { seen.releases.append($0) }, handler: { _ in })
        let staleID = try #require(backend.hotkeyID(of: kept.shortcut))

        let again = ShortcutPlan.Registration(id: UUID(), shortcut: kept.shortcut)
        registrar.apply([again], onRelease: { seen.releases.append($0) }, handler: { _ in })
        backend.releaseStale(hotkeyID: staleID)

        #expect(seen.releases.isEmpty, "a release for the old registration reached the handler: \(seen.releases)")
        backend.release(kept.shortcut)
        #expect(seen.releases == [again.id])
    }

    @Test("after a replace only the new release handler is called")
    func releaseAfterReplace() {
        let old = registration(FunctionKey.f13)
        let new = registration(FunctionKey.f14)
        let oldSeen = Seen()
        let newSeen = Seen()
        registrar.apply([old], onRelease: { oldSeen.releases.append($0) }, handler: { _ in })
        registrar.apply([new], onRelease: { newSeen.releases.append($0) }, handler: { _ in })

        backend.release(old.shortcut)
        backend.release(new.shortcut)

        #expect(oldSeen.releases.isEmpty)
        #expect(newSeen.releases == [new.id])
    }

    // MARK: Temporary hotkey

    private let escapeWithCommand = Shortcut(keyCode: 53, modifiers: [.command])

    @Test("a temporary hotkey is registered with the backend, and its press calls its own handler, not the bindings'")
    func temporaryHotkey() throws {
        let a = registration(FunctionKey.f13)
        let seen = Seen()
        registrar.apply([a], onRelease: { seen.releases.append($0) }, handler: { seen.presses.append($0) })

        try registrar.registerTemporary(escapeWithCommand) { seen.temporaryPresses += 1 }
        #expect(backend.liveShortcuts.contains(escapeWithCommand))
        #expect(registrar.registered == [a], "the temporary hotkey is not a registration of the plan")
        #expect(registrar.hasTemporary)

        backend.press(escapeWithCommand)
        backend.release(escapeWithCommand)

        #expect(seen.temporaryPresses == 1)
        #expect(seen.presses.isEmpty)
        #expect(seen.releases.isEmpty)
    }

    @Test("unregistering the temporary hotkey releases it at the backend, and its press is no longer delivered")
    func unregisterTemporary() throws {
        let seen = Seen()
        registrar.apply([]) { _ in }
        try registrar.registerTemporary(escapeWithCommand) { seen.temporaryPresses += 1 }
        let hotkeyID = try #require(backend.hotkeyID(of: escapeWithCommand))

        registrar.unregisterTemporary()

        #expect(backend.live.isEmpty)
        #expect(registrar.hasTemporary == false)
        backend.pressStale(hotkeyID: hotkeyID)
        #expect(seen.temporaryPresses == 0)
    }

    @Test("unregistering when nothing is registered does nothing")
    func unregisterNothing() {
        registrar.unregisterTemporary()
        #expect(backend.calls.isEmpty)
    }

    @Test("registering a second temporary hotkey replaces the first")
    func temporaryReplaces() throws {
        let other = Shortcut(keyCode: 53, modifiers: [.option])
        try registrar.registerTemporary(escapeWithCommand) {}
        try registrar.registerTemporary(other) {}
        #expect(backend.liveShortcuts == [other])
    }

    @Test("a temporary hotkey the system refuses throws, and nothing stays registered")
    func temporaryRefused() {
        backend.refuse(escapeWithCommand, reason: "taken")
        #expect(throws: HotkeyRefusal(reason: "taken")) {
            try registrar.registerTemporary(escapeWithCommand) {}
        }
        #expect(registrar.hasTemporary == false)
        #expect(backend.live.isEmpty)
    }

    @Test("a temporary hotkey that a binding has already is refused")
    func temporaryClashesWithBinding() {
        let binding = registration(53, [.command])
        registrar.apply([binding]) { _ in }
        #expect(throws: HotkeyRefusal.self) {
            try registrar.registerTemporary(escapeWithCommand) {}
        }
        #expect(registrar.registered == [binding])
    }

    @Test("applying a plan releases the temporary hotkey too")
    func applyReleasesTemporary() throws {
        try registrar.registerTemporary(escapeWithCommand) {}
        registrar.apply([]) { _ in }
        #expect(backend.live.isEmpty)
        #expect(registrar.hasTemporary == false)
    }
}
