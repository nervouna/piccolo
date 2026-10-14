import AppKit
import PiccoloSystem

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let accessibility = AccessibilityStatus.shared
    let config = ConfigController.shared
    #if DEBUG
    private let debugControl = DebugControlServer()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Settles the language the app runs in before anything is looked up in another one.
        _ = SystemLanguageBackend.launchLanguage
        accessibility.start()
        config.start()
        // Records which windows are focused from now on, so that the first "arrange" has a history.
        // The first use of `ActionExecutor.live` starts it too, which only matters if this line goes.
        FocusTracker.shared.start()
        #if DEBUG
        debugControl.start()
        #endif
    }

    /// The app was launched again while it runs (Finder, `open`, the Dock). A menu bar app has
    /// no window to show, so this opens Settings: the way to reach the app when its menu bar icon
    /// is hidden, and the one way to bring a window forward without a click on macOS 14 and later.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsController.shared.show()
        return false
    }
}
