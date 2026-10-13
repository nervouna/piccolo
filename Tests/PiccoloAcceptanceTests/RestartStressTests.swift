import Foundation
import Testing

/// A stress test for `PiccoloProcess.restart`: it quits and launches the Debug Piccolo again and
/// again, and every round has to end in a new process that answers. LaunchServices answers a launch
/// right after a quit with an error (-600) every now and then, and `restart` has to ask again; this
/// is how that is shown to work, and how often it was needed.
///
/// Off by default: it takes minutes and restarts Piccolo dozens of times. Run it with
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

        @Test("restartStress. quitting and launching Piccolo over and over always ends in a new process that answers")
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
                print(
                    "restart stress: round \(round)/\(rounds)\(round.isMultiple(of: 2) ? " (after activation)" : ""): pid \(before) -> \(launch.pid), \(launch.openCalls) open call(s), \(launch.failedOpens.count) failed"
                )
            }

            let tally = PiccoloProcess.tally.withLock { $0 }
            let failed = Array(tally.failedOpens.dropFirst(tallyBefore.failedOpens.count))
            print(
                "restart stress: \(rounds) restarts (\(activatedRounds) after activation), \(tally.openCalls - tallyBefore.openCalls) open call(s), \(failed.count) failed launch(es) retried"
            )
            for message in failed {
                print("restart stress: retried after: \(message)")
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
                failedOpens: Array(tally.failedOpens.dropFirst(tallyBefore.failedOpens.count)))
        }
    }
}
