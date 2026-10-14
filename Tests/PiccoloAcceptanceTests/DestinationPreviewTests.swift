import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for the destination preview: the installed Debug Piccolo, with a temporary config
/// (`config.load`) that binds test shortcuts (`TestShortcut`), is driven with real keyboard events
/// (`hotkey.press`, `hotkey.release`, `hotkey.escape`, `hotkey.simulate`), and the window server says
/// what is on screen.
///
/// A hold is a press without the release. The tests that hold a shortcut always end it before they
/// finish: the release runs the action on the focused fixture window, an Escape cancels it, and
/// `withConfigDirectory` ends with `config.reload`, which cancels whatever is still held without
/// running it. No test releases a shortcut whose action could move a window of somebody else: the
/// focused window is always a window of the fixture, and the test of an arrangement checks which
/// windows the preview refers to before it releases.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Destination preview")
    struct DestinationPreviewAcceptance {
        private let piccolo = PiccoloClient()

        private static let grid = GridSpec(count: 3, rows: 2, columns: 2)

        // MARK: 1. Hold and release

        @Test("preview 1. holding leftHalf shows the highlight at the left half and leaves the window and the focus alone; releasing hides it and moves the window")
        func holdAndRelease() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let expected = FrameResolver.frame(
                for: .preset(.leftHalf), visibleFrame: screens[0].visibleFrame, currentFrame: start)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write([leftHalf]))
                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "hold", frame: start)
                    let pid = try piccolo.pid()

                    try piccolo.pressHotkey(leftHalf.id)

                    // The highlight: Piccolo says it is visible at the left half, and the window server
                    // has a window of Piccolo's process there.
                    let state = try await eventually(
                        "preview.state to be visible at the left half \(describe(expected))", timeout: 5
                    ) { () -> Observation<PiccoloClient.PreviewState> in
                        let state = try piccolo.previewState()
                        guard state.visible, state.frames.count == 1, framesMatch(state.frames[0], expected) else {
                            return .unsatisfied("visible: \(state.visible), frames: \(state.frames.map(describe)), planning error: \(state.planningError ?? "none")")
                        }
                        return .satisfied(state)
                    }
                    #expect(state.heldBindingID == leftHalf.id)
                    #expect(state.escapeRegistered, "Escape should be registered while the shortcut is held")
                    #expect(state.windows == nil, "a single-window action lists no windows, it lists \(String(describing: state.windows))")
                    let highlights = try await PiccoloOverlays.waitForHighlights(pid: pid, at: [expected])
                    // The status bar level: above ordinary windows (layer 0) and floating panels.
                    let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
                    #expect(
                        highlights[0].layer == statusLevel,
                        "the highlight should be on the status window level \(statusLevel), above ordinary windows; it is on layer \(highlights[0].layer)")
                    // It fades in and is then fully shown.
                    _ = try await eventually("the highlight to be fully opaque", timeout: 3) { () -> Observation<Void> in
                        let alphas = PiccoloOverlays.onScreen(pid: pid).map(\.alpha)
                        return alphas.count == 1 && alphas[0] > 0.99 ? .satisfied(()) : .unsatisfied("alphas \(alphas)")
                    }

                    // Nothing else happened: the window is where it was, still the focused window, and
                    // Piccolo has not become the frontmost application.
                    let measured = Measure.frame(ofWindow: window.windowNumber)
                    #expect(
                        measured.map { framesMatch($0, start) } == true,
                        "the fixture window moved to \(measured.map { describe($0) } ?? "nowhere") while the shortcut was held")
                    let focused = try piccolo.focusedWindow()
                    #expect(fixture.processIDs().contains(focused.pid), "the focused window belongs to pid \(focused.pid), not to the fixture")
                    #expect(framesMatch(focused.frame, start), "the focused window is at \(describe(focused.frame)), not at \(describe(start))")
                    #expect(
                        Frontmost.state() == .application(FixtureApp.bundleID),
                        "the highlight changed the frontmost application: \(Frontmost.state())")

                    // Piccolo's own windows, the highlight included, are left out of the windows an
                    // arrangement may move.
                    let ownWindows = try piccolo.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2), onlyPid: pid)
                    #expect(
                        ownWindows == .nothingToDo,
                        "an arrangement of Piccolo's own windows, with the highlight on screen, answered \(ownWindows)")

                    try piccolo.releaseHotkey(leftHalf.id)

                    try await PiccoloOverlays.waitForNoHighlight(pid: pid, at: [expected])
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                    let after = try piccolo.previewState()
                    #expect(!after.visible, "preview.state is still visible after the release")
                    #expect(!after.escapeRegistered, "Escape is still registered after the release")
                    #expect(after.heldBindingID == nil)
                    #expect(
                        after.last == PiccoloClient.PreviewState.Last(bindingID: leftHalf.id, result: "ran", previewShown: true),
                        "last is \(String(describing: after.last))")
                }
            }
        }

        // MARK: 2. Escape

        @Test("preview 2. Escape while held hides the highlight, the release does nothing, and Escape does not reach the focused window")
        func escapeCancels() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let expected = FrameResolver.frame(
                for: .preset(.leftHalf), visibleFrame: screens[0].visibleFrame, currentFrame: start)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write([leftHalf]))
                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "escape", frame: start)
                    let pid = try piccolo.pid()

                    try piccolo.pressHotkey(leftHalf.id)
                    _ = try await PiccoloOverlays.waitForHighlights(pid: pid, at: [expected])

                    try piccolo.pressEscape()

                    try await PiccoloOverlays.waitForNoHighlight(pid: pid, at: [expected])
                    let cancelled = try piccolo.previewState()
                    #expect(!cancelled.visible, "preview.state is still visible after Escape")
                    #expect(cancelled.heldBindingID == leftHalf.id, "the shortcut is still down after Escape")

                    try piccolo.releaseHotkey(leftHalf.id)

                    let after = try piccolo.previewState()
                    #expect(
                        after.last == PiccoloClient.PreviewState.Last(bindingID: leftHalf.id, result: "cancelled", previewShown: true),
                        "last is \(String(describing: after.last))")
                    #expect(after.heldBindingID == nil)
                    #expect(!after.escapeRegistered)

                    // The release must not move the window, which would show within the animation.
                    try await expectStays(window, at: start, for: 0.6)
                    let keys = try fixture.keyEvents(id: "escape")
                    #expect(!keys.contains(53), "the fixture window received an Escape key-down: \(keys)")
                }
            }
        }

        // MARK: 3. Tap

        @Test("preview 3. a tap moves the window and shows no highlight")
        func tap() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let expected = FrameResolver.frame(
                for: .preset(.leftHalf), visibleFrame: screens[0].visibleFrame, currentFrame: start)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write([leftHalf]))
                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "tap", frame: start)
                    let pid = try piccolo.pid()

                    try piccolo.simulateHotkey(leftHalf.id)

                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                    let state = try piccolo.previewState()
                    #expect(
                        state.last == PiccoloClient.PreviewState.Last(bindingID: leftHalf.id, result: "ran", previewShown: false),
                        "last is \(String(describing: state.last))")
                    #expect(!state.visible)
                    #expect(state.heldBindingID == nil)
                    #expect(
                        PiccoloOverlays.onScreen(pid: pid).isEmpty,
                        "a tap left windows of Piccolo on screen: \(PiccoloOverlays.onScreen(pid: pid))")
                }
            }
        }

        // MARK: 4. Arrange

        @Test("preview 4. holding an arrangement of 3 windows in 2×2 shows one highlight per cell for exactly the 3 fixture windows; the release arranges them")
        func holdArrangement() async throws {
            let screen = try await ArrangeRun.screens()[0]
            let arrange = KeyBinding(action: .arrangeGrid(Self.grid), shortcut: TestShortcut.f14)
            let cells = ArrangeRun.cells(3, in: Self.grid, on: screen).frames

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write([arrange]))
                try await withFixture { fixture in
                    let run = ArrangeRun(fixture: fixture)
                    let windows = try await run.open(["A", "B", "C"], on: screen)
                    // Brought forward in turn: C is the most recent, then B, then A.
                    try await run.focus(windows)
                    let order = windows.reversed().map(\.windowNumber)
                    let pid = try piccolo.pid()

                    try piccolo.pressHotkey(arrange.id)

                    let state = try await eventually(
                        "preview.state to show 3 highlights for an arrangement", timeout: 8
                    ) { () -> Observation<PiccoloClient.PreviewState> in
                        let state = try piccolo.previewState()
                        guard state.visible, state.frames.count == 3 else {
                            return .unsatisfied("visible: \(state.visible), frames: \(state.frames.map(describe)), planning error: \(state.planningError ?? "none")")
                        }
                        return .satisfied(state)
                    }

                    // Before anything is released: are these the windows of the fixture, and only those?
                    guard state.windows == order else {
                        try? piccolo.pressEscape()
                        throw AcceptanceFailure(
                            "the preview refers to the windows \(String(describing: state.windows)), expected exactly the fixture's windows \(order) "
                                + "(C, B, A); another window is among the most recently focused ones, so the shortcut was cancelled with Escape and not released")
                    }
                    for (index, cell) in cells.enumerated() {
                        #expect(
                            framesMatch(state.frames[index], cell),
                            "highlight \(index) is at \(describe(state.frames[index])), cell \(index) is \(describe(cell))")
                    }
                    let highlights = try await PiccoloOverlays.waitForHighlights(pid: pid, at: cells)
                    #expect(Set(highlights.map(\.number)).count == 3, "the three highlights are not three windows: \(highlights)")

                    try piccolo.releaseHotkey(arrange.id)

                    try await PiccoloOverlays.waitForNoHighlight(pid: pid, at: cells)
                    for (index, number) in order.enumerated() {
                        _ = try await Measure.waitForFrame(ofWindow: number, matching: cells[index])
                    }
                    let after = try piccolo.previewState()
                    #expect(
                        after.last == PiccoloClient.PreviewState.Last(bindingID: arrange.id, result: "ran", previewShown: true),
                        "last is \(String(describing: after.last))")
                }
            }
        }

        // MARK: 5. Preview off

        @Test("preview 5. with destinationPreview false the press alone moves the window, and no highlight appears")
        func previewOff() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let expected = FrameResolver.frame(
                for: .preset(.leftHalf), visibleFrame: screens[0].visibleFrame, currentFrame: start)

            try await withConfigDirectory { config in
                let url = try config.write(Config(destinationPreview: false, bindings: [leftHalf]))
                try piccolo.loadConfig(at: url)
                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "off", frame: start)
                    let pid = try piccolo.pid()

                    try piccolo.pressHotkey(leftHalf.id)

                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                    let state = try piccolo.previewState()
                    #expect(!state.visible, "the preview is visible with destinationPreview false")
                    #expect(!state.escapeRegistered, "Escape is registered with destinationPreview false")
                    #expect(state.heldBindingID == nil)
                    #expect(
                        state.last == PiccoloClient.PreviewState.Last(bindingID: leftHalf.id, result: "ran", previewShown: false),
                        "last is \(String(describing: state.last))")
                    #expect(
                        PiccoloOverlays.onScreen(pid: pid).isEmpty,
                        "windows of Piccolo are on screen with destinationPreview false: \(PiccoloOverlays.onScreen(pid: pid))")

                    // The key goes up; nothing more happens.
                    try piccolo.releaseHotkey(leftHalf.id)
                    try await expectStays(window, at: expected, for: 0.3)
                }
            }
        }

        // MARK: Carbon

        // What `CarbonHotkeyBackend` documents about the events of a key that is held. The key events
        // are posted by Piccolo with a private event source (`hotkey.press`, `hotkey.release`): the
        // keyboard's own auto-repeat cannot be produced from here, so a key-down flagged as
        // auto-repeat, and a second key-down without a key-up before it, stand for it.
        @Test("carbon 1. a key that is held delivers one press: key-downs flagged as auto-repeat, and a second key-down without a key-up, are not delivered")
        func carbonHeldKeyDeliversOnePress() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write([leftHalf]))
                try await withFixture { fixture in
                    _ = try await openFocused(fixture, id: "carbon-repeat", frame: start)

                    let presses = try piccolo.pressHotkey(leftHalf.id, autorepeat: 5)
                    #expect(
                        presses == 1,
                        "1 key-down and 5 auto-repeat key-downs delivered \(String(describing: presses)) presses, expected 1")

                    let response = try piccolo.sendRaw("hotkey.press", ["id": .string(leftHalf.id.uuidString)])
                    #expect(
                        !response.ok,
                        "a second key-down while the key is down was delivered as a press: \(String(describing: response.result))")

                    try piccolo.pressEscape()
                    try piccolo.releaseHotkey(leftHalf.id)
                }
            }
        }

        @Test("carbon 2. the release is delivered also when the modifiers go up before the key")
        func carbonModifiersFirst() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let expected = FrameResolver.frame(
                for: .preset(.leftHalf), visibleFrame: screens[0].visibleFrame, currentFrame: start)
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write([leftHalf]))
                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "carbon-modifiers", frame: start)
                    let pid = try piccolo.pid()

                    try piccolo.pressHotkey(leftHalf.id)
                    _ = try await PiccoloOverlays.waitForHighlights(pid: pid, at: [expected])

                    // A flags-changed event with no flags (the modifiers went up), then the key-up.
                    try piccolo.releaseHotkey(leftHalf.id, modifiersFirst: true)

                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                    try await PiccoloOverlays.waitForNoHighlight(pid: pid, at: [expected])
                    let state = try piccolo.previewState()
                    #expect(state.heldBindingID == nil, "the shortcut is still held after its key went up")
                    #expect(
                        state.last == PiccoloClient.PreviewState.Last(bindingID: leftHalf.id, result: "ran", previewShown: true),
                        "last is \(String(describing: state.last))")
                }
            }
        }

        // MARK: Helpers

        /// Opens a window at `frame`, waits until it is there and brings it into focus, which is what a
        /// hotkey acts on.
        private func openFocused(_ fixture: FixtureApp, id: String, frame: CGRect) async throws -> FixtureWindow {
            let window = try fixture.open(id: id, frame: frame)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
            try await Focus.bring(window, of: fixture)
            return window
        }

        /// Checks that the window stays at `frame` for `duration` seconds: a negative result has to be
        /// watched for a while, and the animation of an action takes 0.15 s.
        private func expectStays(_ window: FixtureWindow, at frame: CGRect, for duration: TimeInterval) async throws {
            let clock = ContinuousClock()
            let start = clock.now
            while start.duration(to: clock.now) < .seconds(duration) {
                let measured = Measure.frame(ofWindow: window.windowNumber)
                guard measured.map({ framesMatch($0, frame) }) == true else {
                    throw AcceptanceFailure(
                        "window '\(window.id)' should have stayed at \(describe(frame)), it is measured at \(measured.map { describe($0) } ?? "nowhere")")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
