import Foundation
import PiccoloCore

extension KeymapSection {
    /// The header of the section's card on the Shortcuts tab, in the language of `bundle`: "Halves",
    /// "Quarters", "Thirds", "Other", "Displays", "Arrange Grid", "Move Divider", "Swap Window" or
    /// "Custom Areas".
    public func title(bundle: Bundle = AppLanguage.currentTextBundle) -> String {
        switch self {
        case .halves: String(localized: "Halves", bundle: bundle)
        case .quarters: String(localized: "Quarters", bundle: bundle)
        case .thirds: String(localized: "Thirds", bundle: bundle)
        case .other: String(localized: "Other", bundle: bundle)
        case .displays: String(localized: "Displays", bundle: bundle)
        case .grids: String(localized: "Arrange Grid", bundle: bundle)
        case .dividers: String(localized: "Move Divider", bundle: bundle)
        case .swaps: String(localized: "Swap Window", bundle: bundle)
        case .customAreas: String(localized: "Custom Areas", bundle: bundle)
        }
    }

    /// The text of the row that adds a layout to the section ("Add Grid…", "Add Custom Area…"), or `nil` for a
    /// section that has no such row.
    public func addRowTitle(bundle: Bundle = AppLanguage.currentTextBundle) -> String? {
        switch self {
        case .grids: String(localized: "Add Grid…", bundle: bundle)
        case .customAreas: String(localized: "Add Custom Area…", bundle: bundle)
        default: nil
        }
    }
}
