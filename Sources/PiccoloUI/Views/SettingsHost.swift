import Foundation

/// What the Settings window needs from the app that it cannot know itself.
public struct SettingsHost {
    /// Whether the app is trusted for Accessibility. Read while a view is drawn, so an
    /// observable source keeps the window up to date.
    public var isAccessibilityTrusted: @MainActor () -> Bool
    public var openAccessibilitySettings: @MainActor () -> Void
    public var revealConfigInFinder: @MainActor () -> Void
    /// For example "0.1.0 (1)".
    public var appVersion: String

    public init(
        isAccessibilityTrusted: @escaping @MainActor () -> Bool,
        openAccessibilitySettings: @escaping @MainActor () -> Void,
        revealConfigInFinder: @escaping @MainActor () -> Void,
        appVersion: String
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.openAccessibilitySettings = openAccessibilitySettings
        self.revealConfigInFinder = revealConfigInFinder
        self.appVersion = appVersion
    }
}
