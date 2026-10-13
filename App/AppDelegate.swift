import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let accessibility = AccessibilityStatus()
    let config = ConfigController.shared
    #if DEBUG
    private let debugControl = DebugControlServer()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        accessibility.start()
        config.start()
        #if DEBUG
        debugControl.start()
        #endif
    }
}
