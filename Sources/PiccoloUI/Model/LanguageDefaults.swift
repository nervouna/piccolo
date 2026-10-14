import Foundation

/// The language choice as macOS stores it: the `AppleLanguages` list in an app's own defaults
/// domain, which the system reads when the app starts.
///
/// One code in the list makes the app start in that language. No `AppleLanguages` key in the
/// domain makes it follow the system's list, so ``AppLanguage/system`` is stored by removing the
/// key. System Settings writes the same key for an app under Language & Region, Applications, so
/// the two stay in step, and a list written by it (which can hold a region, or several languages)
/// reads as the first language of the list that the interface is available in.
public struct LanguageDefaults {
    /// The key macOS reads the languages of an app from.
    public static let key = "AppleLanguages"

    private let defaults: UserDefaults
    private let domain: String

    /// - Parameters:
    ///   - defaults: The user defaults to read and write.
    ///   - domain: The name of the app's own domain in them: its bundle ID. (`defaults` itself would
    ///     also answer with the system's list, which is not the choice of the app.)
    public init(defaults: UserDefaults, domain: String) {
        self.defaults = defaults
        self.domain = domain
    }

    /// What the app's own domain holds: ``AppLanguage/system`` when it has no `AppleLanguages`
    /// list, or one that names no language the interface is available in.
    public var stored: AppLanguage {
        guard let list = defaults.persistentDomain(forName: domain)?[Self.key] as? [String] else {
            return .system
        }
        return AppLanguage.best(for: list) ?? .system
    }

    /// Stores `language` for the next launch of the app: its code as the only element of the
    /// list, or no list for ``AppLanguage/system``.
    public func store(_ language: AppLanguage) {
        if let code = language.code {
            defaults.set([code], forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
        // The app may be quit right after, and a write that has not reached the preferences daemon
        // by then would be lost.
        defaults.synchronize()
    }
}
