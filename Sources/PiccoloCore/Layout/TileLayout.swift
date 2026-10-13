/// A tiling of a visible frame by rows of cells, stored as fractions so that the
/// layout does not depend on the screen it is applied to.
///
/// Rows run from top to bottom. A row's `height` is a fraction of the total height,
/// and its `widths` are fractions of the row's width, from left to right. Each entry
/// of `widths` is one window. Heights and widths that sum to 1 tile the frame exactly.
/// `frames(in:)` turns the fractions into whole-point rectangles.
public struct TileLayout: Equatable, Sendable, Codable {
    /// Rows from top to bottom.
    public var rows: [Row]

    public init(rows: [Row]) {
        self.rows = rows
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

    /// Number of cells, one per window.
    public var windowCount: Int {
        rows.reduce(0) { $0 + $1.widths.count }
    }

    /// Tolerance for the sums of fractions, which need not be exact in floating point.
    private static let sumTolerance = 1e-9

    /// Checks what `frames(in:)` relies on: at least one row, at least one cell per row,
    /// every fraction finite and greater than zero, the heights summing to 1, and the
    /// widths of each row summing to 1. Sums may miss 1 by up to `1e-9`.
    public func validate() throws(TileLayoutError) {
        guard !rows.isEmpty else { throw .noRows }
        for (index, row) in rows.enumerated() {
            guard row.height.isFinite, row.height > 0 else { throw .invalidHeight(row: index) }
            guard !row.widths.isEmpty else { throw .emptyRow(row: index) }
            for (column, width) in row.widths.enumerated() {
                guard width.isFinite, width > 0 else {
                    throw .invalidWidth(row: index, column: column)
                }
            }
            guard Self.isOne(row.widths.reduce(0, +)) else {
                throw .widthsDoNotSumToOne(row: index)
            }
        }
        guard Self.isOne(rows.reduce(0) { $0 + $1.height }) else {
            throw .heightsDoNotSumToOne
        }
    }

    private static func isOne(_ sum: Double) -> Bool {
        abs(sum - 1) <= sumTolerance
    }
}
