import Foundation

/// The name of each tab of the Settings window: the label under its icon in the toolbar and the
/// title of the window while it is selected.
public enum SettingsTabText {
    /// The name of `tab`, in the language of `bundle` (default: the running app's).
    public static func title(of tab: SettingsTab, bundle: Bundle = AppLanguage.currentTextBundle) -> String {
        switch tab {
        case .shortcuts: String(localized: "Shortcuts", bundle: bundle)
        case .general: String(localized: "General", bundle: bundle)
        }
    }

    /// The SF Symbol above the name in the toolbar.
    public static func symbolName(of tab: SettingsTab) -> String {
        switch tab {
        case .shortcuts: "keyboard"
        case .general: "gearshape"
        }
    }
}
