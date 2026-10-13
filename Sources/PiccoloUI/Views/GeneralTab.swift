import SwiftUI

/// The "General" tab: launch at login, the linked-resize step, the Accessibility status, the config
/// file and the version.
struct GeneralTab: View {
    let model: SettingsModel
    let host: SettingsHost

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LaunchAtLoginSection(model: model)

                Section {
                    PercentField(
                        title: "Resize step", fraction: model.resizeStep, step: 0.01, range: 0.01...0.5
                    ) { newValue in
                        model.setResizeStep(newValue)
                    }
                } footer: {
                    Text("How far a linked resize moves a divider, as a share of the screen. Between 0% and 50%.")
                }

                Section("Accessibility") {
                    LabeledContent("Status") {
                        if host.isAccessibilityTrusted() {
                            Label("Granted", systemImage: "checkmark.circle")
                        } else {
                            Label("Not granted", systemImage: "exclamationmark.triangle")
                        }
                    }
                    Button("Open Accessibility Settings…") {
                        host.openAccessibilitySettings()
                    }
                }

                Section("Config") {
                    Button("Reveal Config in Finder") {
                        host.revealConfigInFinder()
                    }
                }

                Section {
                    LabeledContent("Version", value: host.appVersion)
                }
            }
            .formStyle(.grouped)

            StatusMessages(model: model)
        }
        .onAppear {
            // The user can change the login item in System Settings at any time.
            model.refreshLoginItem()
        }
    }
}

/// The "Launch at login" switch. It shows what the system says: when the tab appears and after
/// every change the model reads the status again, and a refused change puts the switch back and
/// says why right under it.
private struct LaunchAtLoginSection: View {
    let model: SettingsModel

    var body: some View {
        Section {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }))

            if model.loginItemStatus == .requiresApproval {
                Text("Piccolo is waiting for your approval. Allow it in Login Items in System Settings.")
                    .foregroundStyle(.secondary)
                Button("Open Login Items Settings…") {
                    model.openLoginItemsSettings()
                }
            }

            if let error = model.loginItemError {
                Label(error, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}
