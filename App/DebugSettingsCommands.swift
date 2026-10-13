#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloUI

/// The Settings window commands of the Debug control channel: `settings.open`, `settings.close`,
/// `settings.state`, the edits (`settings.addBinding`, `settings.removeBinding`,
/// `settings.updateAction`, `settings.setResizeStep`) and recording (`settings.beginRecording`,
/// `settings.cancelRecording`, `settings.record`).
///
/// They drive the model the window uses, through the same methods, so a rejected edit answers
/// `ok: false` with the model's own message. Like the rest of the control channel, this file is
/// compiled out of Release builds.
extension DebugControlServer {
    /// How long `settings.record` waits for the recorder to receive the key press it posted.
    private nonisolated static let recordTimeout: TimeInterval = 3

    nonisolated static func registerSettingsCommands(in router: inout ControlRouter) {
        // Opens the window and activates the app. Since macOS 14 the system may refuse the
        // activation; the window is then on screen behind other apps, and launching the app
        // again through LaunchServices brings it forward.
        router.register("settings.open") { _ in
            onMainActor {
                SettingsController.shared.show()
                return settingsState()
            }
        }

        // Closes the window and ends a recording, also when the window was not open.
        router.register("settings.close") { _ in
            onMainActor {
                SettingsController.shared.close()
                return settingsState()
            }
        }

        router.register("settings.state") { _ in
            onMainActor { settingsState() }
        }

        router.register("settings.addBinding") { _ in
            try onMainActor {
                let model = SettingsController.shared.model
                guard model.addBinding() != nil else { throw rejection(of: model) }
                return settingsState()
            }
        }

        router.register("settings.removeBinding") { params in
            let id = try params.decode(IDParams.self).id
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.removeBinding(id) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // The params are the binding's ID and an action exactly as the config file writes it.
        router.register("settings.updateAction") { params in
            let update = try params.decode(UpdateActionParams.self)
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.updateAction(update.id, to: update.action) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // The value is a fraction of the screen, as in the config file: 0.1 is 10%.
        router.register("settings.setResizeStep") { params in
            let value = try params.decode(ValueParams.self).value
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.setResizeStep(value) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // Starts recording without a key press: the global hotkeys are suspended until
        // `settings.cancelRecording`, a recorded key, or the window closing.
        router.register("settings.beginRecording") { params in
            let id = try params.decode(IDParams.self).id
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.beginRecording(id) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        router.register("settings.cancelRecording") { _ in
            onMainActor {
                SettingsController.shared.model.cancelRecording()
                return settingsState()
            }
        }

        // Records a shortcut the way a person does: starts recording on the binding, then presses
        // the keys with real keyboard events (see `hotkey.simulate`) that reach the Settings
        // window. The events go to whatever application is frontmost, so the command refuses
        // unless Piccolo is the active application and the Settings window is its key window.
        router.register("settings.record") { params in
            let request = try params.decode(RecordParams.self)
            guard CGPreflightPostEventAccess() else {
                throw ControlCommandError.failed(
                    "Piccolo is not allowed to post keyboard events (CGPreflightPostEventAccess is false); "
                        + "this command never asks for the permission")
            }
            let press = Shortcut(keyCode: request.keyCode, modifiers: Set(request.modifiers))

            // The checks and the posting are one step on the main thread, so that nothing can
            // change the frontmost application in between.
            let pressesBefore: Int = try onMainActor {
                let settings = SettingsController.shared
                guard NSApplication.shared.isActive,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier
                        == ProcessInfo.processInfo.processIdentifier
                else {
                    throw ControlCommandError.failed(
                        "Piccolo is not the frontmost application; refusing to post a key press that could land "
                            + "in another app (bring Piccolo forward with `open` first)")
                }
                guard settings.isOpen, settings.isKey else {
                    throw ControlCommandError.failed(
                        "the Settings window is not the key window; refusing to post a key press "
                            + "(settings.open, then bring Piccolo forward with `open`)")
                }
                guard settings.model.beginRecording(request.id) else {
                    throw rejection(of: settings.model)
                }
                let pressesBefore = settings.model.pressesTaken
                do {
                    try postKeyPress(press)
                } catch {
                    settings.model.cancelRecording()
                    throw error
                }
                return pressesBefore
            }

            // The events are asynchronous: wait until the recorder has taken the key press.
            let deadline = Date().addingTimeInterval(recordTimeout)
            while Date() < deadline {
                let (taken, stillRecording) = onMainActor {
                    let model = SettingsController.shared.model
                    return (model.pressesTaken, model.recordingBindingID != nil)
                }
                if taken > pressesBefore {
                    return onMainActor { settingsState() }
                }
                if !stillRecording {
                    // Something else ended the recording (the window lost key status, the app
                    // was deactivated) before the key press arrived.
                    throw ControlCommandError.failed(
                        "the recording ended before the key press arrived: the Settings window is no longer the key window")
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            onMainActor { SettingsController.shared.model.cancelRecording() }
            throw ControlCommandError.failed(
                "the key press was posted but the recorder did not receive it within \(Int(recordTimeout)) s; "
                    + "recording was cancelled")
        }
    }

    // MARK: State

    /// The model and the window as the commands answer with them.
    @MainActor
    private static func settingsState() -> JSONValue {
        let settings = SettingsController.shared
        let model = settings.model
        var state: [String: JSONValue] = [
            "isOpen": .bool(settings.isOpen),
            "bindings": .array(
                model.bindings.map { binding in
                    var entry: [String: JSONValue] = [
                        "id": .string(binding.id.uuidString),
                        "action": (try? JSONValue(encoding: binding.action)) ?? .null,
                        "summary": .string(model.summary(of: binding)),
                    ]
                    if let shortcut = binding.shortcut {
                        entry["shortcut"] = .object([
                            "keyCode": .int(shortcut.keyCode),
                            "modifiers": .array(shortcut.modifiers.map(\.rawValue).sorted().map { .string($0) }),
                        ])
                        entry["shortcutText"] = .string(model.shortcutText(for: shortcut))
                    }
                    return .object(entry)
                }),
            "resizeStep": .double(model.resizeStep),
            "issues": .array(model.issues.map { .string($0) }),
        ]
        if let error = model.error {
            state["error"] = .string(error)
        }
        if let recording = model.recordingBindingID {
            state["recordingBindingID"] = .string(recording.uuidString)
        }
        return .object(state)
    }

    /// The error that answers a rejected edit: the model's message.
    @MainActor
    private static func rejection(of model: SettingsModel) -> ControlCommandError {
        .failed(model.error ?? "the change was rejected")
    }

    // MARK: Parameters

    private struct IDParams: Decodable {
        var id: UUID
    }

    private struct ValueParams: Decodable {
        var value: Double
    }

    private struct UpdateActionParams: Decodable {
        var id: UUID
        var action: Action
    }

    private struct RecordParams: Decodable {
        var id: UUID
        var keyCode: Int
        var modifiers: [Modifier]
    }
}
#endif
