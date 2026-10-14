import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

@MainActor
@Suite("Settings model: language")
struct LanguageModelTests {
    private func make(
        stored: AppLanguage = .system, running: AppLanguage = .en, system: AppLanguage = .en
    ) -> (model: SettingsModel, language: FakeLanguage, backend: InMemorySettingsBackend) {
        let backend = InMemorySettingsBackend(config: UIFixture.twoBindings())
        let language = FakeLanguage(stored: stored, running: running, system: system)
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: language) { _ in nil }
        return (model, language, backend)
    }

    // MARK: Initial state

    @Test("the model starts with the stored choice and the language the app runs in")
    func initialState() {
        let (model, language, _) = make(stored: .zhHans, running: .en)

        #expect(model.language == .zhHans)
        #expect(model.effectiveLanguage == .en)
        #expect(model.restartError == nil)
        // Looking asks for nothing.
        #expect(language.stored.isEmpty)
        #expect(language.restarts == 0)
    }

    @Test("an app that was never given a language starts on System default")
    func startsOnSystemDefault() {
        let (model, _, _) = make()
        #expect(model.language == .system)
        #expect(!model.restartRequired)
    }

    // MARK: Choosing

    @Test("a chosen language is stored through the backend and shows", arguments: AppLanguage.languages)
    func choosing(_ chosen: AppLanguage) {
        let (model, language, _) = make()

        model.setLanguage(chosen)

        #expect(language.stored == [chosen])
        #expect(language.storedLanguage == chosen)
        #expect(model.language == chosen)
    }

    @Test("System default is stored as the absence of a choice")
    func systemDefaultRemovesTheChoice() {
        let (model, language, _) = make(stored: .zhHans)

        model.setLanguage(.system)

        // The backend is asked to forget the choice; the in-memory one then holds `.system`, which
        // `LanguageDefaultsTests` shows the real one stores by removing the key.
        #expect(language.stored == [.system])
        #expect(language.storedLanguage == .system)
        #expect(model.language == .system)
    }

    @Test("the choice is not part of the config: nothing is saved to it")
    func notInTheConfig() {
        let (model, _, backend) = make()

        model.setLanguage(.ja)
        model.setLanguage(.system)

        #expect(backend.saved.isEmpty)
        #expect(model.error == nil)
    }

    @Test("choosing a language does not change the language the app runs in")
    func runningLanguageStays() {
        let (model, _, _) = make(running: .en)

        model.setLanguage(.zhHans)

        #expect(model.effectiveLanguage == .en)
    }

    // MARK: Restart

    @Test(
        "a restart is needed when the chosen language differs from the one the app runs in",
        arguments: [
            // (running, chosen, the system's language, restart needed)
            (AppLanguage.en, AppLanguage.en, AppLanguage.zhHans, false),
            (.en, .zhHans, .en, true),
            (.zhHans, .zhHans, .en, false),
            (.zhHans, .en, .zhHans, true),
            (.ja, .ptBR, .ja, true),
            // System default is the system's language: no restart on a Mac set to the language the
            // app runs in, and one on a Mac set to another.
            (.en, .system, .en, false),
            (.zhHans, .system, .zhHans, false),
            (.en, .system, .zhHans, true),
            (.zhHans, .system, .en, true),
        ] as [(AppLanguage, AppLanguage, AppLanguage, Bool)])
    func restartRequired(running: AppLanguage, chosen: AppLanguage, system: AppLanguage, required: Bool) {
        let (model, _, _) = make(running: running, system: system)

        model.setLanguage(chosen)

        #expect(model.restartRequired == required)
    }

    @Test("a restart is needed from the start when the stored choice differs from the running language")
    func restartRequiredAtStart() {
        // The app was given a language after it started, for example in System Settings.
        let (model, _, _) = make(stored: .de, running: .en)
        #expect(model.restartRequired)
    }

    @Test("going back to the language the app runs in needs no restart any more")
    func choosingBack() {
        let (model, _, _) = make(running: .en)

        model.setLanguage(.zhHans)
        #expect(model.restartRequired)
        model.setLanguage(.en)
        #expect(!model.restartRequired)
    }

    @Test("refresh reads the choice the system holds now")
    func refresh() {
        let (model, language, _) = make(running: .en)
        #expect(!model.restartRequired)

        // Somebody (System Settings, a script) gave Piccolo a language behind the model's back.
        language.storedLanguage = .fr
        #expect(model.language == .system, "the model changed before it was asked to look")
        model.refreshLanguage()

        #expect(model.language == .fr)
        #expect(model.restartRequired)
        // Refreshing stores nothing.
        #expect(language.stored.isEmpty)
    }

    // MARK: Restart now

    @Test("Restart Now asks the backend to restart, once")
    func restartNow() {
        let (model, language, _) = make()
        model.setLanguage(.ja)

        let started = model.restartNow()

        #expect(started)
        #expect(language.restarts == 1)
        #expect(model.restartError == nil)
    }

    @Test("a restart that cannot be arranged says why, leaves the choice alone and is tried again on request")
    func restartFails() {
        let (model, language, _) = make()
        model.setLanguage(.ja)
        language.restartFailure = RestartError(message: "no helper")

        #expect(!model.restartNow())

        #expect(language.restarts == 1)
        #expect(model.restartError?.contains("no helper") == true)
        #expect(model.language == .ja)
        #expect(model.restartRequired)

        // The next try works and forgets the message.
        language.restartFailure = nil
        #expect(model.restartNow())
        #expect(language.restarts == 2)
        #expect(model.restartError == nil)
    }

    @Test("choosing another language forgets the message of a failed restart, and so does clearError")
    func restartErrorIsForgotten() {
        let (model, language, _) = make()
        language.restartFailure = RestartError(message: "no helper")

        model.restartNow()
        #expect(model.restartError != nil)
        model.setLanguage(.fr)
        #expect(model.restartError == nil)

        model.restartNow()
        #expect(model.restartError != nil)
        model.clearError()
        #expect(model.restartError == nil)
    }
}
