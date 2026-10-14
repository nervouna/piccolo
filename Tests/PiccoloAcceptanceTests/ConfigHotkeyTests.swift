import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for the config and the global hotkeys: the installed Debug Piccolo loads a
/// config file, registers its shortcuts with the system, and a shortcut pressed with real
/// keyboard events (`hotkey.simulate`) runs its action on the focused window of the fixture.
///
/// Every test writes its config into a temporary directory and applies it with `config.load`,
/// so nothing is written to the default location, and ends with `config.reload`, which releases
/// the test's hotkeys again (see ``withConfigDirectory(_:)``). The shortcuts are real global
/// hotkeys on a machine somebody works at: only control + option + shift + command with F13 to
/// F19 are used.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Config and hotkeys")
    struct ConfigHotkeys {
        private let piccolo = PiccoloClient()

        // MARK: 1. One binding

        @Test("config 1. one binding is registered, and its hotkey moves the focused window to the left half")
        func oneBinding() async throws {
            let screens = try Layout.screens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)

            try await withConfigDirectory { config in
                let url = try config.write([leftHalf])
                let loaded = try piccolo.loadConfig(at: url)

                #expect(loaded.path == url.path)
                #expect(loaded.bindingCount == 1)
                #expect(loaded.issues.isEmpty, "loading a clean file reported \(loaded.issues)")
                #expect(
                    loaded.registered == [registered(leftHalf)],
                    "config.load lists \(loaded.registered) as registered, expected \(registered(leftHalf))")
                #expect(
                    try piccolo.configStatus() == loaded,
                    "config.status differs from what config.load answered")

                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "one-binding", frame: start)

                    try piccolo.simulateHotkey(leftHalf.id)

                    let expected = FrameResolver.frame(
                        for: .preset(.leftHalf), visibleFrame: visible, currentFrame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                }
            }
        }

        // MARK: 2. Two bindings

        @Test("config 2. two bindings: each hotkey puts the window at its own frame")
        func twoBindings() async throws {
            let screens = try Layout.screens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let maximize = KeyBinding(action: .placeWindow(.preset(.maximize)), shortcut: TestShortcut.f14)

            try await withConfigDirectory { config in
                let loaded = try piccolo.loadConfig(at: try config.write([leftHalf, maximize]))
                #expect(loaded.issues.isEmpty, "loading a clean file reported \(loaded.issues)")
                #expect(loaded.registered == [registered(leftHalf), registered(maximize)])

                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "two-bindings", frame: start)
                    let leftFrame = FrameResolver.frame(
                        for: .preset(.leftHalf), visibleFrame: visible, currentFrame: start)
                    let maximizeFrame = FrameResolver.frame(
                        for: .preset(.maximize), visibleFrame: visible, currentFrame: start)

                    try piccolo.simulateHotkey(leftHalf.id)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: leftFrame)

                    try piccolo.simulateHotkey(maximize.id)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: maximizeFrame)

                    // And back, so that the order of the bindings in the file does not matter.
                    try piccolo.simulateHotkey(leftHalf.id)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: leftFrame)
                }
            }
        }

        // MARK: 3. moveToDisplay

        @Test(
            "config 3. a hotkey bound to moveToDisplay next moves the window to the other display",
            .enabled(if: Acceptance.displayCount >= 2, "needs two or more displays")
        )
        func moveToDisplayNext() async throws {
            let screens = try Layout.screens()
            let displays = Screens.displays(from: screens)
            let sourceIndex = 0
            let targetIndex = DisplayLayout.neighbor(of: sourceIndex, .next, in: displays)
            let start = Layout.frame(in: screens[sourceIndex], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let next = KeyBinding(action: .moveToDisplay(.next), shortcut: TestShortcut.f15)

            try await withConfigDirectory { config in
                let loaded = try piccolo.loadConfig(at: try config.write([next]))
                #expect(loaded.registered == [registered(next)])

                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "traveller", frame: start)

                    try piccolo.simulateHotkey(next.id)

                    let predicted = DisplayLayout.frame(
                        moving: start, from: displays[sourceIndex], to: displays[targetIndex])
                    let moved = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: predicted)
                    #expect(
                        DisplayLayout.index(containing: moved, in: displays) == targetIndex,
                        "the window is measured at \(describe(moved)), not on display \(targetIndex) (\(describe(displays[targetIndex].frame)))"
                    )
                }
            }
        }

        // MARK: 4. Shortcuts that are not registered

        @Test("config 4. a binding without a shortcut, a plain A and a duplicate are not registered, and the issues say which")
        func unregisteredBindings() async throws {
            let first = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let noShortcut = KeyBinding(action: .placeWindow(.preset(.rightHalf)))
            let plainA = KeyBinding(
                action: .placeWindow(.preset(.center)), shortcut: Shortcut(keyCode: 0, modifiers: []))
            let duplicate = KeyBinding(action: .placeWindow(.preset(.maximize)), shortcut: TestShortcut.f13)

            try await withConfigDirectory { config in
                let loaded = try piccolo.loadConfig(at: try config.write([first, noShortcut, plainA, duplicate]))

                #expect(loaded.bindingCount == 4)
                #expect(
                    loaded.registered == [registered(first)],
                    "config.load lists \(loaded.registered) as registered, expected only \(registered(first))")
                #expect(loaded.issues.count == 2, "expected two issues, got \(loaded.issues)")
                #expect(
                    loaded.issues.first?.hasPrefix("bindings[2]") == true,
                    "the first issue should be about bindings[2] (the plain A): \(loaded.issues)")
                #expect(
                    loaded.issues.last?.hasPrefix("bindings[3]") == true,
                    "the second issue should be about bindings[3] (the duplicate): \(loaded.issues)")

                // Only registered bindings can be pressed.
                for (name, binding) in [("plain A", plainA), ("duplicate", duplicate), ("no shortcut", noShortcut)] {
                    let reason = try piccolo.simulateHotkeyExpectingRefusal(binding.id)
                    #expect(
                        reason.contains("no registered shortcut"),
                        "the refusal for the \(name) binding is \"\(reason)\"")
                }
            }
        }

        // MARK: 5. Replacing

        @Test("config 5. loading a second file replaces the first, and the first file's bindings can no longer be pressed")
        func secondFileReplacesFirst() async throws {
            let screens = try Layout.screens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let fromFirst = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let fromSecond = KeyBinding(action: .placeWindow(.preset(.maximize)), shortcut: TestShortcut.f14)
            let alsoSecond = KeyBinding(action: .placeWindow(.preset(.center)), shortcut: TestShortcut.f16)

            try await withConfigDirectory { config in
                let firstURL = try config.write([fromFirst], as: "first.json")
                let secondURL = try config.write([fromSecond, alsoSecond], as: "second.json")

                let first = try piccolo.loadConfig(at: firstURL)
                #expect(first.registered == [registered(fromFirst)])

                let second = try piccolo.loadConfig(at: secondURL)
                #expect(second.path == secondURL.path)
                #expect(
                    second.registered == [registered(fromSecond), registered(alsoSecond)],
                    "after the second file config.load lists \(second.registered) as registered")
                #expect(try piccolo.configStatus() == second)

                let reason = try piccolo.simulateHotkeyExpectingRefusal(fromFirst.id)
                #expect(
                    reason.contains("no registered shortcut"),
                    "the refusal for a binding of the first file is \"\(reason)\"")

                // The second file's hotkeys work.
                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "replaced", frame: start)
                    try piccolo.simulateHotkey(fromSecond.id)
                    let expected = FrameResolver.frame(
                        for: .preset(.maximize), visibleFrame: visible, currentFrame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                }
            }
        }

        // MARK: 6. A file that is not JSON

        @Test("config 6. a file that is not JSON is reported, registers nothing, and is moved aside next to itself")
        func notJSON() async throws {
            try await withConfigDirectory { config in
                let url = try config.write(text: "this is not JSON {", as: "config.json")

                let loaded = try piccolo.loadConfig(at: url)

                #expect(loaded.path == url.path)
                #expect(loaded.registered.isEmpty, "config.load lists \(loaded.registered) as registered")
                #expect(loaded.bindingCount == 0)
                #expect(loaded.issues.count == 1, "expected one issue, got \(loaded.issues)")
                #expect(
                    loaded.issues.first?.contains("config.json") == true,
                    "the issue should name the file: \(loaded.issues)")

                // The bad file went aside inside the temporary directory; the default location
                // is checked by withConfigDirectory.
                let names = try config.contents()
                #expect(
                    names.count == 1 && names[0].hasPrefix("config.corrupt-") && names[0].hasSuffix(".json"),
                    "the temporary directory should hold only the moved-aside copy, it holds \(names)")
            }
        }

        // MARK: 7. Back to the default location

        @Test("config 7. config.reload goes back to the default location, and the tests left nothing there")
        func backToTheDefaultLocation() async throws {
            let binding = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f17)
            let defaultPath = ConfigLocation.defaultURL.path

            try await withConfigDirectory { config in
                let url = try config.write([binding])
                let loaded = try piccolo.loadConfig(at: url)
                #expect(loaded.path == url.path)
                #expect(loaded.path != defaultPath)

                let reloaded = try piccolo.reloadConfig()
                #expect(
                    reloaded.path == defaultPath,
                    "config.reload reports the config path \(reloaded.path), expected \(defaultPath)")
                #expect(
                    !reloaded.registered.contains { $0.id == binding.id },
                    "the temporary config's binding is still registered after config.reload")
                #expect(try piccolo.configStatus().path == defaultPath)
            }
        }

        // MARK: 8. The default shortcuts

        // Every default is a real global hotkey while this test runs, so the test is short and
        // withConfigDirectory ends it with config.reload. A default that the system refuses on this
        // machine shows up as an issue here, and as a missing registration.
        @Test("config 8. all 25 default shortcuts are registered with no issues on this machine")
        func defaultShortcutsRegister() async throws {
            let defaults = Config.defaultShortcuts.bindings

            try await withConfigDirectory { config in
                let loaded = try piccolo.loadConfig(at: try config.write(defaults))

                #expect(loaded.bindingCount == 25, "the defaults load \(loaded.bindingCount) bindings, expected 25")
                #expect(loaded.issues.isEmpty, "the default shortcuts reported issues: \(loaded.issues)")
                #expect(
                    loaded.registered == defaults.map { registered($0) },
                    "config.load lists \(loaded.registered.count) of the 25 defaults as registered: \(loaded.registered)")
                #expect(try piccolo.configStatus() == loaded, "config.status differs from what config.load answered")
            }
        }

        // MARK: Helpers

        private func registered(_ binding: KeyBinding) -> PiccoloClient.RegisteredShortcut {
            PiccoloClient.RegisteredShortcut(
                id: binding.id, keyCode: binding.shortcut?.keyCode ?? -1,
                modifiers: binding.shortcut?.modifiers ?? [])
        }

        /// Opens a window at `frame`, waits until it is there and brings it into focus, which is
        /// what a hotkey acts on.
        private func openFocused(
            _ fixture: FixtureApp, id: String, frame: CGRect
        ) async throws -> FixtureWindow {
            let window = try fixture.open(id: id, frame: frame)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
            try await Focus.bring(window, of: fixture)
            return window
        }
    }
}
