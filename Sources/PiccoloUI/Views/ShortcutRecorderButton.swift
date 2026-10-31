import PiccoloCore
import SwiftUI

/// The shortcut button of a row of the keymap, 128 pt wide: the row's shortcut, "Record Shortcut" with a dashed
/// border when it has none, "Type shortcut…" in the accent colour while it records. Clicking it starts
/// recording; clicking it again cancels. On hover a ✕ inside the button clears the shortcut. The key press itself
/// is caught by ``SettingsWindowController``, which offers it to the model.
struct ShortcutRecorderButton: View {
    static let width: CGFloat = 128
    private static let height: CGFloat = 22
    private static let corner: CGFloat = 5

    let model: SettingsModel
    let row: KeymapRow

    @State private var isHovering = false

    var body: some View {
        let isRecording = model.recordingRow == row.id
        let shortcut = row.shortcut
        let accent = Color(nsColor: .controlAccentColor)
        let shape = RoundedRectangle(cornerRadius: Self.corner)
        ZStack(alignment: .trailing) {
            Button {
                if isRecording {
                    model.cancelRecording()
                } else {
                    model.beginRecording(row.id)
                }
            } label: {
                Text(title(isRecording: isRecording))
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isRecording ? accent : (shortcut == nil ? Color.secondary : Color.primary))
                    // Room for the ✕ on both sides, so that the text stays in the middle.
                    .padding(.horizontal, shortcut == nil || isRecording ? 6 : 22)
                    .frame(width: Self.width, height: Self.height)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .background(
                isRecording ? accent.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: shape
            )
            .overlay {
                shape.strokeBorder(
                    isRecording ? accent : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: 1, dash: shortcut == nil && !isRecording ? [3, 2] : []))
            }
            .help(
                isRecording
                    ? Text(localized: "Press the new shortcut, Escape to cancel, Delete to clear")
                    : Text(localized: "Click, then press the shortcut"))

            if isHovering, shortcut != nil, !isRecording {
                Button {
                    model.clearShortcut(row.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
                .help(Text(localized: "Remove Shortcut"))
                .accessibilityLabel(Text(localized: "Remove Shortcut"))
            }
        }
        .frame(width: Self.width, height: Self.height)
        .onHover { isHovering = $0 }
    }

    private func title(isRecording: Bool) -> String {
        if isRecording {
            return String(localized: "Type shortcut…", bundle: .module)
        }
        if let shortcut = row.shortcut {
            return model.shortcutText(for: shortcut)
        }
        return String(localized: "Record Shortcut", bundle: .module)
    }
}
