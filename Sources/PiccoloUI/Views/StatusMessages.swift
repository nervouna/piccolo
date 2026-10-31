import SwiftUI

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
