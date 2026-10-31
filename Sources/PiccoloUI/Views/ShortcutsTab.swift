import PiccoloCore
import SwiftUI

/// The "Shortcuts" tab: a keymap. A top bar with the search and the "⋯" menu, the banner of config problems, and
/// the cards of the sections with a row per action, in the order of ``KeymapSection``. Errors show where they
/// happen: under a row, or in the banner.
struct ShortcutsTab: View {
    @Bindable var model: SettingsModel
    let host: SettingsHost

    var body: some View {
        VStack(spacing: 8) {
            topBar
            ProblemsBanner(model: model)
                .padding(.horizontal, 16)
            keymap
        }
        .alert(
            Text(localized: "Restore the default shortcuts?"), isPresented: $model.isConfirmingRestore
        ) {
            Button(role: .destructive) {
                model.restoreDefaultShortcuts()
            } label: {
                Text(localized: "Restore")
            }
            Button(role: .cancel) {
                model.cancelRestoreDefaults()
            } label: {
                Text(localized: "Cancel")
            }
        } message: {
            Text(
                localized:
                    "The current shortcuts will be replaced by the defaults. A copy of the config file is kept next to it."
            )
        }
        .sheet(item: LayoutEditorSheet.presentation(of: model)) { presentation in
            LayoutEditorSheet(model: model, request: presentation.request)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            searchField
            menu
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                String(localized: "Search", bundle: .module),
                text: Binding(get: { model.search }, set: { model.setSearch($0) })
            )
            .textFieldStyle(.plain)
            .onExitCommand {
                model.setSearch("")
            }
            if !model.search.isEmpty {
                Button {
                    model.setSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(localized: "Clear Search"))
                .accessibilityLabel(Text(localized: "Clear Search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private var menu: some View {
        Menu {
            Button {
                model.askToRestoreDefaults()
            } label: {
                Text(localized: "Restore Default Shortcuts…")
            }
            .help(
                Text(
                    localized:
                        "Replace every shortcut with the defaults. A copy of the config file is kept next to it."))
            Button {
                host.revealConfigInFinder()
            } label: {
                Text(localized: "Reveal Config in Finder")
            }
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityLabel(Text(localized: "More"))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Cards

    @ViewBuilder
    private var keymap: some View {
        let groups = model.keymap
        if groups.isEmpty {
            Text(localized: "No shortcuts match")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.section) { group in
                            KeymapCard(model: model, group: group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // A click on anything that is not a control ends a recording.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.isRecording {
                            model.cancelRecording()
                        }
                    }
                }
                .onChange(of: model.recordingRow) { _, row in
                    if let row {
                        proxy.scrollTo(row)
                    }
                }
            }
        }
    }
}

/// The card of one section: its header, a row per action and, for grids and custom areas, the row that adds one.
private struct KeymapCard: View {
    let model: SettingsModel
    let group: KeymapGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.section.title())
                .font(.headline)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().padding(.leading, 12)
                    }
                    KeymapRowView(model: model, row: row)
                        .id(row.id)
                }
                if let title = group.section.addRowTitle() {
                    if !group.rows.isEmpty {
                        Divider().padding(.leading, 12)
                    }
                    addRow(title)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }

    private func addRow(_ title: String) -> some View {
        Button {
            model.editLayout(.new(group.section))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .frame(width: ActionGlyph.size.width)
                Text(title)
                Spacer()
            }
            .foregroundStyle(Color(nsColor: .controlAccentColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
