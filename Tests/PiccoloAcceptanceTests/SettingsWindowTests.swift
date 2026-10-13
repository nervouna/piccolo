import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for the Settings window: the installed Debug Piccolo opens it, edits the
/// config file Piccolo has loaded, records shortcuts from real keyboard events, and keeps the
/// global hotkeys in step with all of it.
///
/// Every test runs on a temporary config applied with `config.load` (see
/// ``withSettingsSession(_:inNewSubfolder:_:)``): Settings writes to the file Piccolo has
/// loaded, so nothing here ever touches the default location. The shortcuts are real global
/// hotkeys on a machine somebody works at: only control + option + shift + command with F13 to
/// F19 are used.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Settings window")
    struct SettingsWindow {
        private let piccolo = PiccoloClient()

        // MARK: 1. Open and close

        @Test("settings 1. settings.open puts a window of Piccolo on screen, settings.close removes it")
        func openAndClose() async throws {
            try await withSettingsSession { session in
                let pid = try piccolo.pid()
                #expect(
                    PiccoloWindows.onScreen(pid: pid).isEmpty,
                    "Piccolo already has a window on screen before Settings was opened")

                let opened = try session.openSettings()
                #expect(opened.isOpen, "settings.open answered isOpen: false")
                _ = try await PiccoloWindows.waitForWindow(pid: pid)
                // For the log: whether the control command alone brought the window forward.
                print("settings.open: frontmost app afterwards is \(Frontmost.bundleID() ?? "unknown")")
                #expect(try piccolo.settingsState().isOpen)

                let closed = try piccolo.settingsClose()
                #expect(!closed.isOpen, "settings.close answered isOpen: true")
                try await PiccoloWindows.waitForNoWindow(pid: pid)
                #expect(try !piccolo.settingsState().isOpen)
            }
        }

        // MARK: 2. A second launch opens Settings

        @Test("settings 2. launching Piccolo again while it runs opens Settings and brings it forward")
        func secondLaunchOpensSettings() async throws {
            try await withSettingsSession { session in
                let pid = try piccolo.pid()
                #expect(try !piccolo.settingsState().isOpen)

                session.markPiccoloActivated()
                try Shell.open([try piccolo.bundlePath()])

                try await eventually("Settings to be open after launching Piccolo again", timeout: 5) {
                    let state = try piccolo.settingsState()
                    return state.isOpen ? .satisfied(()) : .unsatisfied("isOpen is false")
                }
                _ = try await PiccoloWindows.waitForWindow(pid: pid)
                try await eventually("Piccolo to be the frontmost application", timeout: 5) {
                    let front = Frontmost.bundleID()
                    return front == piccoloBundleID
                        ? .satisfied(()) : .unsatisfied("frontmost app is \(front ?? "unknown")")
                }
                #expect(try piccolo.pid() == pid, "launching again started a second Piccolo")
            }
        }

        // MARK: 3. Add a binding

        @Test("settings 3. a new binding is in the state, in the file (created with its folder), and counted by config.status")
        func addBinding() async throws {
            try await withSettingsSession(inNewSubfolder: "not-yet") { session in
                #expect(
                    !FileManager.default.fileExists(atPath: session.url.deletingLastPathComponent().path),
                    "the config folder exists before the first save")
                #expect(try piccolo.configStatus().bindingCount == 0)

                let state = try piccolo.settingsAddBinding()

                #expect(state.bindings.count == 1, "the state lists \(state.bindings.count) bindings")
                let added = try #require(state.bindings.first)
                #expect(added.action == .placeWindow(.preset(.leftHalf)))
                #expect(added.summary == "Left Half")
                #expect(added.shortcut == nil && added.shortcutText == nil)
                #expect(state.error == nil, "adding a binding set the error \(state.error ?? "")")

                let inFile = try session.fileBindings()
                #expect(inFile.count == 1 && inFile.first?.id == added.id, "the file holds \(inFile)")
                #expect(inFile.first?.action == .placeWindow(.preset(.leftHalf)))
                #expect(try piccolo.configStatus().bindingCount == 1)
                #expect(try piccolo.configStatus().path == session.url.path)
            }
        }

        // MARK: 4. Update an action

        @Test("settings 4. updating the action changes the file; an invalid action is rejected and leaves the file byte for byte")
        func updateAction() async throws {
            let binding = KeyBinding(action: .placeWindow(.preset(.leftHalf)))
            try await withSettingsSession([binding]) { session in
                let before = try session.fileBytes()
                let grid = Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))

                let state = try piccolo.settingsUpdateAction(binding.id, grid)

                #expect(state.bindings.first?.action == grid)
                #expect(state.bindings.first?.summary == "Arrange 4 in 2 × 2")
                let changed = try session.fileBytes()
                #expect(changed != before, "the file did not change")
                #expect(try session.fileBindings().first?.action == grid)

                // Five windows do not fit in 2 × 2.
                let rejected = Action.arrangeGrid(GridSpec(count: 5, rows: 2, columns: 2))
                let message = try piccolo.settingsUpdateActionExpectingRejection(binding.id, rejected)

                #expect(message.contains("rows × columns"), "the message is \"\(message)\"")
                #expect(try session.fileBytes() == changed, "the rejected action changed the file")
                let after = try piccolo.settingsState()
                #expect(after.bindings.first?.action == grid, "the rejected action reached the state")
                #expect(after.error == message, "the state's error is \(after.error ?? "nil"), not the message")
            }
        }

        // MARK: 5. Record a shortcut

        @Test("settings 5. recording F14 with the four modifiers sets and registers the shortcut, and its hotkey moves a window")
        func recordShortcut() async throws {
            let screens = try Layout.screens()
            let visible = screens[0].visibleFrame
            let start = try fixtureWindowFrame()

            try await withSettingsSession { session in
                let added = try piccolo.settingsAddBinding()
                let id = try #require(added.bindings.first?.id)
                try session.openSettings()

                let state = try await session.record(id, TestShortcut.f14)

                #expect(state.error == nil, "recording set the error \(state.error ?? "")")
                #expect(state.recordingBindingID == nil, "the recording did not end")
                let binding = try #require(state.bindings.first)
                #expect(binding.shortcut == TestShortcut.f14, "the state shows \(String(describing: binding.shortcut))")
                #expect(binding.shortcutText == "⌃⌥⇧⌘F14", "the shortcut text is \(binding.shortcutText ?? "nil")")
                #expect(try session.fileBindings().first?.shortcut == TestShortcut.f14)

                let status = try piccolo.configStatus()
                #expect(
                    status.registered == [
                        PiccoloClient.RegisteredShortcut(
                            id: id, keyCode: TestShortcut.f14.keyCode, modifiers: TestShortcut.f14.modifiers)
                    ],
                    "config.status lists \(status.registered) as registered")

                // A Piccolo that has been the active application no longer fires simulated
                // hotkeys (see PiccoloProcess), so the shortcut is tried in a new process, which
                // loads the file Settings has just written.
                try await session.restartPiccolo()
                let reloaded = try piccolo.configStatus()
                #expect(
                    reloaded.registered.map(\.id) == [id],
                    "after restarting, config.status lists \(reloaded.registered) as registered")
                #expect(reloaded.path == session.url.path)

                try await withFixture { fixture in
                    let window = try fixture.open(id: "recorded", frame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)
                    try await Focus.bring(window, of: fixture)

                    try piccolo.simulateHotkey(id)

                    let expected = FrameResolver.frame(
                        for: .preset(.leftHalf), visibleFrame: visible, currentFrame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                }
            }
        }

        // MARK: 6. A shortcut that is taken

        @Test("settings 6. recording a shortcut another binding has is rejected, names that binding's action, and sets nothing")
        func recordTakenShortcut() async throws {
            let first = KeyBinding(action: .placeWindow(.preset(.rightHalf)), shortcut: TestShortcut.f14)
            try await withSettingsSession([first]) { session in
                let added = try piccolo.settingsAddBinding()
                let secondID = try #require(added.bindings.last?.id)
                #expect(secondID != first.id)
                try session.openSettings()
                let before = try session.fileBytes()

                let state = try await session.record(secondID, TestShortcut.f14)

                let message = try #require(state.error, "recording a taken shortcut did not set an error")
                #expect(message.contains("Right Half"), "the message does not name the first binding's action: \"\(message)\"")
                let second = try #require(state.bindings.first { $0.id == secondID })
                #expect(second.shortcut == nil, "the second binding got the shortcut \(String(describing: second.shortcut))")
                #expect(state.bindings.first { $0.id == first.id }?.shortcut == TestShortcut.f14)
                #expect(state.recordingBindingID == nil)
                #expect(try session.fileBindings().last?.shortcut == nil)
                #expect(
                    try session.fileBytes() == before,
                    "the rejected shortcut changed the file")
                // The first binding keeps its hotkey, and only that one is registered.
                #expect(try session.registeredIDs() == [first.id])
            }
        }

        // MARK: 7. Recording suspends the hotkeys

        @Test("settings 7. while a shortcut is being recorded no hotkey is registered, and cancelling restores them")
        func recordingSuspendsHotkeys() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let b = KeyBinding(action: .placeWindow(.preset(.rightHalf)), shortcut: TestShortcut.f14)
            try await withSettingsSession([a, b]) { session in
                let before = try piccolo.configStatus().registered
                #expect(before.map(\.id) == [a.id, b.id])

                let recording = try piccolo.settingsBeginRecording(a.id)

                #expect(recording.recordingBindingID == a.id)
                let suspended = try piccolo.configStatus()
                #expect(
                    suspended.registered.isEmpty,
                    "hotkeys are still registered while recording: \(suspended.registered)")
                // The bindings are still there, only their registrations are off.
                #expect(suspended.bindingCount == 2)

                let cancelled = try piccolo.settingsCancelRecording()

                #expect(cancelled.recordingBindingID == nil)
                let restored = try piccolo.configStatus().registered
                #expect(restored == before, "after cancelling, config.status lists \(restored), expected \(before)")
            }
        }

        @Test("settings 7b. closing the window during a recording restores the hotkeys")
        func closingWindowEndsRecording() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            try await withSettingsSession([a]) { session in
                try session.openSettings()
                try piccolo.settingsBeginRecording(a.id)
                #expect(try piccolo.configStatus().registered.isEmpty)

                let closed = try piccolo.settingsClose()

                #expect(closed.recordingBindingID == nil, "the recording survived closing the window")
                #expect(try session.registeredIDs() == [a.id], "the hotkeys were not restored")
            }
        }

        @Test("settings 7c. closing the window with the close command also ends a recording when the window was not open")
        func closeEndsRecordingWithoutWindow() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            try await withSettingsSession([a]) { session in
                try piccolo.settingsBeginRecording(a.id)
                #expect(try !piccolo.settingsState().isOpen)
                #expect(try piccolo.configStatus().registered.isEmpty)

                try piccolo.settingsClose()

                #expect(try piccolo.settingsState().recordingBindingID == nil)
                #expect(try session.registeredIDs() == [a.id])
            }
        }

        @Test("settings 7d. removing the binding that is recording restores the hotkeys of the others")
        func removingRecordedBindingEndsRecording() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let b = KeyBinding(action: .placeWindow(.preset(.rightHalf)), shortcut: TestShortcut.f14)
            try await withSettingsSession([a, b]) { session in
                try piccolo.settingsBeginRecording(b.id)
                #expect(try piccolo.configStatus().registered.isEmpty)

                let state = try piccolo.settingsRemoveBinding(b.id)

                #expect(state.recordingBindingID == nil, "the recording survived the removal of its binding")
                #expect(state.bindings.map(\.id) == [a.id])
                #expect(try session.registeredIDs() == [a.id], "the hotkeys were not restored")
                #expect(try session.fileBindings().map(\.id) == [a.id])
            }
        }

        @Test("settings 7e. deactivating the app during a recording restores the hotkeys")
        func deactivationEndsRecording() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let start = try fixtureWindowFrame()
            try await withSettingsSession([a]) { session in
                try session.openSettings()
                try await session.bringPiccoloForward()
                try piccolo.settingsBeginRecording(a.id)
                #expect(try piccolo.configStatus().registered.isEmpty)

                // Another application comes to the front: Piccolo is deactivated.
                try await withFixture { fixture in
                    let window = try fixture.open(id: "deactivator", frame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)
                    try await Focus.bring(window, of: fixture)

                    try await eventually("the recording to end and the hotkeys to be restored", timeout: 5) {
                        () throws -> Observation<Void> in
                        let state = try piccolo.settingsState()
                        let registered = try session.registeredIDs()
                        guard state.recordingBindingID == nil, registered == [a.id] else {
                            return .unsatisfied(
                                "recording: \(String(describing: state.recordingBindingID)), registered: \(registered)")
                        }
                        return .satisfied(())
                    }
                }
            }
        }

        @Test("settings 7f. Escape and Delete, pressed as real keys, end a recording; Delete clears the shortcut")
        func escapeAndDelete() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            try await withSettingsSession([a]) { session in
                try session.openSettings()

                let escaped = try await session.record(a.id, Shortcut(keyCode: 53, modifiers: []))
                #expect(escaped.recordingBindingID == nil)
                #expect(escaped.bindings.first?.shortcut == TestShortcut.f13, "Escape changed the shortcut")
                #expect(try session.registeredIDs() == [a.id])

                let deleted = try await session.record(a.id, Shortcut(keyCode: 51, modifiers: []))
                #expect(deleted.recordingBindingID == nil)
                #expect(deleted.bindings.first?.shortcut == nil, "Delete did not clear the shortcut")
                #expect(try session.fileBindings().first?.shortcut == nil)
                #expect(try session.registeredIDs().isEmpty)
            }
        }

        @Test("settings 7g. settings.record refuses unless Piccolo is frontmost with the Settings window key, and posts nothing")
        func recordRefusesWithoutFocus() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)))
            let start = try fixtureWindowFrame()
            try await withSettingsSession([a]) { session in
                // The Settings window is closed: there is no key window.
                let closed = try piccolo.settingsRecordRaw(a.id, TestShortcut.f15)
                #expect(!closed.ok, "settings.record was accepted with Settings closed")
                #expect(try piccolo.settingsState().recordingBindingID == nil)

                // Settings is open but another application is frontmost.
                try session.openSettings()
                try await withFixture { fixture in
                    let window = try fixture.open(id: "in-front", frame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)
                    try await Focus.bring(window, of: fixture)

                    let response = try piccolo.settingsRecordRaw(a.id, TestShortcut.f15)
                    #expect(!response.ok, "settings.record was accepted while the fixture was frontmost")
                    #expect(
                        response.error?.contains("frontmost") == true,
                        "the refusal is \"\(response.error ?? "nil")\"")
                }
                let state = try piccolo.settingsState()
                #expect(state.recordingBindingID == nil)
                #expect(state.bindings.first?.shortcut == nil, "a refused settings.record set a shortcut")
            }
        }

        // MARK: 8. Remove a binding

        @Test("settings 8. removing a binding removes it from the file and releases its hotkey")
        func removeBinding() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let b = KeyBinding(action: .placeWindow(.preset(.rightHalf)), shortcut: TestShortcut.f14)
            try await withSettingsSession([a, b]) { session in
                #expect(try session.registeredIDs() == [a.id, b.id])

                let state = try piccolo.settingsRemoveBinding(a.id)

                #expect(state.bindings.map(\.id) == [b.id], "the state lists \(state.bindings.map(\.id))")
                #expect(try session.fileBindings().map(\.id) == [b.id])
                let status = try piccolo.configStatus()
                #expect(status.bindingCount == 1)
                #expect(status.registered.map(\.id) == [b.id], "config.status lists \(status.registered) as registered")
                let reason = try piccolo.simulateHotkeyExpectingRefusal(a.id)
                #expect(reason.contains("no registered shortcut"), "the refusal is \"\(reason)\"")

                // An unknown binding is rejected.
                let response = try piccolo.sendRaw("settings.removeBinding", ["id": .string(UUID().uuidString)])
                #expect(!response.ok)
            }
        }

        // MARK: 9. The resize step

        @Test("settings 9. a resize step of 0.1 is saved, 0.9 is rejected")
        func resizeStep() async throws {
            try await withSettingsSession { session in
                let state = try piccolo.settingsSetResizeStep(0.1)

                #expect(state.resizeStep == 0.1)
                #expect(try session.fileConfig().resizeStep == 0.1)
                let saved = try session.fileBytes()

                let message = try piccolo.settingsSetResizeStepExpectingRejection(0.9)

                #expect(message.contains("50%"), "the message is \"\(message)\"")
                #expect(try session.fileBytes() == saved, "the rejected step changed the file")
                let after = try piccolo.settingsState()
                #expect(after.resizeStep == 0.1)
                #expect(after.error == message)
            }
        }

        // MARK: 10. The default location

        @Test("settings 10. a whole editing session leaves the default config location as it was")
        func defaultLocationUntouched() async throws {
            let defaultFile = ConfigLocation.defaultURL
            let defaultFolder = defaultFile.deletingLastPathComponent()
            let before = try? FileManager.default.contentsOfDirectory(atPath: defaultFolder.path).sorted()
            let existedBefore = FileManager.default.fileExists(atPath: defaultFile.path)
            let bytesBefore = try? Data(contentsOf: defaultFile)

            try await withSettingsSession(inNewSubfolder: "session") { session in
                try session.openSettings()
                let id = try #require(try piccolo.settingsAddBinding().bindings.first?.id)
                try piccolo.settingsUpdateAction(id, .moveToDisplay(.next))
                try piccolo.settingsSetResizeStep(0.2)
                try piccolo.settingsBeginRecording(id)
                try piccolo.settingsCancelRecording()
                try piccolo.settingsRemoveBinding(id)
                #expect(try piccolo.configStatus().path == session.url.path)
            }

            let status = try piccolo.configStatus()
            #expect(status.path == defaultFile.path, "Piccolo reports the config path \(status.path)")
            #expect(status.registered.isEmpty || existedBefore, "hotkeys are registered although there is no default config")
            #expect(FileManager.default.fileExists(atPath: defaultFile.path) == existedBefore)
            let bytesAfter = try? Data(contentsOf: defaultFile)
            #expect(bytesAfter == bytesBefore, "the default config file changed")
            let after = try? FileManager.default.contentsOfDirectory(atPath: defaultFolder.path).sorted()
            #expect(after == before, "the default config folder held \(String(describing: before)), it now holds \(String(describing: after))")
            #expect(try !piccolo.settingsState().isOpen)
        }

        // MARK: 11. Select a binding

        @Test("settings 11. settings.select selects a binding in the open window, an unknown ID is refused, and nothing is saved")
        func selectBinding() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let b = KeyBinding(action: .placeWindow(.preset(.rightHalf)), shortcut: TestShortcut.f14)
            try await withSettingsSession([a, b]) { session in
                let pid = try piccolo.pid()
                try session.openSettings()
                _ = try await PiccoloWindows.waitForWindow(pid: pid)
                let before = try session.fileBytes()

                // A window opens with the first binding selected.
                let initial = try piccolo.settingsState()
                #expect(initial.selectedBindingID == a.id, "the state shows \(String(describing: initial.selectedBindingID)) selected")

                let selected = try piccolo.settingsSelect(b.id)
                #expect(selected.selectedBindingID == b.id, "settings.select answered \(String(describing: selected.selectedBindingID))")
                #expect(try piccolo.settingsState().selectedBindingID == b.id)

                let back = try piccolo.settingsSelect(a.id)
                #expect(back.selectedBindingID == a.id)

                // An ID no binding has is refused, and the selection stays.
                let message = try piccolo.settingsSelectExpectingRefusal(UUID())
                #expect(message.contains("no binding"), "the message is \"\(message)\"")
                #expect(try piccolo.settingsState().selectedBindingID == a.id, "a refused settings.select changed the selection")

                // Selecting is a change of the view: the file, the hotkeys and the window are as they were.
                #expect(try session.fileBytes() == before, "selecting a binding changed the file")
                #expect(try session.registeredIDs() == [a.id, b.id])
                #expect(try piccolo.settingsState().isOpen)
                _ = try await PiccoloWindows.waitForWindow(pid: pid)
            }
        }

        // MARK: 12. Show a tab

        @Test("settings 12. settings.showTab switches the tab, with the window closed and open, and an unknown tab is refused")
        func showTab() async throws {
            let a = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            try await withSettingsSession([a]) { session in
                let pid = try piccolo.pid()
                let before = try session.fileBytes()

                // Whatever tab an earlier test left behind, this one starts on the Shortcuts tab.
                #expect(try piccolo.settingsShowTab("shortcuts").tab == "shortcuts")

                // With the window closed the tab is set, and the window opens on it.
                let general = try piccolo.settingsShowTab("general")
                #expect(general.tab == "general", "settings.showTab answered the tab \(general.tab)")
                #expect(!general.isOpen)
                try session.openSettings()
                _ = try await PiccoloWindows.waitForWindow(pid: pid)
                #expect(try piccolo.settingsState().tab == "general", "opening the window changed the tab")

                // With the window open, both ways.
                #expect(try piccolo.settingsShowTab("shortcuts").tab == "shortcuts")
                #expect(try piccolo.settingsState().tab == "shortcuts")
                #expect(try piccolo.settingsShowTab("general").tab == "general")
                #expect(try piccolo.settingsShowTab("general").tab == "general", "showing the tab that is shown changed it")

                // An unknown tab is refused, names the tabs there are, and the tab stays.
                let message = try piccolo.settingsShowTabExpectingRefusal("advanced")
                #expect(
                    message.contains("shortcuts") && message.contains("general"),
                    "the message does not name the tabs: \"\(message)\"")
                #expect(try piccolo.settingsState().tab == "general", "a refused settings.showTab changed the tab")

                // A change of the view saves nothing and leaves the window open and the hotkeys registered.
                #expect(try session.fileBytes() == before, "switching the tab changed the file")
                #expect(try session.registeredIDs() == [a.id])
                #expect(try piccolo.settingsState().isOpen)
                _ = try await PiccoloWindows.waitForWindow(pid: pid)
                try piccolo.settingsShowTab("shortcuts")
            }
        }

        // MARK: Helpers

        /// Where the fixture windows of these tests start: inside the primary display.
        private func fixtureWindowFrame() throws -> CGRect {
            let screens = try Layout.screens()
            return Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
        }
    }
}
