import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import Testing

/// Acceptance tests for bringing the Settings window to the front: with a window of another
/// application in front, opening Settings makes Piccolo the active application and the Settings
/// window its key window, whatever asked for it (the control channel, which is the worst case
/// because no user event is behind it, a second launch).
///
/// Every round starts with a fixture window verified as frontmost (`Focus.bring`), then asks
/// Piccolo to open Settings and looks at what the system says: `lsappinfo front` (measured here,
/// independently of Piccolo) and `settings.state` (`isActive`, `isKey`). Each round is logged, so
/// that a run shows what happened to an activation request that was refused.
///
/// Piccolo has been the active application after these tests, so `withSettingsSession` ends them by
/// restarting it (see ``PiccoloProcess``).
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Settings in front")
    struct SettingsInFront {
        private let piccolo = PiccoloClient()

        /// How many times the activation has to work, in a row: one miss is a failure.
        private static let rounds = 10

        /// How long Piccolo is given to become the active application after `settings.open`.
        private static let frontTimeout: TimeInterval = 5

        // MARK: 1. settings.open from another application

        @Test("settingsInFront 1. settings.open with a fixture window in front makes Piccolo frontmost and Settings the key window, 10 rounds of 10")
        func openFromAnotherApplication() async throws {
            let screens = try await MainActor.run { try Layout.screens() }
            let frame = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))

            try await withSettingsSession { session in
                try await withFixture { fixture in
                    let window = try fixture.open(id: "in-front", frame: frame)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
                    let pid = try piccolo.pid()

                    var misses: [String] = []
                    for round in 1...Self.rounds {
                        try await Focus.bring(window, of: fixture)
                        let before = Frontmost.bundleID() ?? "none"

                        let clock = ContinuousClock()
                        let start = clock.now
                        let opened = try session.openSettings()
                        let answered = start.duration(to: clock.now)
                        let immediately = Frontmost.bundleID() ?? "none"

                        // The window is there at once, whether or not the activation has come yet.
                        var problems: [String] = []
                        if !opened.isOpen { problems.append("settings.open answered isOpen: false") }
                        do {
                            _ = try await PiccoloWindows.waitForWindow(pid: pid, timeout: 1)
                        } catch {
                            problems.append("no window of Piccolo on screen within 1 s of settings.open: \(error)")
                        }

                        var arrived = "never"
                        do {
                            let state: SettingsState = try await eventually(
                                "Piccolo to be frontmost with the Settings window key (round \(round))",
                                timeout: Self.frontTimeout
                            ) { () throws -> Observation<SettingsState> in
                                let front = Frontmost.state()
                                let state = try piccolo.settingsState()
                                guard front == .application(piccoloBundleID) else {
                                    return .unsatisfied(
                                        "\(Frontmost.explain(front, wanted: piccoloBundleID)); isOpen \(state.isOpen), isActive \(state.isActive), isKey \(state.isKey)"
                                    )
                                }
                                guard state.isOpen, state.isKey else {
                                    return .unsatisfied(
                                        "Piccolo is frontmost but isOpen \(state.isOpen), isActive \(state.isActive), isKey \(state.isKey)")
                                }
                                return .satisfied(state)
                            }
                            arrived = "\(start.duration(to: clock.now)) (isActive \(state.isActive), isKey \(state.isKey))"
                        } catch {
                            problems.append("\(error)")
                        }

                        print(
                            "settingsInFront round \(round): front before \(before); settings.open answered after \(answered) "
                                + "with isOpen \(opened.isOpen), isActive \(opened.isActive), isKey \(opened.isKey), "
                                + "front then \(immediately); in front: \(arrived)"
                                + (problems.isEmpty ? "" : "; PROBLEMS: \(problems.joined(separator: " | "))"))
                        if !problems.isEmpty { misses.append("round \(round): \(problems.joined(separator: " | "))") }

                        let closed = try piccolo.settingsClose()
                        #expect(!closed.isOpen, "settings.close answered isOpen: true in round \(round)")
                    }

                    #expect(
                        misses.isEmpty,
                        "Settings did not come to the front in \(misses.count) of \(Self.rounds) rounds: \(misses.joined(separator: "; "))"
                    )
                }
            }
        }

        // MARK: 2. A second settings.open while Piccolo is in front

        @Test("settingsInFront 2. settings.open while Settings is open and in front changes nothing: still key, one window, same process")
        func openWhileInFrontChangesNothing() async throws {
            try await withSettingsSession { session in
                let pid = try piccolo.pid()
                _ = try session.openSettings()
                try await session.bringPiccoloForward()
                try await eventually("Settings to be the key window", timeout: Self.frontTimeout) { () throws -> Observation<Void> in
                    let state = try piccolo.settingsState()
                    return state.isOpen && state.isKey ? .satisfied(()) : .unsatisfied("isOpen \(state.isOpen), isKey \(state.isKey)")
                }
                _ = try await PiccoloWindows.waitForWindow(pid: pid)
                let framesBefore = PiccoloWindows.onScreen(pid: pid)
                #expect(framesBefore.count == 1, "expected one window of Piccolo, saw \(framesBefore.map(describe))")

                for _ in 1...3 {
                    let again = try piccolo.settingsOpen()
                    #expect(again.isOpen && again.isKey, "isOpen \(again.isOpen), isKey \(again.isKey) after a second settings.open")
                }
                #expect(Frontmost.state() == .application(piccoloBundleID), "Piccolo is no longer frontmost: \(Frontmost.state())")
                #expect(try piccolo.pid() == pid, "Piccolo was restarted")
                let framesAfter = PiccoloWindows.onScreen(pid: pid)
                #expect(framesAfter.count == 1, "expected one window of Piccolo after the second settings.open, saw \(framesAfter.map(describe))")
            }
        }

        // MARK: 3. A second launch from another application

        @Test("settingsInFront 3. launching Piccolo again with a fixture window in front opens Settings as the key window of the frontmost Piccolo")
        func secondLaunchFromAnotherApplication() async throws {
            let screens = try await MainActor.run { try Layout.screens() }
            let frame = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))

            try await withSettingsSession { session in
                try await withFixture { fixture in
                    let window = try fixture.open(id: "second-launch", frame: frame)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
                    let pid = try piccolo.pid()
                    try await Focus.bring(window, of: fixture)

                    session.markPiccoloActivated()
                    try Shell.open([try piccolo.bundlePath()])

                    try await eventually("Settings to be open, key, and Piccolo frontmost", timeout: Self.frontTimeout) {
                        () throws -> Observation<Void> in
                        let front = Frontmost.state()
                        let state = try piccolo.settingsState()
                        guard front == .application(piccoloBundleID) else {
                            return .unsatisfied("\(Frontmost.explain(front, wanted: piccoloBundleID)); isOpen \(state.isOpen), isKey \(state.isKey)")
                        }
                        return state.isOpen && state.isKey ? .satisfied(()) : .unsatisfied("isOpen \(state.isOpen), isKey \(state.isKey)")
                    }
                    #expect(try piccolo.pid() == pid, "launching again started a second Piccolo")
                    _ = try await PiccoloWindows.waitForWindow(pid: pid)
                    let frames = PiccoloWindows.onScreen(pid: pid)
                    #expect(frames.count == 1, "expected one window of Piccolo, saw \(frames.map(describe))")
                }
            }
        }
    }
}
