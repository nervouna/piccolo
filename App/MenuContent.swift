import AppKit
import PiccoloSystem
import SwiftUI

struct MenuContent: View {
    let accessibility: AccessibilityStatus
    let config: ConfigController

    var body: some View {
        if accessibility.isTrusted {
            Label("Accessibility: Granted", systemImage: "checkmark.circle")
        } else {
            Label("Accessibility: Not granted", systemImage: "exclamationmark.triangle")
            Button("Open Accessibility Settings…") {
                AccessibilityPermission().openSettings()
            }
        }

        Divider()

        Label(
            config.status.summary,
            systemImage: config.status.issues.isEmpty ? "keyboard" : "exclamationmark.triangle")
        Button("Reload Config") {
            config.reload()
        }
        Button("Reveal Config in Finder") {
            config.revealInFinder()
        }

        Divider()

        Button("Quit Piccolo") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
