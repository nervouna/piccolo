import Foundation

/// The running Debug Piccolo as a process.
///
/// A Piccolo process that has been the active application stops receiving the shortcuts that
/// `hotkey.simulate` posts: the key events are posted and delivered, but the system no longer
/// matches them against the process's registered hotkeys, whichever application is in front
/// afterwards and however the hotkeys are registered again. (Measured on macOS 27 with the Debug
/// builds of `main` as well; real key presses are not affected.) Only a new process fires again.
/// So a test that brings Piccolo forward, as the Settings tests must to type into its window,
/// ends by restarting it, and a test that wants a hotkey to fire after that restarts it too.
enum PiccoloProcess {
    /// Quits the running Piccolo the way `scripts/install.sh` does (SIGTERM, then SIGKILL if it
    /// does not go), launches the same bundle through LaunchServices and returns when the new
    /// process answers on its control channel. Piccolo then runs on its default config.
    static func restart(timeout: TimeInterval = 30) async throws {
        let piccolo = PiccoloClient()
        let oldPID = try piccolo.pid()
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

        try Shell.open([bundle])
        try await eventually("the restarted Piccolo to answer on its control channel", timeout: timeout) {
            do {
                let pid = try piccolo.pid()
                return pid != oldPID ? Observation.satisfied(()) : .unsatisfied("still the old process \(pid)")
            } catch {
                return .unsatisfied("\(error)")
            }
        }
    }
}
