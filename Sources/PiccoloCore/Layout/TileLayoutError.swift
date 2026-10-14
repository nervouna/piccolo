/// A layout that breaks one of the rules checked by `TileLayout.validate()`.
///
/// A row layout throws the first six cases. A column layout breaks the same rules, and throws the
/// matching case of the last six: the rule is the transposed one, so a column plays the part of a
/// row, its width the part of a row's height, and the height of its cells the part of the widths of a
/// row's cells.
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

    /// The layout has no columns.
    case noColumns
    /// Column `column` has no cells.
    case emptyColumn(column: Int)
    /// The width of column `column` is not finite, or not greater than zero.
    case invalidColumnWidth(column: Int)
    /// The height of the cell at `row` in column `column` is not finite, or not greater than zero.
    case invalidCellHeight(column: Int, row: Int)
    /// The heights of the cells of column `column` do not sum to 1.
    case cellHeightsDoNotSumToOne(column: Int)
    /// The widths of the columns do not sum to 1.
    case columnWidthsDoNotSumToOne

    /// The error the transposed layout throws for the same mistake: a row error becomes the column
    /// error, and the other way round.
    var transposed: TileLayoutError {
        switch self {
        case .noRows: .noColumns
        case .emptyRow(let row): .emptyColumn(column: row)
        case .invalidHeight(let row): .invalidColumnWidth(column: row)
        case .invalidWidth(let row, let column): .invalidCellHeight(column: row, row: column)
        case .widthsDoNotSumToOne(let row): .cellHeightsDoNotSumToOne(column: row)
        case .heightsDoNotSumToOne: .columnWidthsDoNotSumToOne
        case .noColumns: .noRows
        case .emptyColumn(let column): .emptyRow(row: column)
        case .invalidColumnWidth(let column): .invalidHeight(row: column)
        case .invalidCellHeight(let column, let row): .invalidWidth(row: column, column: row)
        case .cellHeightsDoNotSumToOne(let column): .widthsDoNotSumToOne(row: column)
        case .columnWidthsDoNotSumToOne: .heightsDoNotSumToOne
        }
    }
}
