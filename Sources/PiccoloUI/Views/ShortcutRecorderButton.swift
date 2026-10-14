import PiccoloCore
import SwiftUI

/// Shows a binding's shortcut, or "Record Shortcut" when it has none. Clicking it starts
/// recording ("Type shortcut…"); clicking it again cancels. The key press itself is caught by
/// ``SettingsWindowController``, which offers it to the model.
struct ShortcutRecorderButton: View {
    let model: SettingsModel
    let bindingID: UUID

    var body: some View {
        let isRecording = model.recordingBindingID == bindingID
        Button {
            if isRecording {
                model.cancelRecording()
            } else {
                model.beginRecording(bindingID)
            }
        } label: {
            Text(title(isRecording: isRecording))
                .frame(minWidth: 110)
                .foregroundStyle(isRecording ? Color(nsColor: .controlAccentColor) : Color.primary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(
            isRecording
                ? Text(localized: "Press the new shortcut, Escape to cancel, Delete to clear")
                : Text(localized: "Click, then press the shortcut"))
    }

    private func title(isRecording: Bool) -> String {
        if isRecording {
            return String(localized: "Type shortcut…", bundle: .module)
        }
        if let shortcut = model.binding(bindingID)?.shortcut {
            return model.shortcutText(for: shortcut)
        }
        return String(localized: "Record Shortcut", bundle: .module)
    }
}
