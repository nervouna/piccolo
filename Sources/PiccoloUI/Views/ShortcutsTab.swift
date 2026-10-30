import PiccoloCore
import SwiftUI

/// The "Shortcuts" tab: the list of bindings with a recorder per row, the buttons to add and
/// remove one, the editor of the selected binding, and the last error and the config's issues.
struct ShortcutsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            bindingList
            listToolbar
            Divider()
            // The editor and the messages keep their natural height; the list takes the rest.
            editor
                .fixedSize(horizontal: false, vertical: true)
            StatusMessages(model: model)
                .fixedSize(horizontal: false, vertical: true)
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
    }

    // MARK: List

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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var bindingList: some View {
        ScrollViewReader { proxy in
            List(selection: $model.selectedBindingID) {
                ForEach(model.sections, id: \.kind) { section in
                    Section {
                        ForEach(section.bindings, id: \.id) { binding in
                            HStack {
                                Text(model.summary(of: binding))
                                Spacer()
                                if model.inactiveBindingIDs.contains(binding.id) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                        .help(Text(localized: "This shortcut is not active. See the problems below."))
                                        .accessibilityLabel(
                                            Text(localized: "This shortcut is not active. See the problems below."))
                                }
                                ShortcutRecorderButton(model: model, bindingID: binding.id)
                            }
                            .tag(binding.id)
                            .id(binding.id)
                        }
                    } header: {
                        Text(section.kind.title)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: model.selectedBindingID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(minHeight: 96, maxHeight: .infinity)
        .overlay {
            if model.bindings.isEmpty {
                Text(localized: "No shortcuts yet. Click + to add one.")
                    .foregroundStyle(.secondary)
            } else if model.sections.isEmpty {
                Text(localized: "No shortcuts match")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var listToolbar: some View {
        HStack(spacing: 4) {
            Button {
                model.addBinding()
            } label: {
                Image(systemName: "plus")
            }
            .help(Text(localized: "Add a shortcut"))
            .accessibilityLabel(Text(localized: "Add Shortcut"))

            Button {
                if let id = model.selectedBindingID {
                    model.removeBinding(id)
                }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(model.selectedBindingID == nil)
            .help(Text(localized: "Remove the selected shortcut"))
            .accessibilityLabel(Text(localized: "Remove Shortcut"))

            Button {
                model.askToRestoreDefaults()
            } label: {
                Text(localized: "Restore Default Shortcuts…")
            }
            .help(
                Text(
                    localized:
                        "Replace every shortcut with the defaults. A copy of the config file is kept next to it."))

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let id = model.selectedBindingID, let binding = model.binding(id) {
            BindingEditor(model: model, binding: binding)
        } else {
            Group {
                if model.bindings.isEmpty {
                    Text(verbatim: "")
                } else {
                    Text(localized: "Select a shortcut to edit what it does.")
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
        }
    }
}

/// The rejected change, if any, and the problems with the config file. Shown on both tabs.
struct StatusMessages: View {
    let model: SettingsModel

    var body: some View {
        if model.error != nil || !model.issues.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    ForEach(model.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 96)
            .background(.bar)
        }
    }
}
