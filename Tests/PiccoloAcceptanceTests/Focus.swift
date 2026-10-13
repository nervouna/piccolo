import CoreGraphics
import Foundation

/// Brings a fixture window into the state a Piccolo action needs: its app frontmost and
/// the window key. Focus is verified, never assumed.
///
/// Since macOS 14 an app cannot always activate itself, so asking the fixture to focus a
/// window is only a request. What reliably works is the way a user does it: hand the app
/// to LaunchServices (`open`), which the system treats as user intent. The request to the
/// fixture then makes the window key. Both are repeated until the state is observed:
///
/// 1. LaunchServices names the fixture's bundle ID as the frontmost app. This is
///    measured by this process, independently of the fixture and of Piccolo. When it names
///    something else, the failure says which of three things it is: the screen is locked (fails
///    at once), no application is frontmost (`loginwindow` while the screen is not locked; cleared
///    by handing the front to Finder if it lasts), or another application is.
/// 2. The fixture reports the window as key.
/// 3. Piccolo, the app under test, agrees: the focused window it sees belongs to the
///    fixture's process and has the window's frame. This is what a Piccolo action acts on.
enum Focus {
    /// Seconds between two attempts to hand the focus over. An attempt that has worked
    /// is picked up by the next look well before that.
    private static let retryInterval: TimeInterval = 1.5

    /// How long "no application is frontmost" may last before the front is handed to Finder.
    private static let noApplicationGrace: Duration = .seconds(1)

    /// - Parameter recovering: Whether to clear a "no application is frontmost" state that lasts
    ///   (see ``Frontmost/clearNoApplication()``). The stress tests turn it off, so that a restart
    ///   that leaves the desktop in that state fails them and is not repaired behind their back.
    static func bring(
        _ window: FixtureWindow,
        of fixture: FixtureApp,
        seenBy piccolo: PiccoloClient? = PiccoloClient(),
        timeout: TimeInterval = 15,
        recovering: Bool = true
    ) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        var lastAttempt: ContinuousClock.Instant?
        var attempts = 0
        var lastSeen = "nothing observed"
        var noApplicationSince: ContinuousClock.Instant?
        var cleared = false

        while true {
            // A locked screen does not get better by waiting; no application being frontmost may.
            let front = Frontmost.state()
            switch front {
            case .locked:
                throw AcceptanceFailure(
                    "focus cannot be established: \(Frontmost.explain(front, wanted: FixtureApp.bundleID))",
                    isRetryable: false)
            case .noApplication:
                noApplicationSince = noApplicationSince ?? clock.now
                if recovering, !cleared, noApplicationSince.map({ $0.duration(to: clock.now) >= noApplicationGrace }) == true {
                    cleared = true
                    try Frontmost.clearNoApplication()
                }
            case .application:
                noApplicationSince = nil
            }

            if lastAttempt.map({ $0.duration(to: clock.now) >= .seconds(retryInterval) }) ?? true {
                attempts += 1
                lastAttempt = clock.now
                try Shell.open([Acceptance.fixtureAppURL.path])
                try fixture.requestFocus(id: window.id)
            }

            switch try look(at: window, of: fixture, seenBy: piccolo, front: front) {
            case .satisfied:
                return
            case .unsatisfied(let seen):
                lastSeen = seen
            }

            if start.duration(to: clock.now) >= .seconds(timeout) {
                throw AcceptanceFailure(
                    "focus was not established within \(String(format: "%.1f", timeout)) s "
                        + "after \(attempts) attempt(s) to hand it to the fixture window '\(window.id)'"
                        + (cleared ? " (and the front was handed to Finder once)" : "")
                        + "; last observed: \(lastSeen)")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// One look at the system. Throws only for failures that waiting cannot fix.
    private static func look(
        at window: FixtureWindow, of fixture: FixtureApp, seenBy piccolo: PiccoloClient?, front: FrontState
    ) throws -> Observation<Void> {
        guard front == .application(FixtureApp.bundleID) else {
            return .unsatisfied(Frontmost.explain(front, wanted: FixtureApp.bundleID))
        }

        let listed: [FixtureWindow]
        do {
            listed = try fixture.list()
        } catch {
            try rethrowIfFatal(error)
            return .unsatisfied("the fixture does not answer: \(error.localizedDescription)")
        }
        guard let entry = listed.first(where: { $0.id == window.id }) else {
            return .unsatisfied("the fixture has no window '\(window.id)' (it lists \(listed.map(\.id)))")
        }
        guard entry.isKey else {
            return .unsatisfied("the fixture is frontmost but window '\(window.id)' is not key")
        }

        guard let piccolo else { return .satisfied(()) }
        let focused: (pid: pid_t, frame: CGRect)
        do {
            focused = try piccolo.focusedWindow()
        } catch {
            try rethrowIfFatal(error)
            return .unsatisfied("Piccolo cannot read the focused window: \(error.localizedDescription)")
        }
        guard fixture.processIDs().contains(focused.pid) else {
            return .unsatisfied(
                "Piccolo sees the focused window of pid \(focused.pid) at \(describe(focused.frame)), "
                    + "not of the fixture (pids \(fixture.processIDs()))")
        }
        guard framesMatch(focused.frame, entry.frame) else {
            return .unsatisfied(
                "Piccolo sees the fixture's focused window at \(describe(focused.frame)), "
                    + "wanted '\(window.id)' at \(describe(entry.frame))")
        }
        return .satisfied(())
    }

    private static func rethrowIfFatal(_ error: any Error) throws {
        if let failure = error as? AcceptanceFailure, !failure.isRetryable { throw failure }
    }
}
