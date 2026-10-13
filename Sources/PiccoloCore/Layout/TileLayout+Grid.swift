extension TileLayout {
    /// The layout that places `windowCount` windows row by row on a `rows` by `columns` grid.
    ///
    /// Only the first `min(windowCount, rows * columns)` cells are used. Every used row holds
    /// `columns` windows, except the last, which holds the remainder. Used rows have equal
    /// heights, and the windows of a row have equal widths. A short last row therefore
    /// stretches to the full width, and unused rows give their height to the used ones.
    ///
    /// - Precondition: `windowCount`, `rows` and `columns` are each at least 1.
    public static func grid(windowCount: Int, rows: Int, columns: Int) -> TileLayout {
        precondition(windowCount >= 1, "windowCount must be at least 1")
        precondition(rows >= 1, "rows must be at least 1")
        precondition(columns >= 1, "columns must be at least 1")
        // A product that overflows is larger than any window count.
        let (capacity, overflow) = rows.multipliedReportingOverflow(by: columns)
        let count = overflow ? windowCount : min(windowCount, capacity)
        let usedRows = (count - 1) / columns + 1
        let height = 1 / Double(usedRows)
        let layoutRows = (0..<usedRows).map { row -> Row in
            // Every row before the last one is full, so this is always at least 1.
            let cells = min(columns, count - row * columns)
            return Row(height: height, widths: Array(repeating: 1 / Double(cells), count: cells))
        }
        return TileLayout(rows: layoutRows)
    }
}
