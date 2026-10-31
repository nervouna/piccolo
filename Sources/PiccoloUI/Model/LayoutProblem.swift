import Foundation
import PiccoloCore

/// A field of the sheet for a grid or a custom area that a problem is about.
public enum LayoutField: String, CaseIterable, Sendable {
    case left
    case top
    case width
    case height
    /// The number of windows of a grid.
    case windows
    case rows
    case columns
}

/// What is wrong with a grid or a custom area: the sentence for the person, and the fields to outline.
public struct LayoutProblem: Equatable, Sendable {
    public let message: String
    /// The fields the failing rule is about; empty for a problem that is about the layout as a whole (an
    /// equal one exists).
    public let fields: Set<LayoutField>
}

enum LayoutProblems {
    /// The first problem with `action` as a layout, or `nil` when there is none.
    ///
    /// First the config's own validation of the action, in its order, with the sentences of
    /// ``SettingsMessages`` and the fields the failing rule names; then the rule that no other binding of
    /// the same section (a grid, a custom area) has an equal action. `id` is the binding being edited,
    /// which does not count as another one. An action that is neither a grid nor a custom area has no
    /// problem.
    static func first(
        for action: Action, editing id: UUID?, in bindings: [KeyBinding], bundle: Bundle = .module
    ) -> LayoutProblem? {
        do {
            // The check of `Config` is the public form of the action's own validation.
            try Config(bindings: [KeyBinding(action: action)]).validate()
        } catch {
            return LayoutProblem(message: SettingsMessages.describe(error, bundle: bundle), fields: fields(of: error))
        }
        switch KeymapSection(of: action) {
        case .grids:
            guard bindings.contains(where: { $0.id != id && $0.action == action }) else { return nil }
            return LayoutProblem(message: SettingsMessages.duplicateGrid(bundle: bundle), fields: [])
        case .customAreas:
            guard bindings.contains(where: { $0.id != id && $0.action == action }) else { return nil }
            return LayoutProblem(message: SettingsMessages.duplicateCustomArea(bundle: bundle), fields: [])
        default:
            return nil
        }
    }

    /// The fields the rule that failed is about, by the name the config's validation gives the value.
    private static func fields(of error: ValidationError) -> Set<LayoutField> {
        switch error {
        case .notFinite(let field), .outOfRange(let field, _):
            switch field {
            case "x": return [.left]
            case "y": return [.top]
            case "width": return [.width]
            case "height": return [.height]
            case "x + width": return [.left, .width]
            case "y + height": return [.top, .height]
            case "rows": return [.rows]
            case "columns": return [.columns]
            case "count": return [.windows]
            default: return []
            }
        case .duplicateBindingID, .unsupportedVersion:
            return []
        }
    }
}
