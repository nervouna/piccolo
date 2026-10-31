import SwiftUI

/// The compact banner under the top bar of the Shortcuts tab: the problems found in the config file, and the
/// error of a change that belongs to no row. It lists at most about four lines and scrolls beyond that; the text
/// can be selected.
struct ProblemsBanner: View {
    /// About four lines of the callout font, with the padding.
    private static let maximumHeight: CGFloat = 76

    let model: SettingsModel

    var body: some View {
        let windowError = model.errorTarget == .window ? model.error : nil
        if windowError != nil || !model.issues.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let windowError {
                        Label(windowError, systemImage: "exclamationmark.octagon.fill")
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: Self.maximumHeight)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
