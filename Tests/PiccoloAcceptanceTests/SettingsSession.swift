import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// The bundle ID of the Debug Piccolo, as LaunchServices reports it.
let piccoloBundleID = "io.damao.piccolo"

/// The windows Piccolo shows, seen from the window server (CGWindowList) and not from Piccolo.
enum PiccoloWindows {
    /// The frames of the windows `pid` has on screen that are windows in the usual sense: layer
    /// 0 and not tiny. The menu bar item is a window of Piccolo too, on another layer.
    static func onScreen(pid: pid_t) -> [CGRect] {
        guard
            let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard (entry[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                (entry[kCGWindowLayer as String] as? Int) == 0,
                let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                frame.width >= 300, frame.height >= 300
            else { return nil }
            return frame
        }
    }

    /// Waits until Piccolo has a window on screen and returns its frame.
    static func waitForWindow(pid: pid_t, timeout: TimeInterval = 3) async throws -> CGRect {
        try await eventually("a window owned by Piccolo (pid \(pid)) on screen", timeout: timeout) {
            if let frame = onScreen(pid: pid).first { return .satisfied(frame) }
            return .unsatisfied("Piccolo has no window on screen")
        }
    }

    /// Waits until Piccolo has no window on screen.
    static func waitForNoWindow(pid: pid_t, timeout: TimeInterval = 3) async throws {
        try await eventually("Piccolo (pid \(pid)) to have no window on screen", timeout: timeout) {
            let frames = onScreen(pid: pid)
            if frames.isEmpty { return Observation<Void>.satisfied(()) }
            return .unsatisfied("windows at \(frames.map(describe))")
        }
    }
}

/// One test's temporary config, loaded into Piccolo, and the means to drive Settings on it.
///
/// Whatever brings Piccolo forward (`openSettings`, `bringPiccoloForward`, `record`) marks the
/// session: Piccolo has then been the active application and has to be restarted afterwards for
/// `hotkey.simulate` to work (see ``PiccoloProcess``). `withSettingsSession` does that when the
/// body is done.
final class SettingsSession {
    let config: ConfigDirectory
    /// The file Piccolo has loaded.
    let url: URL
    let piccolo = PiccoloClient()
    /// Whether Piccolo may have been the active application since it was last started.
    private(set) var needsFreshProcess = false

    init(config: ConfigDirectory, url: URL) {
        self.config = config
        self.url = url
    }

    /// Declares that something other than the session's own methods brought Piccolo forward.
    func markPiccoloActivated() {
        needsFreshProcess = true
    }

    /// `settings.open`, which also activates the app when the system lets it.
    @discardableResult
    func openSettings() throws -> SettingsState {
        needsFreshProcess = true
        return try piccolo.settingsOpen()
    }

    /// Quits Piccolo and starts it again (see ``PiccoloProcess``), then loads the session's
    /// config into the new process. Settings is closed and nothing is recording afterwards.
    func restartPiccolo() async throws {
        try await PiccoloProcess.restart()
        needsFreshProcess = false
        try piccolo.loadConfig(at: url)
    }

    /// Restarts Piccolo if the session brought it forward, so that the tests after it find a
    /// Piccolo that fires simulated hotkeys.
    func restartIfActivated() async throws {
        guard needsFreshProcess else { return }
        try await PiccoloProcess.restart()
        needsFreshProcess = false
    }

    /// The restart that ends a session whose test has failed already. Its own failure is recorded
    /// as an issue of the test, next to the error that is about to be thrown: neither hides the
    /// other.
    func restartAfterFailure() async {
        do {
            try await restartIfActivated()
        } catch {
            Issue.record("restarting Piccolo after the failed test failed as well: \(error)")
        }
    }

    // MARK: The files

    /// The bindings in the file on disk.
    func fileBindings() throws -> [KeyBinding] {
        try ConfigStore(url: url).load().config.bindings
    }

    /// The whole config in the file on disk.
    func fileConfig() throws -> Config {
        try ConfigStore(url: url).load().config
    }

    /// The bytes of the file on disk.
    func fileBytes() throws -> Data {
        try Data(contentsOf: url)
    }

    /// The IDs of the bindings Piccolo has registered hotkeys for.
    func registeredIDs() throws -> [UUID] {
        try piccolo.configStatus().registered.map(\.id)
    }

    // MARK: Bringing Piccolo forward

    /// Hands Piccolo to LaunchServices (`open` on the running bundle, which also makes the
    /// system allow the activation) until it is the frontmost application, and returns when it
    /// is. Opening a running app opens its Settings window, which is what the caller needs.
    func bringPiccoloForward(timeout: TimeInterval = 15) async throws {
        needsFreshProcess = true
        let bundle = try piccolo.bundlePath()
        let clock = ContinuousClock()
        let start = clock.now
        var lastAttempt: ContinuousClock.Instant?
        var lastSeen = "nothing observed"
        var attempts = 0
        while true {
            if lastAttempt.map({ $0.duration(to: clock.now) >= .seconds(1.5) }) ?? true {
                lastAttempt = clock.now
                attempts += 1
                try Shell.open([bundle])
            }
            let front = Frontmost.bundleID()
            if front == piccoloBundleID {
                // For the log: how often LaunchServices had to be asked.
                print("bringPiccoloForward: frontmost after \(attempts) open call(s), \(start.duration(to: clock.now))")
                return
            }
            lastSeen = "frontmost app is \(front ?? "unknown"), wanted \(piccoloBundleID)"
            if start.duration(to: clock.now) >= .seconds(timeout) {
                throw AcceptanceFailure(
                    "Piccolo did not become the frontmost application within \(Int(timeout)) s after being opened through LaunchServices; last observed: \(lastSeen)"
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// `settings.record` once Piccolo is frontmost with the Settings window key. A refusal for
    /// that reason leaves nothing behind (no key was posted), so it is tried again, handing
    /// Piccolo to LaunchServices in between, until `timeout`; any other failure ends the wait.
    func record(_ id: UUID, _ shortcut: Shortcut, timeout: TimeInterval = 20) async throws -> SettingsState {
        try await bringPiccoloForward()
        let piccolo = self.piccolo
        return try await eventually(
            "settings.record of \(shortcut) on \(id) to be accepted", timeout: timeout, interval: 0.25
        ) {
            let response = try piccolo.settingsRecordRaw(id, shortcut)
            if response.ok {
                return .satisfied(try piccolo.decodeState(response.result ?? .null, of: "settings.record"))
            }
            let message = response.error ?? "no reason given"
            guard message.contains("frontmost") || message.contains("key window") else {
                throw AcceptanceFailure("settings.record was refused: \(message)")
            }
            // Not in front yet: try to bring it forward again, then look again.
            if let bundle = try? piccolo.bundlePath() { try? Shell.open([bundle]) }
            return .unsatisfied(message)
        }
    }

    // MARK: Cleaning up

    /// Ends a recording and closes Settings, whatever state they are in. Never throws, so that
    /// it can run after a failure.
    func cleanUp() {
        _ = try? piccolo.settingsCancelRecording()
        _ = try? piccolo.settingsClose()
    }
}

/// Runs `body` with a temporary config holding `bindings`, loaded into Piccolo, and Settings
/// closed. Afterwards, whether `body` succeeded or not, a recording is cancelled, Settings is
/// closed (and checked to be gone), Piccolo is restarted if it was brought forward (so that the
/// tests that follow can fire simulated hotkeys, see ``PiccoloProcess``), and Piccolo is back
/// on its default config with the default config folder untouched (`withConfigDirectory`
/// checks both).
///
/// Every edit through Settings is written to the file Piccolo has loaded, so nothing here may
/// run an edit before the temporary config is loaded: this is what makes sure of it.
///
/// - Parameter subfolder: When set, the config file is `subfolder/config.json` inside the
///   temporary directory, and neither exists yet (a missing file loads as an empty config).
func withSettingsSession<Result>(
    _ bindings: [KeyBinding] = [],
    inNewSubfolder subfolder: String? = nil,
    _ body: (SettingsSession) async throws -> Result
) async throws -> Result {
    try await withConfigDirectory { config in
        let url: URL
        if let subfolder {
            url = config.url.appending(path: subfolder).appending(path: "config.json")
        } else {
            url = try config.write(bindings)
        }
        let piccolo = PiccoloClient()
        // Settings left open by an earlier run would show the wrong config for a moment.
        _ = try? piccolo.settingsClose()
        let loaded = try piccolo.loadConfig(at: url)
        guard loaded.path == url.path else {
            throw AcceptanceFailure("config.load reported the path \(loaded.path), expected \(url.path)")
        }

        let session = SettingsSession(config: config, url: url)
        let result: Result
        do {
            result = try await body(session)
        } catch {
            session.cleanUp()
            await session.restartAfterFailure()
            throw error
        }
        session.cleanUp()
        let state = try piccolo.settingsState()
        guard !state.isOpen, state.recordingBindingID == nil else {
            await session.restartAfterFailure()
            throw AcceptanceFailure(
                "after the test Settings is still open or recording (isOpen: \(state.isOpen), recording: \(String(describing: state.recordingBindingID)))"
            )
        }
        try await PiccoloWindows.waitForNoWindow(pid: try piccolo.pid())
        // A failed restart fails the test with its own reason: it is not swallowed.
        try await session.restartIfActivated()
        return result
    }
}
