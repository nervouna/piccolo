import AppKit
import PiccoloSystem
import SwiftUI

struct MenuContent: View {
    let accessibility: AccessibilityStatus

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

        Button("Quit Piccolo") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
