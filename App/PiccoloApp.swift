import SwiftUI

struct PiccoloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Piccolo", systemImage: "rectangle.split.2x2") {
            MenuContent(accessibility: appDelegate.accessibility)
        }
        .menuBarExtraStyle(.menu)
    }
}
