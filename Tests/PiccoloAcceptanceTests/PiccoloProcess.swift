import Foundation
import os

/// The running Debug Piccolo as a process.
///
/// A Piccolo process that has been the active application stops receiving the shortcuts that
/// `hotkey.simulate` posts: the key events are posted and delivered, but the system no longer
/// matches them against the process's registered hotkeys, whichever application is in front
/// afterwards and however the hotkeys are registered again. (Measured on macOS 27 with the Debug
/// builds of `main` as well. This has been observed only for the key events `hotkey.simulate`
/// posts: real key presses keep firing after Piccolo has been frontmost. The owner checked this on
/// an installed build with the Settings window in front, without a restart, and only the events of
/// `hotkey.simulate` stop.) Only a new process fires `hotkey.simulate`'s events again.
/// So a test that brings Piccolo forward, as the Settings tests must to type into its window,
/// ends by restarting it, and a test that wants a hotkey to fire after that restarts it too.
///
/// Starting Piccolo has to cope with LaunchServices. For a moment after a process has died,
/// LaunchServices still lists its instance as running (`lsappinfo find` shows it), and an `open`
/// in that moment goes to the dead instance. It fails with error -600
/// (`_LSOpenURLsWithCompletionHandler() failed`), and it does more than fail: the window server is
/// left waiting for that instance to check in, `lsappinfo front` reports `com.apple.loginwindow`
/// although the screen is not locked, and no other application can be brought to the front any
/// more (every `Focus.bring` after it times out) until some live application is activated. So
/// the launch waits until LaunchServices no longer lists the old instance, and only then runs
/// `open`. A failed `open` is still a reason to ask again and not to give up, so the launch is
/// retried until the new process answers on its control channel or the time runs out; a launch
/// that does not work in the end throws, with what was seen.
enum PiccoloProcess {
    /// Where `scripts/install.sh` puts the Debug Piccolo. Used only when no running Piccolo can
    /// say where its bundle is.
    static let installedBundlePath = "/Applications/Piccolo.app"

    /// What it took to get a Piccolo process running.
    struct Launch: Sendable {
        /// The new process.
        var pid: pid_t
        /// How many times `open` was run, the failed ones included.
        var openCalls = 0
        /// What each failed `open` said. Every one of them was followed by another attempt.
        var failedOpens: [String] = []
        /// How many looks (100 ms apart) found LaunchServices still listing the old instance, so
        /// that `open` had to wait.
        var registryWaits = 0
    }

    /// What every launch of the test run came to, for the log and for the stress test.
    struct Tally: Sendable {
        var launches = 0
        var openCalls = 0
        /// What each failed `open` said, in the order they happened.
        var failedOpens: [String] = []
        var registryWaits = 0
    }

    /// The totals since the test run began.
    static let tally = OSAllocatedUnfairLock(initialState: Tally())

    /// Quits the running Piccolo the way `scripts/install.sh` does (SIGTERM, then SIGKILL if it
    /// does not go), launches the same bundle through LaunchServices and returns when the new
    /// process answers on its control channel. Piccolo then runs on its default config.
    ///
    /// When no Piccolo answers, there is nothing to quit and the installed bundle is launched.
    @discardableResult
    static func restart(timeout: TimeInterval = 30) async throws -> Launch {
        let piccolo = PiccoloClient()
        guard let oldPID = try? piccolo.pid() else {
            return try await launch(bundle: installedBundlePath, notPID: nil, timeout: timeout)
        }
        let bundle = try piccolo.bundlePath()

        for signal in [SIGTERM, SIGKILL] {
            kill(oldPID, signal)
            let gone: Bool? = try? await eventually("Piccolo (pid \(oldPID)) to be gone", timeout: 5) {
                kill(oldPID, 0) != 0 ? Observation.satisfied(true) : .unsatisfied("still running")
            }
            if gone == true { break }
        }
        guard kill(oldPID, 0) != 0 else {
            throw AcceptanceFailure("Piccolo (pid \(oldPID)) did not quit after SIGTERM and SIGKILL")
        }
        return try await launch(bundle: bundle, notPID: oldPID, timeout: timeout)
    }

    /// Sends SIGTERM to the running Piccolo and asks for the launch in the same breath, without
    /// waiting for the process to be gone. This is the moment in which LaunchServices still lists
    /// the old instance, which `restart` only meets now and then; the stress test uses it to meet
    /// it every time. The launch must wait for LaunchServices all the same.
    @discardableResult
    static func killAndLaunchAtOnce(timeout: TimeInterval = 30) async throws -> Launch {
        let piccolo = PiccoloClient()
        let oldPID = try piccolo.pid()
        let bundle = try piccolo.bundlePath()
        kill(oldPID, SIGTERM)
        return try await launch(bundle: bundle, notPID: oldPID, timeout: timeout)
    }

    /// Makes sure a Piccolo answers on its control channel: nothing happens when one does, and the
    /// installed bundle is launched when none does. Answers `nil` in the first case.
    ///
    /// Every acceptance test starts with it (see ``PiccoloRunningTrait``), so that one test that
    /// left Piccolo down fails by itself and does not take the tests after it along.
    @discardableResult
    static func ensureRunning(timeout: TimeInterval = 30) async throws -> Launch? {
        if (try? PiccoloClient().pid()) != nil { return nil }
        return try await launch(bundle: installedBundlePath, notPID: nil, timeout: timeout)
    }

    // MARK: Launching

    /// How long a successful `open` is given to produce a process that answers before it is
    /// believed lost and `open` is run again. Asking again while the app does start would only
    /// reopen it (and so open its Settings window), which is why this is long.
    private static let launchGrace: TimeInterval = 10

    /// The pause between a failed `open` and the next one.
    private static let retryInterval: TimeInterval = 0.25

    /// Runs `open` on `bundle` until a Piccolo other than `notPID` answers on its control channel.
    /// It does not run while LaunchServices lists an instance of Piccolo that has not answered
    /// yet (see above); a failed `open` is remembered and tried again; `timeout` ends the attempts.
    private static func launch(bundle: String, notPID: pid_t?, timeout: TimeInterval) async throws -> Launch {
        let piccolo = PiccoloClient()
        let clock = ContinuousClock()
        var launch = Launch(pid: 0)
        var lastAttempt: ContinuousClock.Instant?
        var lastOpenSucceeded = false
        var lastFailure: String?
        defer {
            let result = launch
            tally.withLock {
                $0.launches += 1
                $0.openCalls += result.openCalls
                $0.failedOpens += result.failedOpens
                $0.registryWaits += result.registryWaits
            }
        }

        let pid = try await eventually(
            "Piccolo (\(bundle)) to be launched and to answer on its control channel", timeout: timeout,
            interval: 0.1
        ) {
            let seen: String
            do {
                let pid = try piccolo.pid()
                if pid != notPID { return Observation.satisfied(pid) }
                seen = "the control channel still answers from the old process \(pid)"
            } catch {
                seen = "\(error)"
            }

            let sinceAttempt = lastAttempt.map { $0.duration(to: clock.now) } ?? .seconds(1_000_000)
            let wait = lastOpenSucceeded ? launchGrace : retryInterval
            if sinceAttempt >= .seconds(wait) {
                if !lastOpenSucceeded {
                    let listed = LaunchServicesRegistry.instances(of: piccoloBundleID)
                    if !listed.isEmpty {
                        launch.registryWaits += 1
                        return .unsatisfied(
                            "LaunchServices still lists \(piccoloBundleID) as running (\(listed.joined(separator: ", "))) "
                                + "and the control channel says: \(seen); not opening it until LaunchServices has forgotten it "
                                + "(\(launch.openCalls) open call(s), \(launch.failedOpens.count) failed)")
                    }
                }
                lastAttempt = clock.now
                launch.openCalls += 1
                do {
                    try Shell.open([bundle])
                    lastOpenSucceeded = true
                } catch {
                    lastOpenSucceeded = false
                    lastFailure = "\(error)"
                    launch.failedOpens.append("\(error)")
                    print("PiccoloProcess: launch attempt \(launch.openCalls) failed, trying again: \(error)")
                }
            }
            let opened =
                lastOpenSucceeded
                ? "the last open succeeded but the control channel is silent: \(seen)"
                : "the last open failed: \(lastFailure ?? "no launch attempted yet")"
            return .unsatisfied("\(opened) (\(launch.openCalls) open call(s), \(launch.failedOpens.count) failed)")
        }
        launch.pid = pid
        return launch
    }
}
