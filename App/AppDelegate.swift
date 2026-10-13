import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let accessibility = AccessibilityStatus()

    func applicationDidFinishLaunching(_ notification: Notification) {
        accessibility.start()
    }
}
