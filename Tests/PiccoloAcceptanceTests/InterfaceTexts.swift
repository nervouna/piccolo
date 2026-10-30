import Foundation
import PiccoloCore

@testable import PiccoloUI

/// The texts Piccolo shows, in the language the running Piccolo shows them in.
///
/// The acceptance tests must pass whatever the language of the machine is, and Piccolo follows it
/// (Simplified Chinese on the owner's Mac). A test that compares a text it reads from Piccolo, such
/// as the summary of an action or the message of a rejected edit, therefore does not compare it with
/// an English literal: it asks for the same text in the language Piccolo reports as its own
/// (`settings.state.effectiveLanguage`), from the same string catalog and the same code Piccolo
/// uses. Piccolo is not switched to English for the tests, so they never touch the language
/// choice of the person who runs them (only the language tests do, and they put it back).
///
/// What this checks is that the texts reach the control channel and the window in the language in
/// effect; that the translations are right and complete is for the unit tests of PiccoloUI.
struct InterfaceTexts {
    /// The language Piccolo runs in, never System default.
    let language: AppLanguage
    private let bundle: Bundle

    /// The language `code` names (`"zh-Hans"`), as `settings.state` reports it.
    init(code: String) throws {
        guard let language = AppLanguage(rawValue: code), language != .system else {
            throw AcceptanceFailure("Piccolo reports the effective language \"\(code)\", which is none of the eight")
        }
        guard let bundle = language.textBundle else {
            throw AcceptanceFailure("PiccoloUI has no texts for the language \"\(code)\"")
        }
        self.language = language
        self.bundle = bundle
    }

    /// The texts in the language the running Piccolo reports.
    static func current(_ piccolo: PiccoloClient) throws -> InterfaceTexts {
        try InterfaceTexts(code: try piccolo.settingsState().effectiveLanguage)
    }

    /// The summary line of an action, as the list of bindings shows it ("Left Half").
    func summary(of action: Action) -> String {
        ActionSummary.text(for: action, bundle: bundle)
    }

    /// The sentence for a rejected edit.
    func message(for error: ValidationError) -> String {
        SettingsMessages.describe(error, bundle: bundle)
    }

    /// The text of a failure notice.
    func notice(_ notice: FailureNotice) -> String {
        FailureNoticeText.text(for: notice, bundle: bundle)
    }
}
