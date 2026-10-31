#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloUI

/// The Settings window commands of the Debug control channel: `settings.open`, `settings.close`,
/// `settings.state`, the view state (`settings.showTab`, `settings.setSearch`), the edits
/// (`settings.removeBinding`, `settings.updateAction`,
/// `settings.setResizeStep`, `settings.setGap`, `settings.setAnimation`, `settings.setGridFillOrder`,
/// `settings.setDestinationPreview`, `settings.setLanguage`, `settings.restoreDefaults`), the restart
/// that applies a new language (`settings.restartNow`), recording a row of the keymap
/// (`settings.beginRecording`, `settings.cancelRecording`, `settings.record`, `settings.pressKey`), the rest of the keymap
/// (`settings.clearShortcut`, `settings.resolveConflict`, `settings.addLayout`, `settings.updateLayout`,
/// `settings.editLayout`, `settings.dismissLayoutEditor`), the history (`settings.undo`, `settings.redo`),
/// and the login item (`loginItem.status`, `loginItem.set`).
///
/// They drive the model the window uses, through the same methods and properties, so a rejected
/// edit answers `ok: false` with the model's own message and the window follows what the commands
/// do: the search field and the tab control are bound to the model. Like the rest of the
/// control channel, this file is compiled out of Release builds.
extension DebugControlServer {
    /// How long `settings.record` waits for the recorder to receive the key press it posted.
    private nonisolated static let recordTimeout: TimeInterval = 3

    /// How long `settings.restartNow` waits before it quits Piccolo: long enough for the answer to
    /// reach the caller.
    private nonisolated static let restartDelay: TimeInterval = 0.3

    nonisolated static func registerSettingsCommands(in router: inout ControlRouter) {
        // Opens the window and makes Piccolo the active application with the window key, whatever
        // application was in front (see `SettingsWindowController.show()`). The answer comes at once,
        // before the system has activated the app, so `isActive` and `isKey` in it can still be false;
        // `settings.state` shows them a moment later.
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

        // Switches the tab, as a click on the tab control does. Works with the window closed too:
        // it then opens on that tab.
        router.register("settings.showTab") { params in
            let name = try params.decode(TabParams.self).tab
            guard let tab = SettingsTab(rawValue: name) else {
                let known = SettingsTab.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " or ")
                throw ControlCommandError.invalidParams("tab must be \(known), not \"\(name)\"")
            }
            return onMainActor {
                SettingsController.shared.model.tab = tab
                return settingsState()
            }
        }

        // Sets the search query, as typing in the search field does: the keymap filters.
        router.register("settings.setSearch") { params in
            let text = try params.decode(TextParams.self).text
            return onMainActor {
                SettingsController.shared.model.setSearch(text)
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

        // The window gap in points: a whole number from 0 to 64. A value outside the range is
        // rejected by the model with its message.
        router.register("settings.setGap") { params in
            let value = try params.decode(GapParams.self).value
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.setGap(value) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // The window animation, by its name in the config file: "off", "fast", "medium" or "slow".
        router.register("settings.setAnimation") { params in
            let name = try params.decode(NameParams.self).value
            guard let animation = WindowAnimation(rawValue: name) else {
                throw ControlCommandError.invalidParams(unknownValue("animation", name, WindowAnimation.self))
            }
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.setAnimation(animation) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // The grid fill order, by its name in the config file: "rows" or "columns".
        router.register("settings.setGridFillOrder") { params in
            let name = try params.decode(NameParams.self).value
            guard let order = GridFillOrder(rawValue: name) else {
                throw ControlCommandError.invalidParams(unknownValue("gridFillOrder", name, GridFillOrder.self))
            }
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.setGridFillOrder(order) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // Whether holding a shortcut shows its destination first.
        router.register("settings.setDestinationPreview") { params in
            let enabled = try params.decode(EnabledParams.self).enabled
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.setDestinationPreview(enabled) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // The language of the interface: "system", or one of the codes "en", "zh-Hans", "zh-Hant", "ja",
        // "fr", "es", "pt-BR" and "de". It is stored for the next launch, as the picker does; the
        // running app keeps its language, which `effectiveLanguage` reports.
        router.register("settings.setLanguage") { params in
            let name = try params.decode(LanguageParams.self).language
            guard let language = AppLanguage(rawValue: name) else {
                let known = AppLanguage.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
                throw ControlCommandError.invalidParams("language must be one of \(known), not \"\(name)\"")
            }
            return onMainActor {
                SettingsController.shared.model.setLanguage(language)
                return settingsState()
            }
        }

        // Quits Piccolo and starts it again, as the Restart Now button does. The answer goes out first:
        // the quit follows a moment later (`restartDelay`), and the state it carries says that the
        // restart was asked for. A restart that cannot be arranged leaves Piccolo running, with the
        // reason in the state's `restartError`.
        router.register("settings.restartNow") { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) {
                MainActor.assumeIsolated {
                    _ = SettingsController.shared.model.restartNow()
                }
            }
            return onMainActor { settingsState(adding: ["restarting": .bool(true)]) }
        }

        // Replaces the bindings with the default shortcuts, as the Restore button does once confirmed,
        // without the alert. Answers the state and `backup`: the name of the copy kept next to the
        // config file, or null when there was no file to copy.
        router.register("settings.restoreDefaults") { _ in
            try onMainActor {
                let model = SettingsController.shared.model
                guard model.restoreDefaultShortcuts() else { throw rejection(of: model) }
                let backup: JSONValue = model.backupName.map { JSONValue.string($0) } ?? .null
                return settingsState(adding: ["backup": backup])
            }
        }

        // What the system says about starting Piccolo at login, read now. The model reads it too, so
        // that the window and `settings.state` show the same.
        router.register("loginItem.status") { _ in
            onMainActor {
                SettingsController.shared.model.refreshLoginItem()
                return loginItemState()
            }
        }

        // Registers or unregisters Piccolo as a login item through the model, as the switch in the
        // General tab does, and answers the status afterwards. A refusal answers `ok: false` with
        // the system's message. Registering shows a system notification, so scripts and tests use
        // this deliberately and put the status back.
        router.register("loginItem.set") { params in
            let enabled = try params.decode(EnabledParams.self).enabled
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.setLaunchAtLogin(enabled) else {
                    throw ControlCommandError.failed(
                        model.loginItemError ?? "the login item could not be changed")
                }
                return loginItemState()
            }
        }

        // Starts recording on a row, as a click on its shortcut button does, without a key press: the global
        // hotkeys are suspended until `settings.cancelRecording`, a recorded key, or the window closing. A row is
        // named as `settings.state` names it (`KeymapRowID.name`).
        router.register("settings.beginRecording") { params in
            let row = try rowID(named: try params.decode(RowParams.self).row)
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.beginRecording(row) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        router.register("settings.cancelRecording") { _ in
            onMainActor {
                SettingsController.shared.model.cancelRecording()
                return settingsState()
            }
        }

        // Records a shortcut the way a person does: begins recording on the row, then presses the keys with real
        // keyboard events (see `hotkey.simulate`) that reach the Settings window. The events go to whatever
        // application is frontmost, so the command refuses unless Piccolo is the active application and the
        // Settings window is its key window. A shortcut the model rejects, a conflict and a shortcut that cannot
        // be a global one come back in the state (`error`, `errorTarget`, `conflict`), not as `ok: false`.
        router.register("settings.record") { params in
            let request = try params.decode(RecordParams.self)
            let row = try rowID(named: request.row)
            let press = Shortcut(keyCode: request.keyCode, modifiers: Set(request.modifiers))
            return try recordByKeyPress(press) { $0.beginRecording(row) }
        }

        // Posts one key press to the Settings window with real keyboard events, as a person's key press, and
        // begins no recording: ⌘Z (keyCode 6, modifiers ["command"]) undoes, ⇧⌘Z redoes. Answers the state
        // once the window has handled the press. Refuses (`ok: false`, nothing posted) unless Piccolo is the
        // frontmost application and the Settings window is key, like `settings.record`.
        router.register("settings.pressKey") { params in
            let request = try params.decode(PressKeyParams.self)
            return try pressKeyInSettings(Shortcut(keyCode: request.keyCode, modifiers: Set(request.modifiers)))
        }

        // Takes away a row's shortcut, as the ✕ in the shortcut button does.
        router.register("settings.clearShortcut") { params in
            let row = try rowID(named: try params.decode(RowParams.self).row)
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.clearShortcut(row) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // Settles the pending conflict: `replace: true` moves the shortcut to the row that was recorded,
        // `replace: false` drops the conflict. `ok: false` when there is none.
        router.register("settings.resolveConflict") { params in
            let replace = try params.decode(ReplaceParams.self).replace
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.pendingConflict != nil else {
                    throw ControlCommandError.failed("there is no shortcut conflict to resolve")
                }
                guard model.resolveConflict(replace: replace) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // Adds a grid or a custom area (an action as the config file writes it) and starts recording its
        // shortcut: the state's `recordingRow` is the new row. A layout that has a problem is refused with
        // the model's message.
        router.register("settings.addLayout") { params in
            let action = try params.decode(ActionParams.self).action
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.addLayout(action) != nil else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // Replaces the action of a grid or a custom area; the params are the binding's ID and an action.
        router.register("settings.updateLayout") { params in
            let update = try params.decode(UpdateActionParams.self)
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.updateLayout(update.id, to: update.action) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // Asks for the sheet of a layout: `row` is a grid's or custom area's row (its UUID), `new` is
        // "grids" or "customAreas". The state's `layoutEditor` is the request.
        router.register("settings.editLayout") { params in
            let request = try params.decode(EditLayoutParams.self)
            let editor: LayoutEditorRequest
            switch (request.row, request.new) {
            case (let name?, nil):
                guard case .layout(let id) = try rowID(named: name) else {
                    throw ControlCommandError.invalidParams("row must be the row of a grid or a custom area")
                }
                editor = .edit(id)
            case (nil, let name?):
                guard let section = KeymapSection(rawValue: name), section == .grids || section == .customAreas
                else {
                    throw ControlCommandError.invalidParams("new must be \"grids\" or \"customAreas\", not \"\(name)\"")
                }
                editor = .new(section)
            default:
                throw ControlCommandError.invalidParams("give either row or new")
            }
            return try onMainActor {
                let model = SettingsController.shared.model
                guard model.editLayout(editor) else { throw rejection(of: model) }
                return settingsState()
            }
        }

        router.register("settings.dismissLayoutEditor") { _ in
            onMainActor {
                SettingsController.shared.model.dismissLayoutEditor()
                return settingsState()
            }
        }

        // Takes back the last change made in the window, as ⌘Z does, and answers the state; `ok: false`
        // when there is nothing to take back, or when the backend cannot save (the model's message).
        router.register("settings.undo") { _ in
            try onMainActor {
                let model = SettingsController.shared.model
                guard model.canUndo else { throw ControlCommandError.failed("there is nothing to undo") }
                guard model.undo() else { throw rejection(of: model) }
                return settingsState()
            }
        }

        // Applies the change that was taken back last, as ⇧⌘Z does.
        router.register("settings.redo") { _ in
            try onMainActor {
                let model = SettingsController.shared.model
                guard model.canRedo else { throw ControlCommandError.failed("there is nothing to redo") }
                guard model.redo() else { throw rejection(of: model) }
                return settingsState()
            }
        }
    }

    // MARK: Key presses

    /// Starts a recording with `begin`, posts `press` with real keyboard events and answers the state once
    /// the recorder has taken it. Refuses (nothing posted) unless Piccolo may post events, is the frontmost
    /// application and has the Settings window as its key window.
    private nonisolated static func recordByKeyPress(
        _ press: Shortcut, begin: @MainActor (SettingsModel) -> Bool
    ) throws -> JSONValue {
        try postToSettingsWindow(
            press, begin: begin,
            count: { $0.model.pressesTaken },
            lostReason: { settings in
                settings.model.isRecording
                    ? nil
                    : "the recording ended before the key press arrived: the Settings window is no longer the key window"
            },
            giveUp: { $0.model.cancelRecording() },
            timeoutMessage: "the key press was posted but the recorder did not receive it within "
                + "\(Int(recordTimeout)) s; recording was cancelled")
    }

    /// Posts `press` with real keyboard events to the Settings window, which handles it as it handles a key
    /// press of a person (⌘Z undoes, ...), and answers the state once the window's key monitor has handled it.
    /// Begins no recording. Refuses (nothing posted) under the same conditions as ``recordByKeyPress(_:begin:)``.
    private nonisolated static func pressKeyInSettings(_ press: Shortcut) throws -> JSONValue {
        try postToSettingsWindow(
            press, begin: { _ in true },
            count: { $0.keyPressesSeen },
            lostReason: { settings in
                settings.isKey ? nil : "the Settings window stopped being the key window before the key press arrived"
            },
            giveUp: { _ in },
            timeoutMessage: "the key press was posted but the Settings window did not handle it within "
                + "\(Int(recordTimeout)) s")
    }

    /// The common part of the commands that post a key press to the Settings window. Checks that Piccolo may
    /// post events, is the frontmost application and has the Settings window as its key window, runs `begin`
    /// (a rejection answers its message), posts `press`, and waits until `count` has gone up, which is when
    /// the press has arrived and had its effect. While it waits, `lostReason` says why the press can no longer
    /// arrive, if it can't; `giveUp` undoes what `begin` did when nothing arrives.
    private nonisolated static func postToSettingsWindow(
        _ press: Shortcut,
        begin: @MainActor (SettingsModel) -> Bool,
        count: @MainActor (SettingsController) -> Int,
        lostReason: @MainActor (SettingsController) -> String?,
        giveUp: @MainActor (SettingsController) -> Void,
        timeoutMessage: String
    ) throws -> JSONValue {
        guard CGPreflightPostEventAccess() else {
            throw ControlCommandError.failed(
                "Piccolo is not allowed to post keyboard events (CGPreflightPostEventAccess is false); "
                    + "this command never asks for the permission")
        }

        // The checks and the posting are one step on the main thread, so that nothing can
        // change the frontmost application in between.
        let countBefore: Int = try onMainActor {
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
            guard begin(settings.model) else {
                throw rejection(of: settings.model)
            }
            let countBefore = count(settings)
            do {
                try postKeyPress(press)
            } catch {
                giveUp(settings)
                throw error
            }
            return countBefore
        }

        // The events are asynchronous: wait until the window has handled the key press.
        let deadline = Date().addingTimeInterval(recordTimeout)
        while Date() < deadline {
            let (seen, lost) = onMainActor {
                let settings = SettingsController.shared
                return (count(settings), lostReason(settings))
            }
            if seen > countBefore {
                return onMainActor { settingsState() }
            }
            if let lost {
                // Something else ended the wait (the window lost key status, the app was deactivated)
                // before the key press arrived.
                throw ControlCommandError.failed(lost)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        onMainActor { giveUp(SettingsController.shared) }
        throw ControlCommandError.failed(timeoutMessage)
    }

    /// The row a name stands for (see ``KeymapRowID/name``).
    private nonisolated static func rowID(named name: String) throws -> KeymapRowID {
        guard let row = KeymapRowID(name: name) else {
            throw ControlCommandError.invalidParams(
                "there is no row named \"\(name)\": a built-in row is placeWindow.<preset>, restoreWindow, "
                    + "moveToDisplay.<direction>, moveDivider.<direction> or swapWindow.<direction>; "
                    + "a grid or a custom area is the UUID of its binding")
        }
        return row
    }

    // MARK: State

    /// The login item as `loginItem.status` and `loginItem.set` answer with it.
    @MainActor
    private static func loginItemState() -> JSONValue {
        .object(["status": .string(SettingsController.shared.model.loginItemStatus.rawValue)])
    }

    /// The model and the window as the commands answer with them, with `extra` added to the answer.
    @MainActor
    private static func settingsState(adding extra: [String: JSONValue] = [:]) -> JSONValue {
        let settings = SettingsController.shared
        let model = settings.model
        // Read from the system, so that the state agrees with `loginItem.status` whatever the
        // user did in System Settings since the model last looked.
        model.refreshLoginItem()
        model.refreshLanguage()
        var state: [String: JSONValue] = [
            "isOpen": .bool(settings.isOpen),
            "isActive": .bool(NSApp.isActive),
            "isKey": .bool(settings.isKey),
            "bindings": .array(
                model.bindings.map { binding in
                    var entry: [String: JSONValue] = [
                        "id": .string(binding.id.uuidString),
                        "action": (try? JSONValue(encoding: binding.action)) ?? .null,
                        "summary": .string(model.summary(of: binding)),
                        "active": .bool(!model.inactiveBindingIDs.contains(binding.id)),
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
            "animation": .string(model.animation.rawValue),
            "gridFillOrder": .string(model.gridFillOrder.rawValue),
            "destinationPreview": .bool(model.destinationPreview),
            "gap": .int(model.gap),
            "search": .string(model.search),
            "issues": .array(model.issues.map { .string($0) }),
            "tab": .string(model.tab.rawValue),
            "loginItem": .string(model.loginItemStatus.rawValue),
            "language": .string(model.language.rawValue),
            "effectiveLanguage": .string(model.effectiveLanguage.rawValue),
            "restartRequired": .bool(model.restartRequired),
            "canUndo": .bool(model.canUndo),
            "canRedo": .bool(model.canRedo),
        ]
        state.merge(settingsWindowState()) { _, new in new }
        if let error = model.error {
            state["error"] = .string(error)
        }
        if let restartError = model.restartError {
            state["restartError"] = .string(restartError)
        }
        state["rows"] = keymapRows(of: model)
        if let row = model.recordingRow {
            state["recordingRow"] = .string(row.name)
        }
        if let conflict = model.pendingConflict {
            state["conflict"] = .object([
                "row": .string(conflict.row.name),
                "shortcutText": .string(model.shortcutText(for: conflict.shortcut)),
                "ownerBindingID": .string(conflict.ownerBindingID.uuidString),
                "ownerName": .string(model.binding(conflict.ownerBindingID).map { model.summary(of: $0) } ?? ""),
            ])
        }
        if let target = model.errorTarget {
            switch target {
            case .row(let row): state["errorTarget"] = .object(["row": .string(row.name)])
            case .field(let field): state["errorTarget"] = .object(["field": .string(field.rawValue)])
            case .window: state["errorTarget"] = .string("window")
            }
        }
        if let editor = model.layoutEditor {
            switch editor {
            case .new(let section): state["layoutEditor"] = .object(["new": .string(section.rawValue)])
            case .edit(let id): state["layoutEditor"] = .object(["edit": .string(id.uuidString)])
            }
        }
        state.merge(extra) { _, new in new }
        return .object(state)
    }

    /// The rows of the keymap under the current search, in the order the Shortcuts tab lists them. A row's
    /// `shortcuts` are its bindings that have a shortcut.
    @MainActor
    private static func keymapRows(of model: SettingsModel) -> JSONValue {
        var rows: [JSONValue] = []
        for group in model.keymap {
            for row in group.rows {
                var shortcuts: [JSONValue] = []
                for binding in row.bindings {
                    guard let shortcut = binding.shortcut else { continue }
                    shortcuts.append(
                        .object([
                            "bindingID": .string(binding.id.uuidString),
                            "shortcutText": .string(model.shortcutText(for: shortcut)),
                            "active": .bool(!model.inactiveBindingIDs.contains(binding.id)),
                        ]))
                }
                rows.append(
                    .object([
                        "row": .string(row.id.name),
                        "section": .string(group.section.rawValue),
                        "name": .string(row.name),
                        "editable": .bool(row.isEditable),
                        "shortcuts": .array(shortcuts),
                        "recording": .bool(model.recordingRow == row.id),
                    ]))
            }
        }
        return .array(rows)
    }

    /// The message for a value that is not a name of `type`, listing the names it accepts.
    private nonisolated static func unknownValue<Value: RawRepresentable & CaseIterable>(
        _ key: String, _ name: String, _ type: Value.Type
    ) -> String where Value.RawValue == String {
        let names = type.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
        return "\(key) must be one of \(names), not \"\(name)\""
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

    private struct TabParams: Decodable {
        var tab: String
    }

    private struct ValueParams: Decodable {
        var value: Double
    }

    private struct GapParams: Decodable {
        var value: Int
    }

    private struct NameParams: Decodable {
        var value: String
    }

    private struct EnabledParams: Decodable {
        var enabled: Bool
    }

    private struct TextParams: Decodable {
        var text: String
    }

    private struct LanguageParams: Decodable {
        var language: String
    }

    private struct UpdateActionParams: Decodable {
        var id: UUID
        var action: Action
    }

    private struct RowParams: Decodable {
        var row: String
    }

    private struct RecordParams: Decodable {
        var row: String
        var keyCode: Int
        var modifiers: [Modifier]
    }

    private struct PressKeyParams: Decodable {
        var keyCode: Int
        var modifiers: [Modifier]
    }

    private struct ReplaceParams: Decodable {
        var replace: Bool
    }

    private struct ActionParams: Decodable {
        var action: Action
    }

    private struct EditLayoutParams: Decodable {
        var row: String?
        var new: String?
    }
}
#endif
