import AppKit
import Foundation
import PiccoloUI

/// The Settings model's view of the language of the interface: the `AppleLanguages` list of
/// Piccolo's own defaults domain (see ``LanguageDefaults``), which macOS reads when the app starts.
///
/// A change reaches the running app at the next launch only: ``runningLanguage`` is read when the
/// app starts and does not change.
@MainActor
final class SystemLanguageBackend: LanguageBackend {
    /// The language the app started in. Read once, as early as possible (`AppDelegate` touches it at
    /// launch), because the text lookups settle on a language the first time they run.
    static let launchLanguage: AppLanguage = {
        for localization in Bundle.main.preferredLocalizations {
            if let language = AppLanguage.best(for: [localization]) {
                return language
            }
        }
        return .fallback
    }()

    private let stored: LanguageDefaults
    private let bundleID: String

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "io.damao.piccolo") {
        self.bundleID = bundleID
        stored = LanguageDefaults(defaults: .standard, domain: bundleID)
    }

    var storedLanguage: AppLanguage {
        stored.stored
    }

    func store(_ language: AppLanguage) {
        stored.store(language)
    }

    var runningLanguage: AppLanguage {
        Self.launchLanguage
    }

    var systemLanguage: AppLanguage {
        // The system's own list, not `Locale.preferredLanguages`: that one follows the app's list.
        let list =
            CFPreferencesCopyValue(
                LanguageDefaults.key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost) as? [String]
        return AppLanguage.best(for: list ?? []) ?? .fallback
    }

    func restart() throws(RestartError) {
        try AppRestart.startHelper(
            processID: ProcessInfo.processInfo.processIdentifier,
            bundlePath: Bundle.main.bundleURL.path,
            bundleID: bundleID)
        NSApplication.shared.terminate(nil)
    }
}
