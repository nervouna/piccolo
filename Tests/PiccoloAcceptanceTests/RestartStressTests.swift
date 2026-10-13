import Foundation
import Testing

/// Stress tests for `PiccoloProcess.restart`: they quit and launch the Debug Piccolo again and
/// again. Every round has to end in a new process that answers, with no failed `open` and a desktop
/// that can still give the front to another application.
///
/// The last point is the one that matters. LaunchServices lists a dead instance as running for a
/// moment, and an `open` in that moment fails with -600 and leaves the window server waiting for
/// the dead instance: `lsappinfo front` then reports `com.apple.loginwindow` although the screen is
/// not locked, and nothing can be activated (see ``PiccoloProcess``). The launch therefore waits for
/// LaunchServices to forget the old instance. These tests show that it does, and how often it had
/// to.
///
/// Off by default: they take minutes and restart Piccolo dozens of times. Run them with
/// `PICCOLO_STRESS=1 scripts/accept.sh restartStress` (`PICCOLO_STRESS_COUNT` sets the number of
/// rounds, 30 by default).
///
/// This is a nested suite: it inherits `.serialized`, the `PICCOLO_ACCEPTANCE` switch and the
/// running-Piccolo trait from the suite it extends.
extension DesktopAcceptanceTests {
    @Suite(
        "Restart stress",
        .enabled(if: Acceptance.isStressEnabled, "set \(Acceptance.stressEnvironmentVariable)=1 to run the stress tests")
    )
    struct RestartStress {
        private let piccolo = PiccoloClient()

        @Test("restartStress. quitting and launching Piccolo over and over always ends in a new process that answers, and the desktop can still activate another application")
        func restartStress() async throws {
            let rounds = Acceptance.stressCount
            let tallyBefore = PiccoloProcess.tally.withLock { $0 }
            var seen: Set<pid_t> = [try piccolo.pid()]
            var activatedRounds = 0

            for round in 1...rounds {
                let before = try piccolo.pid()
                let launch: PiccoloProcess.Launch
                if round.isMultiple(of: 2) {
                    // The way the Settings tests end: Piccolo has been brought forward with its
                    // Settings window open. The session ends with the restart.
                    activatedRounds += 1
                    launch = try await restartAfterActivation()
                } else {
                    launch = try await PiccoloProcess.restart()
                }

                #expect(launch.pid != before, "round \(round): the restart answered from the old process \(before)")
                #expect(seen.insert(launch.pid).inserted, "round \(round): pid \(launch.pid) was a Piccolo of an earlier round")
                #expect(try piccolo.pid() == launch.pid, "round \(round): the control channel answers from another process than the launch reported")
                #expect(try piccolo.axTrusted(), "round \(round): the new process lost its Accessibility grant")
                #expect(try !piccolo.settingsState().isOpen, "round \(round): the new process has Settings open")
                try await expectDesktopCanActivate(round: round)
                print(
                    "restart stress: round \(round)/\(rounds)\(round.isMultiple(of: 2) ? " (after activation)" : ""): pid \(before) -> \(launch.pid), \(launch.openCalls) open call(s), \(launch.failedOpens.count) failed, \(launch.registryWaits) wait(s) for LaunchServices"
                )
            }

            report("restart stress", rounds: rounds, activatedRounds: activatedRounds, since: tallyBefore)
        }

        @Test("restartStressAtOnce. launching Piccolo in the same breath as SIGTERM waits for LaunchServices, fails no open, and leaves the desktop able to activate another application")
        func restartStressAtOnce() async throws {
            let rounds = Acceptance.stressCount
            let tallyBefore = PiccoloProcess.tally.withLock { $0 }

            for round in 1...rounds {
                // Activate Piccolo as the Settings tests do, then quit and launch it at once: the
                // launch is asked for while LaunchServices still lists the instance that was quit.
                try Shell.open([try piccolo.bundlePath()])
                let start = ContinuousClock.now
                while Frontmost.state() != .application(piccoloBundleID), start.duration(to: .now) < .seconds(5) {
                    try await Task.sleep(for: .milliseconds(10))
                }
                let launch = try await PiccoloProcess.killAndLaunchAtOnce()

                #expect(launch.failedOpens.isEmpty, "round \(round): open failed with \(launch.failedOpens)")
                #expect(try piccolo.pid() == launch.pid)
                try await expectDesktopCanActivate(round: round)
                print(
                    "restart stress at once: round \(round)/\(rounds): \(launch.openCalls) open call(s), \(launch.failedOpens.count) failed, \(launch.registryWaits) wait(s) for LaunchServices"
                )
            }

            report("restart stress at once", rounds: rounds, activatedRounds: rounds, since: tallyBefore)
        }

        // MARK: Helpers

        /// Opens a fixture window and brings it to the front, without the repair `Focus.bring` makes
        /// of a desktop that has no frontmost application: a restart that leaves it so fails here.
        private func expectDesktopCanActivate(round: Int) async throws {
            try await withFixture { fixture in
                let screen = try Layout.screens()[0]
                let frame = Layout.frame(in: screen, offset: CGPoint(x: 100, y: 100), size: CGSize(width: 400, height: 300))
                let window = try fixture.open(id: "probe", frame: frame)
                do {
                    try await Focus.bring(window, of: fixture, timeout: 6, recovering: false)
                } catch {
                    throw AcceptanceFailure("round \(round): after the restart the desktop could not activate the fixture: \(error)")
                }
            }
        }

        private func report(_ name: String, rounds: Int, activatedRounds: Int, since before: PiccoloProcess.Tally) {
            let tally = PiccoloProcess.tally.withLock { $0 }
            let failed = Array(tally.failedOpens.dropFirst(before.failedOpens.count))
            print(
                "\(name): \(rounds) restarts (\(activatedRounds) after activation), \(tally.openCalls - before.openCalls) open call(s), \(failed.count) failed launch(es) retried, LaunchServices still listed the old instance at \(tally.registryWaits - before.registryWaits) look(s)"
            )
            for message in failed {
                print("\(name): retried after: \(message)")
            }
        }

        /// Brings Piccolo forward with Settings open, as a Settings test does, and restarts it as that
        /// test's session does when it ends. Returns what the restart did, from the tally.
        private func restartAfterActivation() async throws -> PiccoloProcess.Launch {
            let tallyBefore = PiccoloProcess.tally.withLock { $0 }
            try await withSettingsSession { session in
                try session.openSettings()
                // Opening a running Piccolo through LaunchServices opens Settings, but the app
                // handles that a moment after it has become frontmost. Closing the window first and
                // waiting for it to come back is how to know that nothing is still on its way when
                // the session ends and closes it.
                try piccolo.settingsClose()
                try await session.bringPiccoloForward()
                _ = try await PiccoloWindows.waitForWindow(pid: try piccolo.pid())
            }
            let tally = PiccoloProcess.tally.withLock { $0 }
            return PiccoloProcess.Launch(
                pid: try piccolo.pid(),
                openCalls: tally.openCalls - tallyBefore.openCalls,
                failedOpens: Array(tally.failedOpens.dropFirst(tallyBefore.failedOpens.count)),
                registryWaits: tally.registryWaits - tallyBefore.registryWaits)
        }
    }
}
