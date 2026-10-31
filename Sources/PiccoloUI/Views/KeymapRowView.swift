import PiccoloCore
import SwiftUI

/// One row of a card on the Shortcuts tab: the glyph, the name, the edit button of a grid or a custom area, the extra
/// shortcuts of a hand-edited built-in row as tags, and the shortcut button. Under it, in the same card, the
/// messages that belong to the row: the reason a shortcut was refused, and the choice to replace a shortcut that
/// another row has.
struct KeymapRowView: View {
    /// The space the glyph and the gap after it take, so that the messages line up with the name.
    static let nameInset: CGFloat = ActionGlyph.size.width + 10

    let model: SettingsModel
    let row: KeymapRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ActionGlyph(action: row.action, fillOrder: model.gridFillOrder)
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if case .layout(let id) = row.id {
                    editButton(id)
                }
                if let primary = row.primaryBinding, model.inactiveBindingIDs.contains(primary.id) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(Text(localized: "This shortcut is not active. See the problems above."))
                        .accessibilityLabel(Text(localized: "This shortcut is not active. See the problems above."))
                }
                if !row.isEditable {
                    ForEach(row.bindings.dropFirst(), id: \.id) { binding in
                        ExtraShortcutTag(model: model, binding: binding)
                    }
                }
                ShortcutRecorderButton(model: model, row: row)
            }
            messages
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func editButton(_ id: UUID) -> some View {
        Button {
            model.editLayout(.edit(id))
        } label: {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(localized: "Edit"))
        .accessibilityLabel(Text(localized: "Edit"))
    }

    // MARK: Messages

    @ViewBuilder
    private var messages: some View {
        if model.errorTarget == .row(row.id), let error = model.error {
            Text(error)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Self.nameInset)
        }
        if let conflict = model.pendingConflict, conflict.row == row.id {
            ConflictBox(model: model, conflict: conflict)
                .padding(.leading, Self.nameInset)
        }
    }
}

/// An extra shortcut of a built-in row, which a hand-edited config can hold: the shortcut as a small tag with a ✕
/// that removes its binding.
struct ExtraShortcutTag: View {
    let model: SettingsModel
    let binding: KeyBinding

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: binding.shortcut.map { model.shortcutText(for: $0) } ?? "–")
                .font(.caption)
                .lineLimit(1)
            Button {
                model.removeBinding(binding.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(localized: "Remove Shortcut"))
            .accessibilityLabel(Text(localized: "Remove Shortcut"))
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .padding(.vertical, 1)
        .background(.quaternary, in: Capsule())
    }
}

/// The box under a row whose recorded shortcut another row has: what is taken, and the choice between keeping things
/// as they are (Cancel) and moving the shortcut to this row (Replace).
struct ConflictBox: View {
    let model: SettingsModel
    let conflict: ShortcutConflict

    var body: some View {
        let owner = model.binding(conflict.ownerBindingID).map { model.summary(of: $0) } ?? ""
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(SettingsMessages.alreadyUsed(model.shortcutText(for: conflict.shortcut), by: owner))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.resolveConflict(replace: false)
            } label: {
                Text(localized: "Cancel")
            }
            .controlSize(.small)
            Button {
                model.resolveConflict(replace: true)
            } label: {
                Text(localized: "Replace")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.orange.opacity(0.5), lineWidth: 1))
    }
}
