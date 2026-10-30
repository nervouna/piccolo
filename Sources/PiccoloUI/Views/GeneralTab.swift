import PiccoloCore
import SwiftUI

/// The "General" tab: the language, launch at login, the window animation, the window gap, the grid fill order, the
/// destination preview, the linked-resize step, the Accessibility status, the config file and the
/// version.
struct GeneralTab: View {
    let model: SettingsModel
    let host: SettingsHost

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LanguageSection(model: model)

                LaunchAtLoginSection(model: model)

                Section {
                    Picker(
                        selection: Binding(
                            get: { model.animation },
                            set: { model.setAnimation($0) })
                    ) {
                        Text(localized: "Off").tag(WindowAnimation.off)
                        Text(localized: "Fast").tag(WindowAnimation.fast)
                        Text(localized: "Medium").tag(WindowAnimation.medium)
                        Text(localized: "Slow").tag(WindowAnimation.slow)
                    } label: {
                        Text(localized: "Window animation")
                    }
                    PointField(
                        title: String(localized: "Window gap", bundle: .module), value: model.gap,
                        range: WindowGap.range
                    ) { newValue in
                        model.setGap(newValue)
                    }
                } footer: {
                    Text(localized: "How long a window takes to move to its new place.")
                }

                Section {
                    Picker(
                        selection: Binding(
                            get: { model.gridFillOrder },
                            set: { model.setGridFillOrder($0) })
                    ) {
                        Text(localized: "Rows first").tag(GridFillOrder.rows)
                        Text(localized: "Columns first").tag(GridFillOrder.columns)
                    } label: {
                        Text(localized: "Fill order")
                    }
                } header: {
                    Text(localized: "Arranging windows")
                } footer: {
                    Text(
                        localized:
                            "When the windows do not fill the grid. With 3 windows in 2 × 2, rows first puts two windows on top and one across the bottom; columns first puts two on the left and one down the right side."
                    )
                }

                Section {
                    Toggle(
                        isOn: Binding(
                            get: { model.destinationPreview },
                            set: { model.setDestinationPreview($0) })
                    ) {
                        Text(localized: "Show destination while a shortcut is held")
                    }
                } footer: {
                    Text(
                        localized:
                            "Hold a shortcut to see where windows will go, release it to move them, or press Escape to cancel. When off, windows move as soon as the shortcut is pressed."
                    )
                }

                Section {
                    PercentField(
                        title: String(localized: "Resize step", bundle: .module), fraction: model.resizeStep,
                        step: 0.01, range: 0.01...0.5
                    ) { newValue in
                        model.setResizeStep(newValue)
                    }
                } footer: {
                    Text(
                        localized:
                            "How far a linked resize moves a divider, as a share of the screen. Between 0% and 50%.")
                }

                Section {
                    LabeledContent {
                        if host.isAccessibilityTrusted() {
                            Label {
                                Text(localized: "Granted")
                            } icon: {
                                Image(systemName: "checkmark.circle")
                            }
                        } else {
                            Label {
                                Text(localized: "Not granted")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                        }
                    } label: {
                        Text(localized: "Status")
                    }
                    Button {
                        host.openAccessibilitySettings()
                    } label: {
                        Text(localized: "Open Accessibility Settings…")
                    }
                } header: {
                    Text(localized: "Accessibility")
                }

                Section {
                    Button {
                        host.revealConfigInFinder()
                    } label: {
                        Text(localized: "Reveal Config in Finder")
                    }
                } header: {
                    Text(localized: "Config")
                }

                Section {
                    LabeledContent {
                        Text(verbatim: host.appVersion)
                    } label: {
                        Text(localized: "Version")
                    }
                }
            }
            .formStyle(.grouped)

            StatusMessages(model: model)
        }
        .onAppear {
            // The user can change the login item in System Settings at any time, and the language
            // of the app too.
            model.refreshLoginItem()
            model.refreshLanguage()
        }
    }
}

/// The language picker: "System default" and the eight languages, each written in its own
/// language so that it can be found whatever the current one is. A choice takes effect when Piccolo
/// starts again, so a line says so with a button that restarts it.
private struct LanguageSection: View {
    let model: SettingsModel

    var body: some View {
        Section {
            Picker(
                selection: Binding(
                    get: { model.language },
                    set: { model.setLanguage($0) })
            ) {
                Text(localized: "System default").tag(AppLanguage.system)
                Divider()
                ForEach(AppLanguage.languages, id: \.self) { language in
                    Text(verbatim: language.nativeName ?? language.rawValue).tag(language)
                }
            } label: {
                Text(localized: "Language")
            }

            if model.restartRequired {
                Text(localized: "The new language applies after Piccolo restarts.")
                    .foregroundStyle(.secondary)
                Button {
                    model.restartNow()
                } label: {
                    Text(localized: "Restart Now")
                }
            }

            if let error = model.restartError {
                Label(error, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
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
                isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) })
            ) {
                Text(localized: "Launch at login")
            }

            if model.loginItemStatus == .requiresApproval {
                Text(localized: "Piccolo is waiting for your approval. Allow it in Login Items in System Settings.")
                    .foregroundStyle(.secondary)
                Button {
                    model.openLoginItemsSettings()
                } label: {
                    Text(localized: "Open Login Items Settings…")
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
