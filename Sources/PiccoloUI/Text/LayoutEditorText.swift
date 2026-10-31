import Foundation

/// The texts of the sheet that creates and edits a grid or a custom area, apart from the plain labels the view
/// looks up itself.
enum LayoutEditorText {
    /// The title of the sheet: "New Grid", "Edit Grid", "New Custom Area" or "Edit Custom Area", in the language of
    /// `bundle` (default: the running app's).
    static func title(isNew: Bool, isGrid: Bool, bundle: Bundle = AppLanguage.currentTextBundle) -> String {
        switch (isNew, isGrid) {
        case (true, true): String(localized: "New Grid", bundle: bundle)
        case (false, true): String(localized: "Edit Grid", bundle: bundle)
        case (true, false): String(localized: "New Custom Area", bundle: bundle)
        case (false, false): String(localized: "Edit Custom Area", bundle: bundle)
        }
    }

    /// The size of a grid under the cell picker: "3 × 4" for 3 rows by 4 columns. The key has a word in it because
    /// the build derives a Swift symbol from every key, which "%lld × %lld" alone does not allow; the text
    /// itself is just the two numbers.
    static func size(rows: Int, columns: Int, bundle: Bundle = AppLanguage.currentTextBundle) -> String {
        String(localized: "Grid size \(rows) × \(columns)", bundle: bundle)
    }
}
