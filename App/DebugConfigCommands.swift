#if DEBUG
import ApplicationServices
import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem

/// The config and hotkey commands of the Debug control channel: `config.status`, `config.load`,
/// `config.reload`, `hotkey.simulate`, `hotkey.press`, `hotkey.release`, `hotkey.escape` and `displays`.
///
/// Like the rest of the control channel, this file is compiled out of Release builds.
extension DebugControlServer {
    /// Where the hotkey commands post their key events. The HID tap is the earliest point, so the
    /// events travel the same way as keys pressed on a keyboard.
    private nonisolated static let simulatedEventTap = CGEventTapLocation.cghidEventTap

    /// The state of the source the key events are created from. It must be the private one: events
    /// from the HID system state (or from no source) reach the window server just the same and
    /// are tracked in the system's key and modifier state, but never fire a registered hotkey.
    /// Observed on macOS 27 at the HID, session and annotated session taps alike; with a private
    /// source the events fire the hotkey at the HID and the session tap.
    private nonisolated static let simulatedEventSourceState = CGEventSourceStateID.privateState

    /// How long a hotkey command waits for the hotkey to fire after posting the keys.
    private nonisolated static let simulatedFireTimeout: TimeInterval = 3

    nonisolated static func registerConfigCommands(in router: inout ControlRouter) {
        // The config the app runs with: where it was read from, what is registered, what went wrong.
        router.register("config.status") { _ in
            onMainActor { ConfigController.shared.status.json }
        }

        // Loads another file instead of the default one, for this run only. Nothing is written
        // to the default location.
        router.register("config.load") { params in
            let path = try params.decode(PathParams.self).path
            guard path.hasPrefix("/") else {
                throw ControlCommandError.invalidParams("path must be absolute")
            }
            return onMainActor {
                ConfigController.shared.load(from: URL(fileURLWithPath: path))
                return ConfigController.shared.status.json
            }
        }

        // Loads the default location again, which also ends a `config.load`.
        router.register("config.reload") { _ in
            onMainActor {
                ConfigController.shared.reload()
                return ConfigController.shared.status.json
            }
        }

        // Presses the shortcut of a registered binding with real keyboard events, so that the
        // system's hotkey path fires. The answer comes when the hotkey has fired, not when the
        // action it runs has finished. The key-up follows at once, so with the destination preview
        // on this is a tap: the action runs on release.
        router.register("hotkey.simulate") { params in
            let id = try params.decode(IDParams.self).id
            let (registration, before) = try registeredShortcut(of: id)
            try postKeyPress(registration.shortcut)
            try waitForHotkey(id, after: before) { $0.pressCounts[id, default: 0] }
            return ["posted": .bool(true), "fired": .bool(true)]
        }

        // Presses and holds: posts only the key-down of the shortcut of a registered binding, and
        // answers when the hotkey has fired. The key stays down until `hotkey.release`. The optional
        // `autorepeat` posts that many more key-downs flagged as auto-repeat, to see what the system
        // delivers for them; the answer then also says how many presses reached the app in all.
        router.register("hotkey.press") { params in
            let request = try params.decode(PressParams.self)
            let id = request.id
            let (registration, before) = try registeredShortcut(of: id)
            try postKeyEvent(registration.shortcut, keyDown: true)
            try waitForHotkey(id, after: before) { $0.pressCounts[id, default: 0] }
            var result: [String: JSONValue] = ["posted": .bool(true), "fired": .bool(true)]
            if let repeats = request.autorepeat, repeats > 0 {
                for _ in 0..<repeats {
                    try postKeyEvent(registration.shortcut, keyDown: true, autorepeat: true)
                }
                Thread.sleep(forTimeInterval: 0.15)
                let presses = onMainActor { ConfigController.shared.pressCounts[id, default: 0] } - before
                result["presses"] = .int(presses)
            }
            return .object(result)
        }

        // Posts the key-up of the shortcut of a registered binding and answers when the hotkey's
        // release has reached the app. With `modifiersFirst` the modifiers go up before the key: a
        // flags-changed event with no flags, then the key-up without flags.
        router.register("hotkey.release") { params in
            let request = try params.decode(ReleaseParams.self)
            let id = request.id
            let (registration, _) = try registeredShortcut(of: id)
            let before = onMainActor { ConfigController.shared.releaseCounts[id, default: 0] }
            if request.modifiersFirst == true {
                try postModifiersUp()
                try postKeyEvent(registration.shortcut, keyDown: false, modifiers: [])
            } else {
                try postKeyEvent(registration.shortcut, keyDown: false)
            }
            do {
                try waitForHotkey(id, after: before) { $0.releaseCounts[id, default: 0] }
            } catch {
                throw ControlCommandError.failed(
                    "the key-up for binding \(id.uuidString) was posted, but the system did not report "
                        + "the hotkey as released within \(Int(simulatedFireTimeout)) s")
            }
            return ["posted": .bool(true), "released": .bool(true)]
        }

        // Presses and releases Escape with the modifiers of the shortcut that is held, as a person
        // would to cancel it, and answers when the Escape hotkey has fired. Refuses when nothing is held.
        router.register("hotkey.escape") { _ in
            guard CGPreflightPostEventAccess() else { throw postAccessError() }
            let held = try onMainActor { () throws -> HeldShortcut in
                let controller = ConfigController.shared
                guard let held = controller.held else {
                    throw ControlCommandError.failed("no shortcut is held, so there is nothing to cancel")
                }
                return HeldShortcut(id: held.id, modifiers: held.shortcut.modifiers, escapeCount: controller.escapeCount)
            }
            try postKeyPress(Shortcut(keyCode: ShortcutManager.escapeKeyCode, modifiers: held.modifiers))
            let deadline = Date().addingTimeInterval(simulatedFireTimeout)
            while Date() < deadline {
                if onMainActor({ ConfigController.shared.escapeCount }) > held.escapeCount {
                    return ["posted": .bool(true), "fired": .bool(true)]
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            let registered = onMainActor { ConfigController.shared.escapeIsRegistered }
            throw ControlCommandError.failed(
                "Escape was posted with the modifiers of binding \(held.id.uuidString), but the Escape hotkey did "
                    + "not fire within \(Int(simulatedFireTimeout)) s (Escape registered: \(registered))")
        }

        // The displays as the app sees them, in canonical coordinates, the primary display first.
        router.register("displays") { _ in
            .array(
                Screens.currentDisplays().map {
                    .object([
                        "frame": JSONValue(rect: $0.frame),
                        "visibleFrame": JSONValue(rect: $0.visibleFrame),
                    ])
                })
        }
    }

    // MARK: Parameters

    private struct PathParams: Decodable {
        var path: String
    }

    private struct IDParams: Decodable {
        var id: UUID
    }

    private struct PressParams: Decodable {
        var id: UUID
        var autorepeat: Int?
    }

    /// The shortcut that is down, and how often Escape had fired before the command posted its own.
    private struct HeldShortcut: Sendable {
        var id: UUID
        var modifiers: Set<Modifier>
        var escapeCount: Int
    }

    private struct ReleaseParams: Decodable {
        var id: UUID
        var modifiersFirst: Bool?
    }

    // MARK: Helpers

    /// Runs `body` on the main thread and waits for it. The control server's handlers run on
    /// their own queue; the app's state belongs to the main thread.
    nonisolated static func onMainActor<T: Sendable>(
        _ body: @MainActor () throws -> T
    ) rethrows -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(body)
        }
        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated(body)
        }
    }

    /// The registered shortcut of a binding, and how often its hotkey has fired. Refuses when the app
    /// may not post keyboard events, and for a binding that has no registered shortcut.
    private nonisolated static func registeredShortcut(
        of id: UUID
    ) throws -> (ShortcutPlan.Registration, fired: Int) {
        guard CGPreflightPostEventAccess() else { throw postAccessError() }
        return try onMainActor {
            let controller = ConfigController.shared
            guard let registration = controller.status.registered.first(where: { $0.id == id }) else {
                throw ControlCommandError.failed(
                    "binding \(id.uuidString) has no registered shortcut; "
                        + "only bindings that config.status lists under registered can be simulated")
            }
            return (registration, controller.pressCounts[id, default: 0])
        }
    }

    private nonisolated static func postAccessError() -> ControlCommandError {
        ControlCommandError.failed(
            "Piccolo is not allowed to post keyboard events (CGPreflightPostEventAccess is false); "
                + "this command never asks for the permission")
    }

    /// Waits until a hotkey has fired again: `count` reads the counter the event moves, which was
    /// `before` when the keys were posted. The events are asynchronous.
    private nonisolated static func waitForHotkey(
        _ id: UUID, after before: Int, count: @MainActor (ConfigController) -> Int
    ) throws {
        let deadline = Date().addingTimeInterval(simulatedFireTimeout)
        while Date() < deadline {
            if onMainActor({ count(ConfigController.shared) }) > before {
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw ControlCommandError.failed(
            "the key events for binding \(id.uuidString) were posted, but its hotkey did not fire within "
                + "\(Int(simulatedFireTimeout)) s: the shortcut may belong to the system or another app")
    }

    private nonisolated static func eventFlags(_ modifiers: Set<Modifier>) -> CGEventFlags {
        var flags = CGEventFlags()
        for modifier in modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
        return flags
    }

    /// Posts a key-down and a key-up for `shortcut` with its modifiers as event flags.
    nonisolated static func postKeyPress(_ shortcut: Shortcut) throws {
        try postKeyEvent(shortcut, keyDown: true)
        try postKeyEvent(shortcut, keyDown: false)
    }

    /// Posts one key event for the key of `shortcut`, with `modifiers` (the shortcut's own by default)
    /// as event flags. `autorepeat` flags a key-down as one the keyboard repeats while the key is held.
    nonisolated static func postKeyEvent(
        _ shortcut: Shortcut, keyDown: Bool, modifiers: Set<Modifier>? = nil, autorepeat: Bool = false
    ) throws {
        guard let keyCode = CGKeyCode(exactly: shortcut.keyCode) else {
            throw ControlCommandError.failed("key code \(shortcut.keyCode) cannot be posted")
        }
        let source = CGEventSource(stateID: simulatedEventSourceState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            throw ControlCommandError.failed("the key event could not be created")
        }
        event.flags = eventFlags(modifiers ?? shortcut.modifiers)
        if autorepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        event.post(tap: simulatedEventTap)
    }

    /// Posts a flags-changed event with no flags: every modifier has gone up.
    private nonisolated static func postModifiersUp() throws {
        let source = CGEventSource(stateID: simulatedEventSourceState)
        guard let event = CGEvent(source: source) else {
            throw ControlCommandError.failed("the flags-changed event could not be created")
        }
        event.type = .flagsChanged
        event.flags = []
        event.post(tap: simulatedEventTap)
    }
}

extension ShortcutManager.Status {
    /// The form `config.status`, `config.load` and `config.reload` answer with.
    fileprivate var json: JSONValue {
        .object([
            "path": .string(path),
            "bindingCount": .int(bindingCount),
            "registered": .array(
                registered.map { registration in
                    .object([
                        "id": .string(registration.id.uuidString),
                        "keyCode": .int(registration.shortcut.keyCode),
                        "modifiers": .array(
                            registration.shortcut.modifiers.map(\.rawValue).sorted().map { .string($0) }),
                    ])
                }),
            "issues": .array(issues.map { .string($0) }),
        ])
    }
}
#endif
