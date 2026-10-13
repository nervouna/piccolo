import SwiftUI

/// The content of the Settings window: the "Shortcuts" and "General" tabs.
public struct SettingsView: View {
    private enum Tab: Hashable {
        case shortcuts
        case general
    }

    let model: SettingsModel
    let host: SettingsHost
    @State private var tab: Tab = .shortcuts

    public init(model: SettingsModel, host: SettingsHost) {
        self.model = model
        self.host = host
    }

    public var body: some View {
        TabView(selection: $tab) {
            ShortcutsTab(model: model)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Tab.shortcuts)
            GeneralTab(model: model, host: host)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
        }
        .padding(12)
        .onChange(of: tab) {
            // A rejected change belongs to the tab it was made on.
            model.clearError()
        }
    }
}
