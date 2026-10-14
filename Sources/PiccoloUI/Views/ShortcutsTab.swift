import PiccoloCore
import SwiftUI

/// The "Shortcuts" tab: the list of bindings with a recorder per row, the buttons to add and
/// remove one, the editor of the selected binding, and the last error and the config's issues.
struct ShortcutsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            bindingList
            listToolbar
            Divider()
            editor
            StatusMessages(model: model)
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

    private var bindingList: some View {
        List(selection: $model.selectedBindingID) {
            ForEach(model.bindings, id: \.id) { binding in
                HStack {
                    Text(model.summary(of: binding))
                    Spacer()
                    ShortcutRecorderButton(model: model, bindingID: binding.id)
                }
                .tag(binding.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minHeight: 96, idealHeight: 132, maxHeight: 180)
        .overlay {
            if model.bindings.isEmpty {
                Text(localized: "No shortcuts yet. Click + to add one.")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
