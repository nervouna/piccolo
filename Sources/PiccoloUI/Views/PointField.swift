import SwiftUI

/// A number field for a whole number of points, shown with the unit "pt" and the usual stepper
/// arrows. The field commits on Return and when it loses focus; when the model rejects the value
/// the field shows the old one again (the model's message is on screen).
struct PointField: View {
    let title: String
    /// The value the model holds.
    let value: Int
    /// The smallest and largest value the arrows move to.
    let range: ClosedRange<Int>
    /// Offers a new value to the model. Answers whether it was accepted.
    let commit: (Int) -> Bool

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .focused($isFocused)
                    .onSubmit(apply)
                Text(verbatim: "pt")
                    .foregroundStyle(.secondary)
                Stepper(
                    title,
                    onIncrement: { nudge(by: 1) },
                    onDecrement: { nudge(by: -1) }
                )
                .labelsHidden()
            }
        }
        .onAppear { showModelValue() }
        .onChange(of: value) { showModelValue() }
        .onChange(of: isFocused) { _, focused in
            if !focused { apply() }
        }
    }

    private func showModelValue() {
        text = String(value)
    }

    /// Takes what was typed: a whole number of points.
    private func apply() {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "pt", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let typed = Int(cleaned) else {
            showModelValue()
            return
        }
        if typed != value, commit(typed) {
            // Accepted: the model's new value comes back through `value` and is shown then.
            return
        }
        // Unchanged or rejected: show what the model holds.
        showModelValue()
    }

    private func nudge(by delta: Int) {
        let next = min(max(value + delta, range.lowerBound), range.upperBound)
        guard next != value else { return }
        _ = commit(next)
    }
}
