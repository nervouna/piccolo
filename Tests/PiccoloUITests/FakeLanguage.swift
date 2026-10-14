@testable import PiccoloUI

/// The language settings of the system, in memory, recording what the model asks of them.
@MainActor
final class FakeLanguage: LanguageBackend {
    /// What is stored for the next launch.
    var storedLanguage: AppLanguage
    /// What the running app shows.
    var runningLanguage: AppLanguage
    /// What a launch with no language of its own would show.
    var systemLanguage: AppLanguage
    /// When set, `restart` throws this and the app keeps running.
    var restartFailure: RestartError?

    /// Every choice that was stored, in order.
    private(set) var stored: [AppLanguage] = []
    /// How many times a restart was asked for, failed ones included.
    private(set) var restarts = 0

    init(
        stored: AppLanguage = .system, running: AppLanguage = .en, system: AppLanguage = .en
    ) {
        storedLanguage = stored
        runningLanguage = running
        systemLanguage = system
    }

    func store(_ language: AppLanguage) {
        stored.append(language)
        storedLanguage = language
    }

    func restart() throws(RestartError) {
        restarts += 1
        if let restartFailure {
            throw restartFailure
        }
    }
}
