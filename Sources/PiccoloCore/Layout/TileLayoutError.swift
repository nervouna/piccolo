/// A layout that breaks one of the rules checked by `TileLayout.validate()`.
public enum TileLayoutError: Error, Equatable, Sendable {
    /// The layout has no rows.
    case noRows
    /// Row `row` has no cells.
    case emptyRow(row: Int)
    /// The height of row `row` is not finite, or not greater than zero.
    case invalidHeight(row: Int)
    /// The width of the cell at `column` in row `row` is not finite, or not greater than zero.
    case invalidWidth(row: Int, column: Int)
    /// The widths of row `row` do not sum to 1.
    case widthsDoNotSumToOne(row: Int)
    /// The heights of the rows do not sum to 1.
    case heightsDoNotSumToOne
}
