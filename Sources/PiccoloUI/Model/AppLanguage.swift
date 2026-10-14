import Foundation

/// A choice in the language picker of the General tab: the system's language, or one of the
/// eight languages the interface is available in.
///
/// The raw value is what the debug control channel calls the choice: `"system"`, or the code
/// macOS knows the language by, which is also the name of its `.lproj` folder in the app bundle.
public enum AppLanguage: String, CaseIterable, Sendable {
    /// Follow the system's language list, as an app that was never given a language of its own does.
    case system
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja
    case fr
    case es
    case ptBR = "pt-BR"
    case de

    /// The eight languages, without ``system``, in the order the picker lists them.
    public static let languages: [AppLanguage] = allCases.filter { $0 != .system }

    /// The language the app falls back to, and the one its texts are written in.
    public static let fallback = AppLanguage.en

    /// The code of the language (`"zh-Hans"`), or `nil` for ``system``.
    public var code: String? {
        self == .system ? nil : rawValue
    }

    /// The name of the language in the language itself, as the picker shows it. `nil` for
    /// ``system``, which is named by a text that is translated.
    public var nativeName: String? {
        switch self {
        case .system: nil
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .ja: "日本語"
        case .fr: "Français"
        case .es: "Español"
        case .ptBR: "Português (Brasil)"
        case .de: "Deutsch"
        }
    }

    /// The bundle with PiccoloUI's texts, which answers in the language of the running app. It is
    /// the default of the `bundle` parameter of the functions that produce texts; a caller that wants
    /// a given language passes that language's ``textBundle`` instead.
    public static var currentTextBundle: Bundle { .module }

    /// The bundle that holds the interface texts in this language: the `.lproj` folder of
    /// PiccoloUI's resources. Looking a text up in it gives that language whatever the language of the
    /// running app is, which is how the unit tests and the acceptance tests read a translation.
    /// For ``system`` it is the resource bundle itself, whose texts follow the app's language. `nil`
    /// when the folder is missing.
    public var textBundle: Bundle? {
        guard let code else { return .module }
        guard let path = Bundle.module.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// The language among the eight that best matches `preferences`, a list of language identifiers
    /// in order of preference such as `["zh-Hans-CN", "en-CN"]` (what `AppleLanguages` holds), or
    /// `nil` when none of them is one the interface is available in.
    ///
    /// Regions are ignored (`en-CN` is English), Chinese is `zh-Hant` when its script is Traditional
    /// (`zh-Hant-TW`, and also `zh-TW` and `zh-HK`, whose script is implied) and `zh-Hans` otherwise,
    /// and Portuguese is `pt-BR`.
    public static func best(for preferences: [String]) -> AppLanguage? {
        for identifier in preferences {
            let language = Locale.Language(identifier: identifier)
            guard let languageCode = language.languageCode?.identifier else { continue }
            switch languageCode {
            case "zh":
                let script = Locale.Language(identifier: language.maximalIdentifier).script?.identifier
                return script == "Hant" ? .zhHant : .zhHans
            case "pt":
                return .ptBR
            default:
                if let match = languages.first(where: { $0.rawValue == languageCode }) {
                    return match
                }
            }
        }
        return nil
    }
}
