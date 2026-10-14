import AppKit
import PiccoloSystem
import SwiftUI

/// The menu of the menu bar icon. Its texts are looked up in the app's own string catalog with
/// `String(localized:)` and shown as they are, like those of the Settings window (see
/// `Text(localized:)` in PiccoloUI): that way every text of Piccolo is looked up the same way,
/// in the language the app was started in.
struct MenuContent: View {
    let accessibility: AccessibilityStatus
    let config: ConfigController

    var body: some View {
        if accessibility.isTrusted {
            Label(String(localized: "Accessibility: Granted"), systemImage: "checkmark.circle")
        } else {
            Label(String(localized: "Accessibility: Not granted"), systemImage: "exclamationmark.triangle")
            Button(String(localized: "Open Accessibility Settings…")) {
                AccessibilityPermission().openSettings()
            }
        }

        Divider()

        Label(
            Self.summary(of: config.status),
            systemImage: config.status.issues.isEmpty ? "keyboard" : "exclamationmark.triangle")
        Button(String(localized: "Reload Config")) {
            config.reload()
        }
        Button(String(localized: "Reveal Config in Finder")) {
            config.revealInFinder()
        }

        Divider()

        Button(String(localized: "Settings…")) {
            SettingsController.shared.show()
        }
        .keyboardShortcut(",")

        Button(String(localized: "Quit Piccolo")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// The line for the menu: "3 shortcuts active", or "3 shortcuts active, 2 config problems", in the
    /// language of the app. `ShortcutManager.Status.summary` says the same in English, for the log;
    /// the menu builds its own so that it can be translated.
    ///
    /// The plural rules are those of the language the app runs in, not of the region the Mac is set to,
    /// which can differ (an English app on a Mac set to China would use Chinese rules otherwise).
    static func summary(of status: ShortcutManager.Status) -> String {
        let locale = Locale(identifier: SystemLanguageBackend.launchLanguage.rawValue)
        let active = String(localized: "\(status.registered.count) shortcuts active", locale: locale)
        guard !status.issues.isEmpty else { return active }
        let problems = String(localized: "\(status.issues.count) config problems", locale: locale)
        return String(localized: "\(active), \(problems)", locale: locale)
    }
}
