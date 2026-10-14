import SwiftUI

/// The content of the Settings window: the "Shortcuts" and "General" tabs. The tab shown is the
/// model's ``SettingsModel/tab``.
public struct SettingsView: View {
    @Bindable var model: SettingsModel
    let host: SettingsHost

    public init(model: SettingsModel, host: SettingsHost) {
        self.model = model
        self.host = host
    }

    public var body: some View {
        TabView(selection: $model.tab) {
            ShortcutsTab(model: model)
                .tabItem {
                    Label {
                        Text(localized: "Shortcuts")
                    } icon: {
                        Image(systemName: "keyboard")
                    }
                }
                .tag(SettingsTab.shortcuts)
            GeneralTab(model: model, host: host)
                .tabItem {
                    Label {
                        Text(localized: "General")
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                }
                .tag(SettingsTab.general)
        }
        .padding(12)
        .onChange(of: model.tab) {
            // A rejected change belongs to the tab it was made on.
            model.clearError()
        }
    }
}
