import CoreGraphics

extension TileLayout {
    /// The frame of every cell inside `visibleFrame`, in row-major order: the top row first,
    /// each row from left to right.
    ///
    /// Each interior boundary is its cumulative fraction scaled to the visible frame, then
    /// rounded to the nearest whole point (ties away from zero) on its own. The outermost
    /// boundaries are the rounded edges of `visibleFrame`. Neighbouring cells therefore share
    /// exact edges, with no gaps and no overlaps.
    ///
    /// The layout is assumed to be valid (see `validate()`), and `visibleFrame` to have a
    /// non-negative size.
    public func frames(in visibleFrame: CGRect) -> [CGRect] {
        let rowEdges = Self.edges(
            from: visibleFrame.minY,
            extent: visibleFrame.height,
            to: visibleFrame.maxY,
            fractions: rows.map(\.height))
        var cells: [CGRect] = []
        cells.reserveCapacity(windowCount)
        for (index, row) in rows.enumerated() {
            let columnEdges = Self.edges(
                from: visibleFrame.minX,
                extent: visibleFrame.width,
                to: visibleFrame.maxX,
                fractions: row.widths)
            for column in row.widths.indices {
                let left = columnEdges[column]
                let right = columnEdges[column + 1]
                let top = rowEdges[index]
                let bottom = rowEdges[index + 1]
                cells.append(
                    CGRect(x: left, y: top, width: right - left, height: bottom - top))
            }
        }
        return cells
    }

    /// Boundaries along one axis: `fractions.count + 1` values from `start` to `end`.
    ///
    /// Boundary `k` is `start + (fractions[0] + ... + fractions[k - 1]) * extent`, rounded on
    /// its own, so the cumulative sum is never rounded. The last boundary is `end` rounded.
    private static func edges(
        from start: CGFloat, extent: CGFloat, to end: CGFloat, fractions: [Double]
    ) -> [CGFloat] {
        var edges: [CGFloat] = []
        edges.reserveCapacity(fractions.count + 1)
        var cumulative = 0.0
        for fraction in fractions {
            edges.append((start + CGFloat(cumulative) * extent).rounded())
            cumulative += fraction
        }
        edges.append(end.rounded())
        return edges
    }
}
