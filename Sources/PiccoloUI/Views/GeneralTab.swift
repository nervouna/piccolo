import PiccoloCore
import SwiftUI

/// The "General" tab, in the groups of #99 item 9: launch at login and the language without a header,
/// then moving windows, arranging windows, and the Accessibility status with the config file. The app's
/// name and version sit under the last group. A rejected window gap or linked resize step shows under its
/// field; the config problems and the other messages are the Shortcuts tab's.
struct GeneralTab: View {
    let model: SettingsModel
    let host: SettingsHost

    var body: some View {
        let trusted = host.isAccessibilityTrusted()
        // The card of Accessibility and the config file is tinted while the permission is missing.
        let card: Color? = trusted ? nil : Color.orange.opacity(0.15)

        VStack(spacing: 12) {
            Form {
                Section {
                    LaunchAtLoginRows(model: model)
                    LanguageRows(model: model)
                }

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
                    .pickerStyle(.segmented)

                    Toggle(
                        isOn: Binding(
                            get: { model.destinationPreview },
                            set: { model.setDestinationPreview($0) })
                    ) {
                        Text(localized: "Show destination while a shortcut is held")
                    }
                } header: {
                    Text(localized: "Moving windows")
                } footer: {
                    Text(localized: "Release the shortcut to move the windows, or press Escape to cancel.")
                }

                Section {
                    PointField(
                        title: String(localized: "Window gap", bundle: .module), value: model.gap,
                        range: WindowGap.range
                    ) { newValue in
                        model.setGap(newValue)
                    }
                    if model.errorTarget == .field(.gap), let error = model.error {
                        FieldError(message: error)
                    }

                    LabeledContent {
                        FillOrderChoice(model: model)
                    } label: {
                        Text(localized: "Fill order")
                    }

                    PercentField(
                        title: String(localized: "Linked resize step", bundle: .module),
                        fraction: model.resizeStep, step: 0.01, range: 0.01...0.5
                    ) { newValue in
                        model.setResizeStep(newValue)
                    }
                    if model.errorTarget == .field(.resizeStep), let error = model.error {
                        FieldError(message: error)
                    }
                } header: {
                    Text(localized: "Arranging windows")
                }

                Section {
                    LabeledContent {
                        if trusted {
                            Label {
                                Text(localized: "Granted")
                            } icon: {
                                Image(systemName: "checkmark.circle")
                            }
                        } else {
                            HStack {
                                Label {
                                    Text(localized: "Not granted")
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle")
                                }
                                Button {
                                    host.openAccessibilitySettings()
                                } label: {
                                    Text(localized: "Open Accessibility Settings…")
                                }
                            }
                        }
                    } label: {
                        Text(localized: "Accessibility")
                    }
                    .listRowBackground(card)

                    LabeledContent {
                        Button {
                            host.revealConfigInFinder()
                        } label: {
                            Text(localized: "Show in Finder")
                        }
                    } label: {
                        Text(localized: "Config file")
                    }
                    .listRowBackground(card)
                }
            }
            .formStyle(.grouped)

            Text(verbatim: "Piccolo \(host.appVersion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            // The user can change the login item in System Settings at any time, and the language
            // of the app too.
            model.refreshLoginItem()
            model.refreshLanguage()
        }
    }
}

/// The login item rows: the "Launch at login" switch, with its approval note and its error.
private struct LaunchAtLoginRows: View {
    let model: SettingsModel

    var body: some View {
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

/// The language picker: "System default" and the eight languages, each written in its own
/// language so that it can be found whatever the current one is. A choice takes effect when Piccolo
/// starts again, so a line says so with a button that restarts it.
private struct LanguageRows: View {
    let model: SettingsModel

    var body: some View {
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

/// A rejected value, under the field it is about.
private struct FieldError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.octagon.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
    }
}

/// The fill order as two picture tiles side by side. The selected one has an accent border.
private struct FillOrderChoice: View {
    let model: SettingsModel

    var body: some View {
        HStack(spacing: 12) {
            FillOrderTile(
                order: .rows, label: Text(localized: "Rows first"), selected: model.gridFillOrder == .rows
            ) {
                model.setGridFillOrder(.rows)
            }
            FillOrderTile(
                order: .columns, label: Text(localized: "Columns first"),
                selected: model.gridFillOrder == .columns
            ) {
                model.setGridFillOrder(.columns)
            }
        }
    }
}

/// One fill order: its picture and its name, as a button.
private struct FillOrderTile: View {
    let order: GridFillOrder
    let label: Text
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                FillOrderPicture(order: order)
                    .frame(width: 120, height: 75)
                label
                    .font(.callout)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small screen with three windows in 2 × 2, numbered in the order that `order` lays them out.
private struct FillOrderPicture: View {
    let order: GridFillOrder

    var body: some View {
        GeometryReader { proxy in
            let frames = TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: order)
                .frames(in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                ForEach(frames.indices, id: \.self) { index in
                    let frame = frames[index].insetBy(dx: 3, dy: 3)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .controlAccentColor).opacity(0.35))
                        .overlay {
                            Text(verbatim: "\(index + 1)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
