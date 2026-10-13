import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let accessibility = AccessibilityStatus()
    #if DEBUG
    private let debugControl = DebugControlServer()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        accessibility.start()
        #if DEBUG
        debugControl.start()
        #endif
    }
}
