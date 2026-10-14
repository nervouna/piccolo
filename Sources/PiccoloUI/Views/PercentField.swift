import SwiftUI

/// A number field for a fraction of the screen, shown as a percentage, with the usual stepper
/// arrows. The field commits on Return and when it loses focus; when the model rejects the value
/// the field shows the old one again (the model's message is on screen).
struct PercentField: View {
    let title: String
    /// The value the model holds, as a fraction (0.25 shows as 25).
    let fraction: Double
    /// What one click on the arrows adds or takes, as a fraction.
    let step: Double
    /// The smallest and largest fraction the arrows move to.
    let range: ClosedRange<Double>
    /// Offers a new fraction to the model. Answers whether it was accepted.
    let commit: (Double) -> Bool

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
                Text(verbatim: "%")
                    .foregroundStyle(.secondary)
                Stepper(
                    title,
                    onIncrement: { nudge(by: step) },
                    onDecrement: { nudge(by: -step) }
                )
                .labelsHidden()
            }
        }
        .onAppear { showModelValue() }
        .onChange(of: fraction) { showModelValue() }
        .onChange(of: isFocused) { _, focused in
            if !focused { apply() }
        }
    }

    private func showModelValue() {
        text = ActionSummary.percentNumber(fraction)
    }

    /// Takes what was typed: a number in percent, with a point or a comma.
    private func apply() {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "%", with: "")
        guard let percent = Double(cleaned), percent.isFinite else {
            showModelValue()
            return
        }
        // Two decimals of a percent are enough, and keep the file free of rounding noise.
        let value = (percent * 100).rounded() / 10_000
        if abs(value - fraction) > 1e-9, commit(value) {
            // Accepted: the model's new value comes back through `fraction` and is shown then.
            return
        }
        // Unchanged or rejected: show what the model holds.
        showModelValue()
    }

    private func nudge(by delta: Double) {
        let value = min(max(((fraction + delta) * 10_000).rounded() / 10_000, range.lowerBound), range.upperBound)
        guard abs(value - fraction) > 1e-9 else { return }
        _ = commit(value)
    }
}
