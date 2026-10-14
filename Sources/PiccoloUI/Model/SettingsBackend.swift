import Foundation
import PiccoloCore

/// The config in effect and what is wrong with it.
public struct SettingsSnapshot: Equatable, Sendable {
    public var config: Config
    /// One line per problem: bindings skipped while loading, shortcuts that may not be
    /// registered, shortcuts the system refused. Empty when everything is in order.
    public var issues: [String]

    public init(config: Config, issues: [String] = []) {
        self.config = config
        self.issues = issues
    }
}

/// A change that could not be saved, in words for the user.
public struct SettingsSaveError: Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// What ``SettingsModel`` needs from the app around it: the config file, the global hotkeys.
/// The app's implementation sits on `ShortcutManager` and `ConfigStore`; tests use one in memory.
@MainActor
public protocol SettingsBackend: AnyObject {
    /// The config in effect now.
    func current() -> SettingsSnapshot

    /// Persists `config`, applies it (the shortcuts take effect at once) and answers with the
    /// issues found. Nothing changes when it throws.
    ///
    /// - Throws: ``SettingsSaveError`` (or any error with a readable description) when the
    ///   config cannot be saved.
    func save(_ config: Config) throws -> [String]

    /// Keeps a copy of the config file next to itself (`ConfigStore.backUp()`, when there is a file),
    /// then replaces the bindings in effect with `bindings`, keeping the other settings, and persists and
    /// applies the result, as ``save(_:)`` does. Answers the file name of the copy, or `nil` when there
    /// was no file to copy. Nothing changes when it throws.
    ///
    /// - Throws: ``SettingsSaveError`` (or any error with a readable description) when the copy or the
    ///   config cannot be written.
    func backUpAndReplace(with bindings: [KeyBinding]) throws -> String?

    /// Releases every global hotkey (`true`) or registers them again (`false`). Asking for the
    /// state that is already in force does nothing.
    func setShortcutsSuspended(_ suspended: Bool)

    /// Called when the config in effect was replaced by something other than ``save(_:)``, for
    /// example a reload from the menu. The model installs it.
    var onExternalChange: (@MainActor () -> Void)? { get set }
}
