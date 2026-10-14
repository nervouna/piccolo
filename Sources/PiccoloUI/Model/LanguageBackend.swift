/// Why Piccolo could not be restarted, in words for the user.
public struct RestartError: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// What ``SettingsModel`` needs from the system to let the user choose the language of the
/// interface. The app plugs in the defaults domain of Piccolo and a restart helper; tests use a fake.
///
/// macOS picks the language of an app when the app starts, from the `AppleLanguages` list in the
/// app's own defaults domain, or from the system's list when the app has none. So a change takes
/// effect at the next launch, and the running app keeps the language it started with.
@MainActor
public protocol LanguageBackend: AnyObject {
    /// The choice stored for the next launch: ``AppLanguage/system`` when the app has no language of
    /// its own.
    var storedLanguage: AppLanguage { get }

    /// Stores the choice for the next launch. ``AppLanguage/system`` removes it, so that the system's
    /// list applies again.
    func store(_ language: AppLanguage)

    /// The language the running app shows its texts in. Never ``AppLanguage/system``, and fixed for
    /// the life of the process.
    var runningLanguage: AppLanguage { get }

    /// The language a launch would use if the choice were ``AppLanguage/system``: the one among the
    /// eight that best matches the system's list. Never ``AppLanguage/system``.
    var systemLanguage: AppLanguage { get }

    /// Quits Piccolo and starts it again, so that the stored choice applies. Does not return when
    /// the app quits.
    ///
    /// - Throws: ``RestartError`` when the restart could not be arranged. The app is still running then.
    func restart() throws(RestartError)
}
