#if DEBUG
import ApplicationServices
import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem

/// The config and hotkey commands of the Debug control channel: `config.status`, `config.load`,
/// `config.reload`, `hotkey.simulate` and `displays`.
///
/// Like the rest of the control channel, this file is compiled out of Release builds.
extension DebugControlServer {
    /// Where `hotkey.simulate` posts its key events. The HID tap is the earliest point, so the
    /// events travel the same way as keys pressed on a keyboard.
    private nonisolated static let simulatedEventTap = CGEventTapLocation.cghidEventTap

    /// The state of the source the key events are created from. It must be the private one: events
    /// from the HID system state (or from no source) reach the window server just the same and
    /// are tracked in the system's key and modifier state, but never fire a registered hotkey.
    /// Observed on macOS 27 at the HID, session and annotated session taps alike; with a private
    /// source the events fire the hotkey at the HID and the session tap.
    private nonisolated static let simulatedEventSourceState = CGEventSourceStateID.privateState

    /// How long `hotkey.simulate` waits for the hotkey to fire after posting the keys.
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
        // action it runs has finished.
        router.register("hotkey.simulate") { params in
            let id = try params.decode(IDParams.self).id
            guard CGPreflightPostEventAccess() else {
                throw ControlCommandError.failed(
                    "Piccolo is not allowed to post keyboard events (CGPreflightPostEventAccess is false); "
                        + "this command never asks for the permission")
            }
            let (registration, before) = try onMainActor {
                let controller = ConfigController.shared
                guard let registration = controller.status.registered.first(where: { $0.id == id }) else {
                    throw ControlCommandError.failed(
                        "binding \(id.uuidString) has no registered shortcut; "
                            + "only bindings that config.status lists under registered can be simulated")
                }
                return (registration, controller.pressCounts[id, default: 0])
            }

            try postKeyPress(registration.shortcut)

            // The events are asynchronous: wait until the hotkey registry has delivered the press.
            let deadline = Date().addingTimeInterval(simulatedFireTimeout)
            while Date() < deadline {
                if onMainActor({ ConfigController.shared.pressCounts[id, default: 0] }) > before {
                    return ["posted": .bool(true), "fired": .bool(true)]
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            throw ControlCommandError.failed(
                "the key events for binding \(id.uuidString) were posted, but its hotkey did not fire within "
                    + "\(Int(simulatedFireTimeout)) s: the shortcut may belong to the system or another app")
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

    // MARK: Helpers

    /// Runs `body` on the main thread and waits for it. The control server's handlers run on
    /// their own queue; the app's state belongs to the main thread.
    private nonisolated static func onMainActor<T: Sendable>(
        _ body: @MainActor () throws -> T
    ) rethrows -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(body)
        }
        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated(body)
        }
    }

    /// Posts a key-down and a key-up for `shortcut` with its modifiers as event flags.
    private nonisolated static func postKeyPress(_ shortcut: Shortcut) throws {
        guard let keyCode = CGKeyCode(exactly: shortcut.keyCode) else {
            throw ControlCommandError.failed("key code \(shortcut.keyCode) cannot be posted")
        }
        var flags = CGEventFlags()
        for modifier in shortcut.modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
        let source = CGEventSource(stateID: simulatedEventSourceState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw ControlCommandError.failed("the key events could not be created")
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: simulatedEventTap)
        up.post(tap: simulatedEventTap)
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
