import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance test for the onboarding guide: the installed Debug Piccolo, with a temporary config that
/// binds test shortcuts (`TestShortcut`) for a `leftHalf` and a 1 × 2 `arrangeGrid`, shows the guide
/// while a fixture window is focused. The guide must never take the focus, the shortcuts it asks for
/// must act on the fixture window, and the window server says what is on screen.
///
/// The test reads the stored `OnboardingSeen` flag first and puts it back at the end, also on failure.
/// The arrangement is held and released only after `preview.state.windows` has been checked to list the
/// two fixture windows and nothing else, as the destination preview tests do, so that no window of the
/// owner is ever moved.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the suite
/// it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Onboarding")
    struct OnboardingAcceptance {
        private let piccolo = PiccoloClient()

        private static let twoByOne = GridSpec(count: 2, rows: 1, columns: 2)

        @Test("onboarding 1. the guide opens over the focused window without taking the focus, completes its move and arrange steps from real shortcuts, and closing it stores that it was seen")
        func guideFollowsTheShortcuts() async throws {
            let screens = try await ArrangeRun.screens()
            let screen = screens[0]
            let start = Layout.frame(in: screen, offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let arrange = KeyBinding(action: .arrangeGrid(Self.twoByOne), shortcut: TestShortcut.f14)
            let expectedLeft = FrameResolver.frame(
                for: .preset(.leftHalf), visibleFrame: screen.visibleFrame, currentFrame: start)
            let cells = ArrangeRun.cells(2, in: Self.twoByOne, on: screen).frames

            try await withOnboardingSeenRestored {
                try await withConfigDirectory { config in
                    try piccolo.loadConfig(
                        at: try config.write(Config(destinationPreview: true, bindings: [leftHalf, arrange])))
                    try await withFixture { fixture in
                        // The guide starts closed, whatever an earlier run left.
                        try piccolo.onboardingClose()
                        let pid = try piccolo.pid()

                        let a = try fixture.open(id: "guide-A", frame: start)
                        _ = try await Measure.waitForFrame(ofWindow: a.windowNumber, matching: start)
                        try await Focus.bring(a, of: fixture)

                        // 1. Open: the panel is on screen, the fixture keeps the front and the focus.
                        try piccolo.onboardingOpen()
                        let opened = try await eventually("the guide to be visible with a frame", timeout: 5) {
                            () -> Observation<PiccoloClient.OnboardingState> in
                            let state = try piccolo.onboardingState()
                            guard state.visible, state.frame != nil else {
                                return .unsatisfied("visible: \(state.visible), frame: \(String(describing: state.frame))")
                            }
                            return .satisfied(state)
                        }
                        let frame = try #require(opened.frame)
                        let entries = try await PiccoloOverlays.waitForHighlights(pid: pid, at: [frame])
                        let floating = Int(CGWindowLevelForKey(.floatingWindow))
                        #expect(
                            entries[0].layer == floating,
                            "the guide should be on the floating window level \(floating); it is on layer \(entries[0].layer)")
                        #expect(abs(frame.width - 420) <= 1, "the guide is \(frame.width) pt wide, not about 420")
                        let display = screens.first { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(frame) }
                        #expect(display != nil, "the guide at \(describe(frame)) is not inside the visible frame of any display")
                        if let display {
                            #expect(
                                abs(display.visibleFrame.maxX - frame.maxX) <= 20 && frame.minY - display.visibleFrame.minY <= 20,
                                "the guide at \(describe(frame)) is not in the top-right corner of \(describe(display.visibleFrame))")
                        }
                        try expectFixtureStillInFront(fixture, window: a, at: start, after: "the guide opened")

                        // Accessibility is granted on the test machine: step 1 is done and the guide
                        // moves on by itself.
                        let move = try await eventually("the guide to reach the move step", timeout: 8) {
                            () -> Observation<PiccoloClient.OnboardingState> in
                            let state = try piccolo.onboardingState()
                            return ["moveWindow", "arrange", "done"].contains(state.step)
                                ? .satisfied(state) : .unsatisfied("the step is \(state.step), done: \(state.done)")
                        }
                        #expect(move.done.contains("accessibility"), "step 1 is not done: \(move.done)")
                        #expect(move.moveBindingID == leftHalf.id, "the move step asks for \(String(describing: move.moveBindingID)), not the leftHalf test binding \(leftHalf.id)")
                        #expect(move.arrangeBindingID == arrange.id, "the arrange step asks for \(String(describing: move.arrangeBindingID)), not the test binding \(arrange.id)")
                        try expectFixtureStillInFront(fixture, window: a, at: start, after: "the guide moved to step 2")

                        // 2. The shortcut moves the focused fixture window to the left half.
                        try piccolo.simulateHotkey(leftHalf.id)
                        _ = try await Measure.waitForFrame(ofWindow: a.windowNumber, matching: expectedLeft)
                        _ = try await eventually("the guide to reach the arrange step", timeout: 8) {
                            () -> Observation<Void> in
                            let state = try piccolo.onboardingState()
                            return state.step == "arrange" || state.step == "done"
                                ? .satisfied(()) : .unsatisfied("the step is \(state.step), done: \(state.done)")
                        }

                        // 3. Two fixture windows brought forward in turn are the two most recent.
                        let run = ArrangeRun(fixture: fixture)
                        let bFrame = ArrangeRun.cascadeFrame(1, on: screen)
                        let b = try fixture.open(id: "guide-B", frame: bFrame)
                        _ = try await Measure.waitForFrame(ofWindow: b.windowNumber, matching: bFrame)
                        try await run.focus([a, b])
                        let order = [b.windowNumber, a.windowNumber]

                        try piccolo.pressHotkey(arrange.id)
                        let held = try await eventually("preview.state to show 2 highlights for the arrangement", timeout: 8) {
                            () -> Observation<PiccoloClient.PreviewState> in
                            let state = try piccolo.previewState()
                            guard state.visible, state.frames.count == 2 else {
                                return .unsatisfied("visible: \(state.visible), frames: \(state.frames.map(describe)), planning error: \(state.planningError ?? "none")")
                            }
                            return .satisfied(state)
                        }
                        guard held.windows == order else {
                            try? piccolo.pressEscape()
                            try? piccolo.releaseHotkey(arrange.id)
                            throw AcceptanceFailure(
                                "the preview refers to the windows \(String(describing: held.windows)), expected exactly the fixture's \(order); "
                                    + "another window is among the most recently focused ones, so the shortcut was cancelled with Escape and the arrangement did not run")
                        }
                        try piccolo.releaseHotkey(arrange.id)
                        for (index, number) in order.enumerated() {
                            _ = try await Measure.waitForFrame(ofWindow: number, matching: cells[index])
                        }
                        _ = try await eventually("the guide to reach the last step", timeout: 8) { () -> Observation<Void> in
                            let state = try piccolo.onboardingState()
                            return state.step == "done"
                                ? .satisfied(()) : .unsatisfied("the step is \(state.step), done: \(state.done)")
                        }
                        #expect(
                            Frontmost.state() == .application(FixtureApp.bundleID),
                            "the guide changed the frontmost application: \(Frontmost.state())")

                        // 4. Closing it: gone from the screen, and stored as seen.
                        try piccolo.onboardingSetSeen(false)
                        let closed = try piccolo.onboardingClose()
                        #expect(!closed.visible)
                        #expect(closed.seen, "closing the guide should store that it was seen")
                        try await PiccoloOverlays.waitForNoHighlight(pid: pid, at: [frame])

                        // 5. The guide never activated Piccolo, so its hotkeys still fire.
                        try piccolo.simulateHotkey(leftHalf.id)
                    }
                }
            }
        }

        // MARK: Helpers

        /// The fixture is still the frontmost application, and its window the one Piccolo reports as
        /// focused, at `frame`.
        private func expectFixtureStillInFront(
            _ fixture: FixtureApp, window: FixtureWindow, at frame: CGRect, after what: String
        ) throws {
            #expect(
                Frontmost.state() == .application(FixtureApp.bundleID),
                "\(what), and the frontmost application changed: \(Frontmost.state())")
            let focused = try piccolo.focusedWindow()
            #expect(
                fixture.processIDs().contains(focused.pid),
                "\(what), and the focused window belongs to pid \(focused.pid), not to the fixture")
            #expect(
                framesMatch(focused.frame, frame),
                "\(what), and the focused window is at \(describe(focused.frame)), not at \(describe(frame))")
        }

        /// Runs `body`, then puts the stored `OnboardingSeen` flag back as it was before, also when
        /// `body` failed: removed when it was not stored, written with its old value otherwise. A failure
        /// to put it back is recorded as an issue of its own.
        private func withOnboardingSeenRestored(_ body: () async throws -> Void) async throws {
            let original = try piccolo.onboardingState()
            do {
                try await body()
            } catch {
                restore(original)
                throw error
            }
            restore(original)
        }

        private func restore(_ original: PiccoloClient.OnboardingState) {
            let value: Bool? = original.seenStored ? original.seen : nil
            do {
                let state = try piccolo.onboardingSetSeen(value)
                // A guide left open by a failed test is closed without touching the flag again.
                if state.visible {
                    try piccolo.onboardingClose()
                    try piccolo.onboardingSetSeen(value)
                }
            } catch {
                Issue.record("could not put OnboardingSeen back to \(value.map { String($0) } ?? "absent"): \(error)")
            }
        }
    }
}
