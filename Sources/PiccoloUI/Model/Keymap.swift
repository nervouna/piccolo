import Foundation
import PiccoloCore

/// Identifies a row of the Shortcuts tab's keymap: a built-in action, or the binding of a grid or a
/// custom area.
public enum KeymapRowID: Hashable, Sendable {
    /// The row of a built-in action (`Action.isBuiltIn`). It exists whether a binding has the action or not.
    case builtIn(Action)
    /// The row of a grid or a custom area: the ID of its binding.
    case layout(UUID)

    /// The row a binding is shown in.
    public init(_ binding: KeyBinding) {
        self = binding.action.isBuiltIn ? .builtIn(binding.action) : .layout(binding.id)
    }

    /// The row's name on the debug control channel: `placeWindow.<preset>`, `restoreWindow`,
    /// `moveToDisplay.<direction>`, `moveDivider.<direction>` or `swapWindow.<direction>` for a built-in
    /// row, the binding's UUID for a layout row.
    public var name: String {
        switch self {
        case .layout(let id):
            return id.uuidString
        case .builtIn(let action):
            switch action {
            case .placeWindow(.preset(let preset)): return "placeWindow.\(preset.rawValue)"
            case .placeWindow(.custom): return "placeWindow.custom"
            case .restoreWindow: return "restoreWindow"
            case .moveToDisplay(let direction): return "moveToDisplay.\(direction.rawValue)"
            case .moveDivider(let direction): return "moveDivider.\(direction.rawValue)"
            case .swapWindow(let direction): return "swapWindow.\(direction.rawValue)"
            case .arrangeGrid: return "arrangeGrid"
            }
        }
    }

    /// The row ``name`` names, or `nil` for a name no row has.
    public init?(name: String) {
        if let action = BuiltInActions.all.first(where: { KeymapRowID.builtIn($0).name == name }) {
            self = .builtIn(action)
        } else if let id = UUID(uuidString: name) {
            self = .layout(id)
        } else {
            return nil
        }
    }

    // Equal IDs have equal names, so hashing the name keeps `Hashable` consistent with `==` without
    // `Action` being hashable.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// One row of the keymap: an action with its bindings.
public struct KeymapRow: Equatable, Sendable, Identifiable {
    public let id: KeymapRowID
    public let action: Action
    /// The summary of the action in the language of the bundle the keymap was made with ("Left Half").
    public let name: String
    /// A built-in row: every binding with its action, in file order, possibly none. A layout row: its own
    /// binding.
    public let bindings: [KeyBinding]
    /// Whether the action can be changed: true for the rows of grids and custom areas, false for built-in actions.
    public let isEditable: Bool

    /// The binding that holds the row's shortcut: the first one.
    public var primaryBinding: KeyBinding? {
        bindings.first
    }

    /// The row's shortcut: the first binding's, if it has one.
    public var shortcut: Shortcut? {
        primaryBinding?.shortcut
    }
}

/// A section of the keymap with the rows it shows.
public struct KeymapGroup: Equatable, Sendable {
    public let section: KeymapSection
    public let rows: [KeymapRow]
}

/// The bindings as the Shortcuts tab's keymap lists them: nine sections of rows, filtered by a search
/// query. Pure, so that the rows and the filter are unit tested without a view.
public enum Keymap {
    /// The sections in the order of ``KeymapSection``, each with its rows.
    ///
    /// Every built-in action is a row whether a binding has it or not; the rows of the grids and custom
    /// areas are the bindings with such an action, one row each, in file order. A binding without a
    /// shortcut counts as no shortcut.
    ///
    /// A row matches `query` when the query, trimmed of surrounding whitespace and compared without regard
    /// to case and diacritics, is contained in its name (in the language of `bundle`) or in the text of one
    /// of its shortcuts (`characterForKeyCode` is the keyboard layout lookup of ``ShortcutText``). An empty
    /// query matches every row. A section without a matching row is left out, except that with an empty
    /// query the grids and the custom areas are always there, possibly without rows.
    public static func make(
        bindings: [KeyBinding],
        query: String,
        bundle: Bundle = AppLanguage.currentTextBundle,
        characterForKeyCode: (Int) -> String? = { _ in nil }
    ) -> [KeymapGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ row: KeymapRow) -> Bool {
            guard !needle.isEmpty else { return true }
            if contains(row.name, needle) { return true }
            return row.bindings.contains { binding in
                guard let shortcut = binding.shortcut else { return false }
                return contains(ShortcutText.string(for: shortcut, bundle: bundle, character: characterForKeyCode), needle)
            }
        }
        return KeymapSection.allCases.compactMap { section in
            let rows: [KeymapRow]
            switch section {
            case .grids, .customAreas:
                rows = bindings.filter { KeymapSection(of: $0.action) == section }
                    .map { layoutRow($0, bundle: bundle) }
            default:
                rows = BuiltInActions.all.filter { KeymapSection(of: $0) == section }
                    .map { builtInRow($0, in: bindings, bundle: bundle) }
            }
            let shown = rows.filter(matches)
            let alwaysShown = needle.isEmpty && (section == .grids || section == .customAreas)
            return shown.isEmpty && !alwaysShown ? nil : KeymapGroup(section: section, rows: shown)
        }
    }

    /// The row with this ID, or `nil` when there is none: a layout ID that no binding of a grid or a
    /// custom area has, or a built-in row of an action that is not built in.
    public static func row(
        _ id: KeymapRowID, in bindings: [KeyBinding], bundle: Bundle = AppLanguage.currentTextBundle
    ) -> KeymapRow? {
        switch id {
        case .builtIn(let action):
            return action.isBuiltIn ? builtInRow(action, in: bindings, bundle: bundle) : nil
        case .layout(let bindingID):
            guard let binding = bindings.first(where: { $0.id == bindingID }), !binding.action.isBuiltIn else {
                return nil
            }
            return layoutRow(binding, bundle: bundle)
        }
    }

    private static func builtInRow(_ action: Action, in bindings: [KeyBinding], bundle: Bundle) -> KeymapRow {
        KeymapRow(
            id: .builtIn(action), action: action, name: ActionSummary.text(for: action, bundle: bundle),
            bindings: bindings.filter { $0.action == action }, isEditable: false)
    }

    private static func layoutRow(_ binding: KeyBinding, bundle: Bundle) -> KeymapRow {
        KeymapRow(
            id: .layout(binding.id), action: binding.action,
            name: ActionSummary.text(for: binding.action, bundle: bundle),
            bindings: [binding], isEditable: true)
    }

    private static func contains(_ text: String, _ needle: String) -> Bool {
        text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
