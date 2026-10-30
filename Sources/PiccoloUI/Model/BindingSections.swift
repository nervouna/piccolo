import Foundation
import PiccoloCore

/// The bindings as the Shortcuts tab lists them: one section per action kind, filtered by a search
/// query. Pure, so that the grouping and the filter are unit tested without a view.
public struct BindingSection: Equatable, Sendable {
    public let kind: ActionKind
    /// The bindings of the kind that match the query, in the order of the config file.
    public let bindings: [KeyBinding]
}

public enum BindingSections {
    /// Groups `bindings` by action kind, in the order Place Window, Restore Window, Move to Display, Arrange Grid,
    /// Move Divider, keeping the file order inside a section, and keeps the bindings that match `query`.
    /// A section left without a binding is not in the answer.
    ///
    /// A binding matches when `query`, trimmed of surrounding whitespace and compared without regard to
    /// case and diacritics, is contained in its summary (in the language of `bundle`) or in its shortcut
    /// text (`characterForKeyCode` is the keyboard layout lookup of ``ShortcutText``). An empty query
    /// matches every binding.
    public static func make(
        bindings: [KeyBinding],
        query: String,
        bundle: Bundle = AppLanguage.currentTextBundle,
        characterForKeyCode: (Int) -> String? = { _ in nil }
    ) -> [BindingSection] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = bindings.filter { binding in
            guard !needle.isEmpty else { return true }
            if contains(ActionSummary.text(for: binding.action, bundle: bundle), needle) { return true }
            if let shortcut = binding.shortcut,
                contains(ShortcutText.string(for: shortcut, bundle: bundle, character: characterForKeyCode), needle)
            {
                return true
            }
            return false
        }
        return ActionKind.allCases.compactMap { kind in
            let ofKind = matching.filter { ActionKind($0.action) == kind }
            return ofKind.isEmpty ? nil : BindingSection(kind: kind, bindings: ofKind)
        }
    }

    private static func contains(_ text: String, _ needle: String) -> Bool {
        text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
