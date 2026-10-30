import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import Testing

/// What `notice.state` answers.
struct NoticeState: Equatable {
    struct Last: Equatable {
        var kind: String
        var text: String
        var frame: CGRect
    }

    var visible: Bool
    var last: Last?
}

extension PiccoloClient {
    /// `notice.state`.
    func noticeState() throws -> NoticeState {
        let result = try send("notice.state")
        guard let visible = result["visible"]?.boolValue else {
            throw AcceptanceFailure("Piccolo's notice.state answer is malformed: \(result)")
        }
        var last: NoticeState.Last?
        if let entry = result["last"], entry != .null {
            guard let kind = entry["kind"]?.stringValue, let text = entry["text"]?.stringValue,
                let frame = entry["frame"]?.rectValue
            else {
                throw AcceptanceFailure("notice.state has a malformed last: \(entry)")
            }
            last = NoticeState.Last(kind: kind, text: text, frame: frame)
        }
        return NoticeState(visible: visible, last: last)
    }
}

/// Acceptance tests for the failure notice: a shortcut that cannot act shows a short notice in the
/// middle of the display, and never takes the focus. Run with `scripts/accept.sh Notice`.
extension DesktopAcceptanceTests {
    @Suite("Failure notice")
    struct FailureNoticeAcceptance {
        private let piccolo = PiccoloClient()

        @Test("notice 1. a moveDivider shortcut with no group shows the noGroup notice, centred on the window's display, without taking the focus, and it goes away")
        func noGroupNotice() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let divider = KeyBinding(action: .moveDivider(.right), shortcut: TestShortcut.f13)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write(Config(destinationPreview: false, bindings: [divider])))
                try await withFixture { fixture in
                    let window = try fixture.open(id: "notice", frame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)
                    try await Focus.bring(window, of: fixture)
                    let pid = try piccolo.pid()
                    let texts = try InterfaceTexts.current(piccolo)

                    try piccolo.simulateHotkey(divider.id)

                    let state = try await eventually("notice.state to be visible with a last notice", timeout: 5) {
                        () -> Observation<NoticeState> in
                        let state = try piccolo.noticeState()
                        return state.visible && state.last != nil ? .satisfied(state) : .unsatisfied("\(state)")
                    }
                    let last = try #require(state.last)
                    #expect(last.kind == "noGroup", "the kind is \(last.kind)")
                    #expect(last.text == texts.notice(.noGroup), "the text is \"\(last.text)\"")

                    // A window of Piccolo's process on the status level is at the frame, in the middle of
                    // the display that holds the fixture window.
                    let entries = try await PiccoloOverlays.waitForHighlights(pid: pid, at: [last.frame])
                    let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
                    #expect(entries[0].layer == statusLevel, "the notice is on layer \(entries[0].layer), not \(statusLevel)")
                    let visibleFrame = screens[0].visibleFrame
                    #expect(
                        abs(last.frame.midX - visibleFrame.midX) <= 1 && abs(last.frame.midY - visibleFrame.midY) <= 1,
                        "the notice at \(describe(last.frame)) is not centred on the display's visible frame \(describe(visibleFrame))")

                    // Nothing else happened: the fixture is frontmost and its window the focused one.
                    #expect(
                        Frontmost.state() == .application(FixtureApp.bundleID),
                        "the notice changed the frontmost application: \(Frontmost.state())")
                    let focused = try piccolo.focusedWindow()
                    #expect(fixture.processIDs().contains(focused.pid), "the focused window belongs to pid \(focused.pid), not to the fixture")
                    #expect(framesMatch(focused.frame, start), "the focused window is at \(describe(focused.frame)), not at \(describe(start))")

                    // It goes away within 3 s.
                    _ = try await eventually("the notice to be gone", timeout: 3) { () -> Observation<Void> in
                        let visible = try piccolo.noticeState().visible
                        let onScreen = PiccoloOverlays.onScreen(pid: pid).contains { framesMatch($0.frame, last.frame) }
                        return !visible && !onScreen ? .satisfied(()) : .unsatisfied("visible: \(visible), on screen: \(onScreen)")
                    }
                }
            }
        }

        @Test("notice 2. a placeWindow shortcut, run twice, shows no notice")
        func placeShowsNothing() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)
            let expected = FrameResolver.frame(
                for: .preset(.leftHalf), visibleFrame: screens[0].visibleFrame, currentFrame: start)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write(Config(destinationPreview: false, bindings: [leftHalf])))
                try await withFixture { fixture in
                    let window = try fixture.open(id: "notice-place", frame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)
                    try await Focus.bring(window, of: fixture)

                    let before = try piccolo.noticeState().last
                    try piccolo.simulateHotkey(leftHalf.id)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                    try piccolo.simulateHotkey(leftHalf.id)

                    // A negative result has to be watched for a while.
                    let clock = ContinuousClock()
                    let begin = clock.now
                    while begin.duration(to: clock.now) < .seconds(1.5) {
                        let state = try piccolo.noticeState()
                        #expect(!state.visible, "a notice became visible: \(state)")
                        #expect(state.last == before, "a notice was shown: \(String(describing: state.last))")
                        if state.visible || state.last != before { return }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }
            }
        }

        @Test("notice 3. action.run of a moveDivider with no group answers nothingToDo and shows no notice")
        func actionRunShowsNothing() async throws {
            let screens = try Layout.screens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let divider = KeyBinding(action: .moveDivider(.right), shortcut: TestShortcut.f13)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write(Config(destinationPreview: false, bindings: [divider])))
                try await withFixture { fixture in
                    let window = try fixture.open(id: "notice-run", frame: start)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)
                    try await Focus.bring(window, of: fixture)
                    let pid = try piccolo.pid()
                    let before = try piccolo.noticeState().last

                    let result = try piccolo.moveDivider(.right, onlyPid: pid)
                    guard case .nothingToDo(let nothing) = result else {
                        Issue.record("action.run answered \(result), not nothingToDo")
                        return
                    }
                    #expect(nothing.reason == "noGroup" || nothing.reason == "noFocusedWindow", "the reason is \(nothing.reason)")

                    let clock = ContinuousClock()
                    let begin = clock.now
                    while begin.duration(to: clock.now) < .seconds(1) {
                        let state = try piccolo.noticeState()
                        #expect(!state.visible && state.last == before, "action.run showed a notice: \(state)")
                        if state.visible || state.last != before { return }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }
            }
        }
    }
}
