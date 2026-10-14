import Foundation

/// A tiling of a visible frame by rows of cells, or by columns of cells, stored as fractions so
/// that the layout does not depend on the screen it is applied to.
///
/// A **row layout** runs its rows from top to bottom. A row's `height` is a fraction of the total
/// height, and its `widths` are fractions of the row's width, from left to right. Each entry of
/// `widths` is one window. Heights and widths that sum to 1 tile the frame exactly. Cells are
/// numbered row by row, left to right within a row.
///
/// A **column layout** is the transpose of a row layout: swap x and y, and widths and heights. Its
/// columns run from left to right. A column's `width` is a fraction of the total width, and its
/// `heights` are fractions of the column's height, from top to bottom. Cells are numbered column by
/// column, top to bottom within a column.
///
/// `frames(in:)` turns the fractions into whole-point rectangles. A column layout is kept as the
/// row layout it is the transpose of, with the orientation turned around (see `transposed`), so
/// that whatever is true of rows is true of columns without a second implementation: the frames, the
/// validation and the divider moves of linked resize all go through the transpose.
public struct TileLayout: Equatable, Sendable, Codable {
    /// Which way the lines of a layout run.
    public enum Orientation: Equatable, Sendable {
        /// Rows from top to bottom, cells numbered row by row.
        case rows
        /// Columns from left to right, cells numbered column by column.
        case columns
    }

    /// Whether this is a row layout or a column layout.
    public private(set) var orientation: Orientation

    /// The lines of the layout in row form. For a row layout they are its rows, top to bottom. For a
    /// column layout they are the rows of its transpose, that is its columns from left to right: a
    /// line's `height` is a column's width, and its `widths` are the heights of the column's cells.
    /// Only code that works on both orientations at once reads this; everything else uses `rows` or
    /// `columns`.
    var lines: [Row]

    /// A row layout.
    public init(rows: [Row]) {
        orientation = .rows
        lines = rows
    }

    /// A column layout.
    public init(columns: [Column]) {
        orientation = .columns
        lines = columns.map { Row(height: $0.width, widths: $0.heights) }
    }

    /// The rows of a row layout, from top to bottom. A column layout has none.
    public var rows: [Row] {
        get { orientation == .rows ? lines : [] }
        set {
            precondition(orientation == .rows, "a column layout has no rows to replace")
            lines = newValue
        }
    }

    /// The columns of a column layout, from left to right. A row layout has none.
    public var columns: [Column] {
        orientation == .columns ? lines.map { Column(width: $0.height, heights: $0.widths) } : []
    }

    /// A row of cells.
    public struct Row: Equatable, Sendable, Codable {
        /// Fraction of the total height.
        public var height: Double
        /// Fractions of the row's width, one per cell, from left to right.
        public var widths: [Double]

        public init(height: Double, widths: [Double]) {
            self.height = height
            self.widths = widths
        }
    }

    /// A column of cells.
    public struct Column: Equatable, Sendable, Codable {
        /// Fraction of the total width.
        public var width: Double
        /// Fractions of the column's height, one per cell, from top to bottom.
        public var heights: [Double]

        public init(width: Double, heights: [Double]) {
            self.width = width
            self.heights = heights
        }
    }

    /// The layout with x and y swapped: a row layout becomes the column layout with the same
    /// numbers, and the other way round. A cell keeps its number, so the cell `i` of a layout is the
    /// cell `i` of its transpose, mirrored across the diagonal.
    ///
    /// The frames of a layout are the transposed frames of its transpose, in the transposed visible
    /// frame: `frames(in: v) == transposed.frames(in: v.transposed).map(\.transposed)`.
    public var transposed: TileLayout {
        var layout = self
        layout.orientation = orientation == .rows ? .columns : .rows
        return layout
    }

    /// Number of cells, one per window.
    public var windowCount: Int {
        lines.reduce(0) { $0 + $1.widths.count }
    }

    /// The number of cells in each line: in each row of a row layout, in each column of a column
    /// layout.
    var cellsPerLine: [Int] {
        lines.map { $0.widths.count }
    }

    /// Tolerance for the sums of fractions, which need not be exact in floating point.
    private static let sumTolerance = 1e-9

    /// Checks what `frames(in:)` relies on: at least one row (column), at least one cell per row
    /// (column), every fraction finite and greater than zero, the heights (widths) of the rows
    /// (columns) summing to 1, and the widths (heights) of the cells of each row (column) summing to
    /// 1. Sums may miss 1 by up to `1e-9`. A column layout breaks the same rules as the row layout it
    /// is the transpose of, and the error names the column, the width or the height instead.
    public func validate() throws(TileLayoutError) {
        do {
            try Self.validate(lines)
        } catch {
            throw orientation == .rows ? error : error.transposed
        }
    }

    private static func validate(_ lines: [Row]) throws(TileLayoutError) {
        guard !lines.isEmpty else { throw .noRows }
        for (index, row) in lines.enumerated() {
            guard row.height.isFinite, row.height > 0 else { throw .invalidHeight(row: index) }
            guard !row.widths.isEmpty else { throw .emptyRow(row: index) }
            for (column, width) in row.widths.enumerated() {
                guard width.isFinite, width > 0 else {
                    throw .invalidWidth(row: index, column: column)
                }
            }
            guard isOne(row.widths.reduce(0, +)) else {
                throw .widthsDoNotSumToOne(row: index)
            }
        }
        guard isOne(lines.reduce(0) { $0 + $1.height }) else {
            throw .heightsDoNotSumToOne
        }
    }

    private static func isOne(_ sum: Double) -> Bool {
        abs(sum - 1) <= sumTolerance
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case rows
        case columns
    }

    /// Reads `{"rows": [...]}` as a row layout and `{"columns": [...]}` as a column layout. A layout
    /// that has both keys, or neither, is refused.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (container.contains(.rows), container.contains(.columns)) {
        case (true, false):
            self.init(rows: try container.decode([Row].self, forKey: .rows))
        case (false, true):
            self.init(columns: try container.decode([Column].self, forKey: .columns))
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "a layout has either rows or columns, not both and not neither"))
        }
    }

    /// Writes a row layout as `{"rows": [...]}`, as it always was, and a column layout as
    /// `{"columns": [...]}`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch orientation {
        case .rows: try container.encode(rows, forKey: .rows)
        case .columns: try container.encode(columns, forKey: .columns)
        }
    }
}
