import SwiftUI

struct PiccoloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Piccolo", image: "MenuBarIcon") {
            MenuContent(accessibility: appDelegate.accessibility, config: appDelegate.config)
        }
        .menuBarExtraStyle(.menu)
    }
}
