import Foundation
import PiccoloControl
import PiccoloCore
import Testing

/// Acceptance tests for the language of the interface: the installed Debug Piccolo reports the
/// choice and the language it runs in, shows its texts in the language it was started in, and
/// restarts itself ("Restart Now") into a newly chosen one.
///
/// The language is the one thing in Piccolo that outlives the test run if a test leaves it changed
/// (`AppleLanguages` in Piccolo's defaults domain), so every test here runs inside
/// ``withLanguageRestored(_:)``, which puts the choice back, and Piccolo with it, also when the test
/// fails. The other acceptance tests do not touch the language: they compare texts with the same
/// text in the language Piccolo reports (see ``InterfaceTexts``).
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends.
extension DesktopAcceptanceTests {
    @Suite("Language")
    struct Language {
        private let piccolo = PiccoloClient()

        /// The language that is not the one Piccolo runs in now, so that choosing it needs a restart
        /// whatever the language of the machine is. Simplified Chinese unless Piccolo runs in it.
        private static func otherThan(_ language: String) -> String {
            language == "zh-Hans" ? "en" : "zh-Hans"
        }

        // MARK: 1. The state

        @Test("language 1. the state reports the choice, the language in effect and whether a restart is needed; the running texts keep their language")
        func stateFields() async throws {
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)))
            try await withLanguageRestored { original in
                try await withSettingsSession([leftHalf]) { _ in
                    let start = try piccolo.settingsState()
                    #expect(InterfaceLanguageCodes.codes.contains(start.effectiveLanguage), "effectiveLanguage is \"\(start.effectiveLanguage)\"")
                    #expect(start.language == "system" || InterfaceLanguageCodes.codes.contains(start.language), "language is \"\(start.language)\"")
                    // Piccolo is found in the state a person leaves it in: it runs in the language its choice gives.
                    let summaryBefore = try #require(start.bindings.first?.summary)

                    // Anything but "system" or a code is refused, and nothing changes.
                    let message = try piccolo.settingsSetLanguageExpectingRefusal("klingon")
                    #expect(message.contains("zh-Hans") && message.contains("system"), "the message is \"\(message)\"")
                    #expect(try piccolo.settingsState().language == original.language)

                    // A language other than the one in effect needs a restart, and changes nothing now.
                    let target = Self.otherThan(start.effectiveLanguage)
                    let chosen = try piccolo.settingsSetLanguage(target)
                    #expect(chosen.language == target, "the choice is \"\(chosen.language)\", expected \"\(target)\"")
                    #expect(chosen.effectiveLanguage == start.effectiveLanguage, "the running Piccolo changed its language without a restart")
                    #expect(chosen.restartRequired, "choosing \(target) while Piccolo runs in \(start.effectiveLanguage) needs a restart")
                    #expect(chosen.bindings.first?.summary == summaryBefore, "the summaries changed language without a restart")
                    #expect(chosen.error == nil)

                    // Going back to the language in effect needs none.
                    let back = try piccolo.settingsSetLanguage(start.effectiveLanguage)
                    #expect(back.language == start.effectiveLanguage)
                    #expect(!back.restartRequired, "choosing the language Piccolo runs in needs no restart")

                    // System default: a restart is needed only when the system's language is another one.
                    let system = try piccolo.settingsSetLanguage("system")
                    #expect(system.language == "system")
                    print("language: System default gives restartRequired \(system.restartRequired) while Piccolo runs in \(system.effectiveLanguage)")
                }
            }
        }

        // MARK: 2. Chinese and English

        @Test("language 2. after a restart Piccolo runs in Simplified Chinese and shows Chinese texts, then in English, and the choice is put back")
        func chineseAndEnglish() async throws {
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)))
            try await withLanguageRestored { _ in
                try await withSettingsSession([leftHalf]) { session in
                    let english = try InterfaceTexts(code: "en")
                    let chinese = try InterfaceTexts(code: "zh-Hans")
                    #expect(english.summary(of: leftHalf.action) != chinese.summary(of: leftHalf.action))

                    // Simplified Chinese.
                    try piccolo.settingsSetLanguage("zh-Hans")
                    try await session.restartPiccolo()

                    let zh = try piccolo.settingsState()
                    #expect(zh.effectiveLanguage == "zh-Hans", "after the restart Piccolo runs in \"\(zh.effectiveLanguage)\"")
                    #expect(zh.language == "zh-Hans")
                    #expect(!zh.restartRequired)
                    let zhSummary = try #require(zh.bindings.first?.summary, "the state lists no binding")
                    #expect(zhSummary == chinese.summary(of: leftHalf.action), "the summary is \"\(zhSummary)\"")
                    #expect(zhSummary != english.summary(of: leftHalf.action), "the summary is the English one: \"\(zhSummary)\"")
                    #expect(Self.containsChinese(zhSummary), "the summary \"\(zhSummary)\" has no Chinese characters")

                    // English.
                    try piccolo.settingsSetLanguage("en")
                    let chosen = try piccolo.settingsState()
                    #expect(chosen.restartRequired, "choosing English while Piccolo runs in Chinese needs a restart")
                    #expect(chosen.bindings.first?.summary == zhSummary, "the summary changed language without a restart")
                    try await session.restartPiccolo()

                    let en = try piccolo.settingsState()
                    #expect(en.effectiveLanguage == "en", "after the restart Piccolo runs in \"\(en.effectiveLanguage)\"")
                    #expect(en.language == "en")
                    #expect(!en.restartRequired)
                    let enSummary = try #require(en.bindings.first?.summary, "the state lists no binding")
                    #expect(enSummary == english.summary(of: leftHalf.action), "the summary is \"\(enSummary)\"")
                    #expect(enSummary == "Left Half")
                }
            }
        }

        // MARK: 3. Restart Now

        @Test("language 3. Restart Now answers, quits, and starts Piccolo again within 10 s in the chosen language, with an application frontmost")
        func restartNow() async throws {
            try await withLanguageRestored { original in
                let target = Self.otherThan(original.effectiveLanguage)
                let oldPID = try piccolo.pid()
                let chosen = try piccolo.settingsSetLanguage(target)
                #expect(chosen.restartRequired)

                // The answer comes from the old process, before it quits.
                let answer = try piccolo.settingsRestartNow()
                #expect(answer.language == target)
                let asked = ContinuousClock.now

                // A new process answers on the control channel.
                let newPID = try await waitForNewProcess(replacing: oldPID)
                print("language: Piccolo answered again \(asked.duration(to: .now)) after Restart Now (pid \(oldPID) -> \(newPID))")

                let state = try piccolo.settingsState()
                #expect(state.effectiveLanguage == target, "the new Piccolo runs in \"\(state.effectiveLanguage)\", expected \"\(target)\"")
                #expect(state.language == target)
                #expect(!state.restartRequired)
                #expect(state.restartError == nil)

                // The restart did not leave the desktop without a frontmost application.
                let front = Frontmost.state()
                if case .application(let id) = front {
                    print("language: after Restart Now the frontmost application is \(id)")
                } else {
                    Issue.record("after Restart Now: \(Frontmost.explain(front, wanted: "any application"))")
                }
                #expect(Frontmost.bundleID() != Frontmost.loginWindow, "lsappinfo front reports \(Frontmost.loginWindow) after Restart Now")

                // The helper that started Piccolo has finished.
                try await waitForRestartHelperToExit(after: oldPID)
            }
        }

        // MARK: Support

        /// Waits up to 10 s for a Piccolo other than `oldPID` to answer on the control channel.
        private func waitForNewProcess(replacing oldPID: pid_t) async throws -> pid_t {
            try await eventually(
                "a new Piccolo (not \(oldPID)) to answer on the control channel after Restart Now",
                timeout: 10, interval: 0.1
            ) {
                do {
                    let pid = try piccolo.pid()
                    return pid != oldPID ? .satisfied(pid) : .unsatisfied("the old process \(pid) still answers")
                } catch {
                    return .unsatisfied("\(error)")
                }
            }
        }

        /// Waits until no restart helper is left running: it is a process of its own, and one that
        /// stayed would be a leftover.
        private func waitForRestartHelperToExit(after oldPID: pid_t) async throws {
            try await eventually("the restart helper that replaced pid \(oldPID) to have exited", timeout: 10, interval: 0.2) {
                let helpers = try Shell.run("/usr/bin/pgrep", ["-f", "piccolo-restart"])
                if helpers.status == 1 { return Observation<Void>.satisfied(()) }
                let found = helpers.output.trimmingCharacters(in: .whitespacesAndNewlines)
                return .unsatisfied("pgrep still finds: \(found)")
            }
        }

        /// Whether `text` holds a CJK ideograph.
        private static func containsChinese(_ text: String) -> Bool {
            text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        }

        /// Runs `body` and afterwards puts the language back, whether `body` succeeded or not: the
        /// choice is what it was (so is the language Piccolo runs in, which takes a restart when
        /// `body` changed it, so that the tests after this one find the Piccolo they expect).
        /// A failure to put it back is its own failure: after a failed `body` it is recorded as a second
        /// issue of the test, next to the error that is thrown.
        private func withLanguageRestored<Result>(
            _ body: (_ original: SettingsState) async throws -> Result
        ) async throws -> Result {
            let original = try piccolo.settingsState()
            print("language: the choice before the test is \(original.language), Piccolo runs in \(original.effectiveLanguage)")
            let result: Result
            do {
                result = try await body(original)
            } catch {
                do {
                    try await restore(original)
                } catch {
                    Issue.record("putting the language back to \(original.language) after the failed test failed as well: \(error)")
                }
                throw error
            }
            try await restore(original)
            return result
        }

        /// Stores the choice found at the start and restarts Piccolo when it no longer runs in the
        /// language it ran in then.
        private func restore(_ original: SettingsState) async throws {
            var now = try piccolo.settingsState()
            if now.language != original.language {
                now = try piccolo.settingsSetLanguage(original.language)
            }
            if now.effectiveLanguage != original.effectiveLanguage {
                try await PiccoloProcess.restart()
                now = try piccolo.settingsState()
            }
            guard now.language == original.language, now.effectiveLanguage == original.effectiveLanguage else {
                throw AcceptanceFailure(
                    "the language was \"\(original.language)\" (running in \"\(original.effectiveLanguage)\") before the test; it is \"\(now.language)\" (running in \"\(now.effectiveLanguage)\") after putting it back. Check `defaults read io.damao.piccolo AppleLanguages`.",
                    isRetryable: false)
            }
            print("language: put the choice back to \(original.language) (Piccolo runs in \(original.effectiveLanguage))")
        }
    }
}

/// A stress test for Restart Now: it restarts Piccolo through `settings.restartNow` again and again,
/// half of the rounds with Piccolo the frontmost application and its Settings window open, which is
/// where a person clicks the button. Every round has to end in a new process that answers within
/// 10 s, with a desktop that can still give the front to another application and no helper left
/// behind (see ``RestartStress`` for why that last point about the desktop matters).
///
/// Off by default: it restarts Piccolo dozens of times. Run it with
/// `PICCOLO_STRESS=1 scripts/accept.sh restartNowStress` (`PICCOLO_STRESS_COUNT` sets the number of
/// rounds, 30 by default).
extension DesktopAcceptanceTests {
    @Suite(
        "Restart Now stress",
        .enabled(if: Acceptance.isStressEnabled, "set \(Acceptance.stressEnvironmentVariable)=1 to run the stress tests")
    )
    struct RestartNowStress {
        private let piccolo = PiccoloClient()

        @Test("restartNowStress. Restart Now over and over always ends in a new process that answers, and the desktop can still activate another application")
        func restartNowStress() async throws {
            let rounds = Acceptance.stressCount
            var slowest = Duration.zero
            for round in 1...rounds {
                let activated = round.isMultiple(of: 2)
                if activated {
                    try await withSettingsSession { session in
                        try session.openSettings()
                        // As in RestartStress: closing the window first and waiting for it to come
                        // back is how to know that nothing is still on its way.
                        try piccolo.settingsClose()
                        try await session.bringPiccoloForward()
                        _ = try await PiccoloWindows.waitForWindow(pid: try piccolo.pid())
                        slowest = max(slowest, try await restartNow(round: round, of: rounds, activated: true))
                    }
                } else {
                    slowest = max(slowest, try await restartNow(round: round, of: rounds, activated: false))
                }
            }
            print("restart now stress: \(rounds) restarts, the slowest took \(slowest)")
        }

        /// Asks for the restart and checks the new process and the desktop. Answers how long the new
        /// process took to answer.
        private func restartNow(round: Int, of rounds: Int, activated: Bool) async throws -> Duration {
            let oldPID = try piccolo.pid()
            try piccolo.settingsRestartNow()
            let asked = ContinuousClock.now
            let newPID = try await eventually(
                "round \(round): a new Piccolo (not \(oldPID)) to answer on the control channel after Restart Now",
                timeout: 10, interval: 0.1
            ) {
                do {
                    let pid = try piccolo.pid()
                    return pid != oldPID ? .satisfied(pid) : .unsatisfied("the old process \(pid) still answers")
                } catch {
                    return .unsatisfied("\(error)")
                }
            }
            let took = asked.duration(to: .now)
            let front = Frontmost.state()
            guard case .application = front else {
                throw AcceptanceFailure("round \(round): after Restart Now \(Frontmost.explain(front, wanted: "any application"))")
            }
            try await expectDesktopCanActivate(round: round)
            print("restart now stress: round \(round)/\(rounds)\(activated ? " (Settings frontmost)" : ""): pid \(oldPID) -> \(newPID) in \(took)")
            return took
        }

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
                    throw AcceptanceFailure("round \(round): after Restart Now the desktop could not activate the fixture: \(error)")
                }
            }
        }
    }
}

/// The codes of the interface languages, as `settings.state` writes them.
private enum InterfaceLanguageCodes {
    static let codes = ["en", "zh-Hans", "zh-Hant", "ja", "fr", "es", "pt-BR", "de"]
}
