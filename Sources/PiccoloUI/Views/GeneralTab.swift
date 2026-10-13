import SwiftUI

/// The "General" tab: the linked-resize step, the Accessibility status, the config file and the
/// version.
struct GeneralTab: View {
    let model: SettingsModel
    let host: SettingsHost

    var body: some View {
        VStack(spacing: 0) {
            Form {
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
    }
}
