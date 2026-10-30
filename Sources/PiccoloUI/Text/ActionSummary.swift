import Foundation
import PiccoloCore

/// The words the Settings window uses for actions: one short line per action, for lists, menus
/// and error messages. Pure, so that every action and preset is covered by a unit test.
///
/// The words are looked up in PiccoloUI's string catalog, in the language of `bundle`: the running
/// app's by default, and a given language's ``AppLanguage/textBundle`` when a test wants to read a
/// translation. The examples below are the English ones.
public enum ActionSummary {
    /// One line that says what the action does: "Left Half", "Custom (25%, 0%, 50% × 100%)",
    /// "Next Display", "Arrange 4 in 2 × 2", "Move Divider Left".
    public static func text(for action: Action, bundle: Bundle = AppLanguage.currentTextBundle) -> String {
        switch action {
        case .placeWindow(.preset(let preset)):
            return name(of: preset, bundle: bundle)
        case .placeWindow(.custom(let rect)):
            return String(
                localized:
                    "Custom (\(percent(rect.x)), \(percent(rect.y)), \(percent(rect.width)) × \(percent(rect.height)))",
                bundle: bundle)
        case .moveToDisplay(let direction):
            return name(of: direction, bundle: bundle)
        case .arrangeGrid(let grid):
            return String(localized: "Arrange \(grid.count) in \(grid.rows) × \(grid.columns)", bundle: bundle)
        case .moveDivider(let direction):
            switch direction {
            case .left: return String(localized: "Move Divider Left", bundle: bundle)
            case .right: return String(localized: "Move Divider Right", bundle: bundle)
            case .up: return String(localized: "Move Divider Up", bundle: bundle)
            case .down: return String(localized: "Move Divider Down", bundle: bundle)
            }
        }
    }

    public static func name(of preset: Preset, bundle: Bundle = AppLanguage.currentTextBundle) -> String {
        switch preset {
        case .leftHalf: String(localized: "Left Half", bundle: bundle)
        case .rightHalf: String(localized: "Right Half", bundle: bundle)
        case .topHalf: String(localized: "Top Half", bundle: bundle)
        case .bottomHalf: String(localized: "Bottom Half", bundle: bundle)
        case .topLeft: String(localized: "Top Left", bundle: bundle)
        case .topRight: String(localized: "Top Right", bundle: bundle)
        case .bottomLeft: String(localized: "Bottom Left", bundle: bundle)
        case .bottomRight: String(localized: "Bottom Right", bundle: bundle)
        case .leftThird: String(localized: "Left Third", bundle: bundle)
        case .centerThird: String(localized: "Center Third", bundle: bundle)
        case .rightThird: String(localized: "Right Third", bundle: bundle)
        case .leftTwoThirds: String(localized: "Left Two Thirds", bundle: bundle)
        case .rightTwoThirds: String(localized: "Right Two Thirds", bundle: bundle)
        case .maximize: String(localized: "Maximize", bundle: bundle)
        case .center: String(localized: "Center", bundle: bundle)
        }
    }

    public static func name(
        of direction: DisplayDirection, bundle: Bundle = AppLanguage.currentTextBundle
    ) -> String {
        switch direction {
        case .next: String(localized: "Next Display", bundle: bundle)
        case .previous: String(localized: "Previous Display", bundle: bundle)
        case .left: String(localized: "Display to the Left", bundle: bundle)
        case .right: String(localized: "Display to the Right", bundle: bundle)
        case .up: String(localized: "Display Above", bundle: bundle)
        case .down: String(localized: "Display Below", bundle: bundle)
        }
    }

    /// "Left", "Right", "Up" or "Down".
    public static func name(of direction: Direction, bundle: Bundle = AppLanguage.currentTextBundle) -> String {
        switch direction {
        case .left: String(localized: "Left", bundle: bundle)
        case .right: String(localized: "Right", bundle: bundle)
        case .up: String(localized: "Up", bundle: bundle)
        case .down: String(localized: "Down", bundle: bundle)
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
