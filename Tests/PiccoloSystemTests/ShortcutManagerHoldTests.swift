import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// A timer that fires when the test says so.
@MainActor
final class ManualTimer: HoldTimer {
    private var callbacks: [(fire: @MainActor () -> Void, isCancelled: Bool)] = []

    private(set) var delays: [TimeInterval] = []

    func schedule(
        after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void {
        delays.append(delay)
        callbacks.append((fire, false))
        let index = callbacks.count - 1
        return { [unowned self] in callbacks[index].isCancelled = true }
    }

    /// The time of every timer that was started and not cancelled has come.
    func fireDue() {
        for index in callbacks.indices where !callbacks[index].isCancelled {
            callbacks[index].isCancelled = true
            callbacks[index].fire()
        }
    }
}

/// The hold rules inside the shortcut manager: press, release, the preview callbacks and the
/// temporary Escape hotkey, against the fake backend and a timer the test fires.
@MainActor
@Suite("Shortcut manager: held shortcuts")
struct ShortcutManagerHoldTests {
    @MainActor private final class Log {
        var runs: [UUID] = []
        var previews: [ShortcutManager.Preview] = []
        var events: [ShortcutManager.HotkeyEvent] = []
    }

    @MainActor private final class Rig {
        let directory: URL
        let backend = FakeHotkeyBackend()
        let timer = ManualTimer()
        let manager: ShortcutManager
        private let log = Log()
        var runs: [UUID] { log.runs }
        var previews: [ShortcutManager.Preview] { log.previews }
        var events: [ShortcutManager.HotkeyEvent] { log.events }

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "piccolo-shortcut-hold-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let log = log
            manager = ShortcutManager(
                registrar: HotkeyRegistrar(backend: backend),
                initialURL: directory.appending(path: "config.json"),
                holdTimer: timer
            ) { _, id in
                log.runs.append(id)
            }
            manager.onPreview = { log.previews.append($0) }
            manager.onHotkeyEvent = { log.events.append($0) }
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        @discardableResult
        func load(_ bindings: [KeyBinding], destinationPreview: Bool = true) throws -> ShortcutManager.Status {
            let url = directory.appending(path: "config.json")
            try ConfigStore(url: url).save(Config(destinationPreview: destinationPreview, bindings: bindings))
            return manager.load(from: url)
        }
    }

    private let hyper: Set<Modifier> = [.control, .option, .shift, .command]
    private let left = Action.placeWindow(.preset(.leftHalf))
    private let right = Action.placeWindow(.preset(.rightHalf))

    private func binding(_ keyCode: Int, _ action: Action, _ modifiers: Set<Modifier>? = nil) -> KeyBinding {
        KeyBinding(action: action, shortcut: Shortcut(keyCode: keyCode, modifiers: modifiers ?? hyper))
    }

    private func escape(_ modifiers: Set<Modifier>) -> Shortcut {
        Shortcut(keyCode: 53, modifiers: modifiers)
    }

    // MARK: Tap and hold

    @Test("a tap runs the action on release, shows no preview, and registers Escape only while held")
    func tap() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])

        rig.backend.press(a.shortcut!)
        #expect(rig.runs.isEmpty, "the action must wait for the release")
        #expect(rig.backend.liveShortcuts.contains(escape(hyper)))

        rig.backend.release(a.shortcut!)
        #expect(rig.runs == [a.id])
        #expect(rig.previews.isEmpty)
        #expect(!rig.backend.liveShortcuts.contains(escape(hyper)))
        #expect(rig.manager.heldBindingID == nil)
    }

    @Test("a hold shows the preview for the action when the timer fires, and release hides it and runs the action")
    func hold() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])

        rig.backend.press(a.shortcut!)
        #expect(rig.manager.heldBindingID == a.id)
        rig.timer.fireDue()
        #expect(rig.previews == [.show(left, bindingID: a.id)])
        #expect(rig.runs.isEmpty)

        rig.backend.release(a.shortcut!)
        #expect(rig.previews == [.show(left, bindingID: a.id), .hide])
        #expect(rig.runs == [a.id])
        #expect(rig.manager.lastHold == HoldRules.Outcome(id: a.id, result: .ran, previewShown: true))
    }

    @Test("the timer waits 0.2 s")
    func delay() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])
        rig.backend.press(a.shortcut!)
        #expect(rig.timer.delays == [0.2])
    }

    @Test("a repeated press of the held shortcut changes nothing")
    func repeatedPress() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])

        rig.backend.press(a.shortcut!)
        rig.timer.fireDue()
        rig.backend.press(a.shortcut!)
        rig.backend.press(a.shortcut!)
        rig.backend.release(a.shortcut!)

        #expect(rig.previews == [.show(left, bindingID: a.id), .hide])
        #expect(rig.runs == [a.id])
    }

    @Test("a release the system delivers for a shortcut that is not held is ignored")
    func strayRelease() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        let b = binding(FunctionKey.f14, right)
        try rig.load([a, b])

        rig.backend.release(a.shortcut!)
        rig.backend.press(a.shortcut!)
        rig.backend.release(b.shortcut!)

        #expect(rig.runs.isEmpty)
        #expect(rig.manager.heldBindingID == a.id)
    }

    // MARK: Escape

    @Test("Escape is registered with the held shortcut's modifiers, and unregistered on release")
    func escapeRegistered() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left, [.command, .shift])
        try rig.load([a])
        #expect(!rig.backend.liveShortcuts.contains(escape([.command, .shift])))

        rig.backend.press(a.shortcut!)
        #expect(rig.backend.liveShortcuts.contains(escape([.command, .shift])))
        #expect(rig.manager.escapeIsRegistered)

        rig.backend.release(a.shortcut!)
        #expect(!rig.backend.liveShortcuts.contains(escape([.command, .shift])))
        #expect(!rig.manager.escapeIsRegistered)
    }

    @Test("a function key on its own registers a plain Escape while held")
    func escapeForBareFunctionKey() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left, [])
        try rig.load([a])

        rig.backend.press(a.shortcut!)
        #expect(rig.backend.liveShortcuts.contains(escape([])))
    }

    @Test("pressing the Escape hotkey cancels the hold: the preview is hidden and the release runs nothing")
    func escapeCancels() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])

        rig.backend.press(a.shortcut!)
        rig.timer.fireDue()
        rig.backend.press(escape(hyper))
        #expect(rig.previews == [.show(left, bindingID: a.id), .hide])

        rig.backend.release(escape(hyper))
        rig.backend.release(a.shortcut!)
        #expect(rig.runs.isEmpty)
        #expect(rig.manager.lastHold == HoldRules.Outcome(id: a.id, result: .cancelled, previewShown: true))
        #expect(!rig.manager.escapeIsRegistered)
        #expect(!rig.backend.liveShortcuts.contains(escape(hyper)))
    }

    @Test("Escape stays registered after it was pressed, until the shortcut is released, so that its key-up is not leaked")
    func escapeStaysUntilRelease() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])

        rig.backend.press(a.shortcut!)
        rig.backend.press(escape(hyper))
        #expect(rig.backend.liveShortcuts.contains(escape(hyper)))

        rig.backend.release(a.shortcut!)
        #expect(!rig.backend.liveShortcuts.contains(escape(hyper)))
    }

    @Test("a shortcut on the Escape key itself registers no temporary Escape")
    func escapeShortcutRegistersNoEscape() throws {
        let rig = try Rig()
        let a = binding(53, left, [.command])
        try rig.load([a])
        let registeredBefore = rig.backend.liveShortcuts

        rig.backend.press(a.shortcut!)
        rig.timer.fireDue()

        #expect(rig.backend.liveShortcuts == registeredBefore)
        #expect(!rig.manager.escapeIsRegistered)
        #expect(rig.previews == [.show(left, bindingID: a.id)])

        rig.backend.release(a.shortcut!)
        #expect(rig.runs == [a.id])
        #expect(rig.backend.liveShortcuts == registeredBefore)
    }

    @Test("an Escape the system refuses leaves the hold working: the release still runs the action")
    func escapeRefused() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])
        rig.backend.refuse(escape(hyper), reason: "taken")

        rig.backend.press(a.shortcut!)
        #expect(!rig.manager.escapeIsRegistered)
        rig.timer.fireDue()
        rig.backend.release(a.shortcut!)

        #expect(rig.previews == [.show(left, bindingID: a.id), .hide])
        #expect(rig.runs == [a.id])
    }

    @Test("another binding on Escape with the same modifiers keeps the temporary Escape out, and its press takes over")
    func escapeBindingTakesOver() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        let onEscape = binding(53, right)
        try rig.load([a, onEscape])

        rig.backend.press(a.shortcut!)
        #expect(!rig.manager.escapeIsRegistered)
        rig.backend.press(onEscape.shortcut!)
        #expect(rig.manager.heldBindingID == onEscape.id)
        #expect(rig.runs.isEmpty, "the first hold was cancelled without running")
    }

    // MARK: Another shortcut

    @Test("a press of another shortcut cancels the held one without running it, and Escape follows the new modifiers")
    func takeOver() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left, [.command])
        let b = binding(FunctionKey.f14, right, [.option])
        try rig.load([a, b])

        rig.backend.press(a.shortcut!)
        rig.timer.fireDue()
        rig.backend.press(b.shortcut!)

        #expect(rig.previews == [.show(left, bindingID: a.id), .hide])
        #expect(rig.runs.isEmpty)
        #expect(rig.manager.heldBindingID == b.id)
        #expect(!rig.backend.liveShortcuts.contains(escape([.command])))
        #expect(rig.backend.liveShortcuts.contains(escape([.option])))

        rig.backend.release(a.shortcut!)
        #expect(rig.runs.isEmpty)
        rig.backend.release(b.shortcut!)
        #expect(rig.runs == [b.id])
    }

    // MARK: Preview off

    @Test("with the preview off a press runs the action at once, a release is ignored, and no Escape is registered")
    func previewOff() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a], destinationPreview: false)

        rig.backend.press(a.shortcut!)
        #expect(rig.runs == [a.id])
        #expect(!rig.manager.escapeIsRegistered)
        #expect(rig.timer.delays.isEmpty)

        rig.backend.release(a.shortcut!)
        #expect(rig.runs == [a.id])
        #expect(rig.previews.isEmpty)
    }

    // MARK: Cancel all

    @Test("loading a config while a shortcut is held cancels it: preview hidden, nothing run, Escape released")
    func loadCancels() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])
        rig.backend.press(a.shortcut!)
        rig.timer.fireDue()

        try rig.load([a])

        #expect(rig.previews == [.show(left, bindingID: a.id), .hide])
        #expect(rig.runs.isEmpty)
        #expect(rig.manager.heldBindingID == nil)
        #expect(!rig.backend.liveShortcuts.contains(escape(hyper)))

        rig.backend.release(a.shortcut!)
        #expect(rig.runs.isEmpty, "the release after the load belongs to a hold that was cancelled")
    }

    @Test("suspending the hotkeys while a shortcut is held cancels it")
    func suspendCancels() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])
        rig.backend.press(a.shortcut!)
        rig.timer.fireDue()

        rig.manager.setSuspended(true)

        #expect(rig.previews == [.show(left, bindingID: a.id), .hide])
        #expect(rig.runs.isEmpty)
        #expect(rig.backend.live.isEmpty)
    }

    @Test("saving a config that switches the preview off while a shortcut is held cancels the hold")
    func switchingOffCancels() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])
        rig.backend.press(a.shortcut!)
        rig.timer.fireDue()

        try rig.manager.save(Config(destinationPreview: false, bindings: [a]))

        #expect(rig.previews == [.show(left, bindingID: a.id), .hide])
        #expect(rig.runs.isEmpty)

        rig.backend.press(a.shortcut!)
        #expect(rig.runs == [a.id], "with the preview off a press runs at once")
    }

    // MARK: Events for the debug channel

    @Test("the hotkey events are reported after the hold rules ran, in order, with Escape in between")
    func events() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])

        rig.backend.press(a.shortcut!)
        rig.backend.press(escape(hyper))
        rig.backend.release(a.shortcut!)

        #expect(rig.events == [.pressed(a.id), .escape, .released(a.id)])
    }

    @Test("when the press is reported, Escape is registered already")
    func escapeRegisteredBeforeThePressIsReported() throws {
        let rig = try Rig()
        let a = binding(FunctionKey.f13, left)
        try rig.load([a])
        var registeredWhenReported: Bool?
        rig.manager.onHotkeyEvent = { [unowned rig] event in
            if case .pressed = event { registeredWhenReported = rig.manager.escapeIsRegistered }
        }

        rig.backend.press(a.shortcut!)

        #expect(registeredWhenReported == true)
    }
}
