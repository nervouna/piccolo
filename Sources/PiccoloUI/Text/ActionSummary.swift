import Foundation
import PiccoloCore

/// The words the Settings window uses for actions: one short line per action, for lists, menus
/// and error messages. Pure, so that every action and preset is covered by a unit test.
public enum ActionSummary {
    /// One line that says what the action does: "Left Half", "Custom (25%, 0%, 50% × 100%)",
    /// "Next Display", "Arrange 4 in 2 × 2", "Move Divider Left".
    public static func text(for action: Action) -> String {
        switch action {
        case .placeWindow(.preset(let preset)):
            return name(of: preset)
        case .placeWindow(.custom(let rect)):
            return "Custom (\(percent(rect.x)), \(percent(rect.y)), \(percent(rect.width)) × \(percent(rect.height)))"
        case .moveToDisplay(let direction):
            return name(of: direction)
        case .arrangeGrid(let grid):
            return "Arrange \(grid.count) in \(grid.rows) × \(grid.columns)"
        case .moveDivider(let direction):
            return "Move Divider \(name(of: direction))"
        }
    }

    public static func name(of preset: Preset) -> String {
        switch preset {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .maximize: "Maximize"
        case .center: "Center"
        }
    }

    public static func name(of direction: DisplayDirection) -> String {
        switch direction {
        case .next: "Next Display"
        case .previous: "Previous Display"
        }
    }

    /// "Left", "Right", "Up" or "Down".
    public static func name(of direction: Direction) -> String {
        switch direction {
        case .left: "Left"
        case .right: "Right"
        case .up: "Up"
        case .down: "Down"
        }
    }

    /// A fraction of the screen as a percentage: 0.25 is "25%", 1 / 3 is "33.33%". Whole
    /// percentages have no decimals, others at most two, and the separator is always a point.
    public static func percent(_ fraction: Double) -> String {
        "\(percentNumber(fraction))%"
    }

    /// The number of `percent(_:)` without the sign, for fields that show the sign separately.
    public static func percentNumber(_ fraction: Double) -> String {
        // Rounded to two decimals first, so that 0.1 * 100 does not print as 10.000000000000002.
        let rounded = (fraction * 100 * 100).rounded() / 100
        guard rounded.isFinite, abs(rounded) < 1e15 else { return "\(rounded)" }
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}
