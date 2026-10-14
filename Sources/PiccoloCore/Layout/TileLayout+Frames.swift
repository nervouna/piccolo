import CoreGraphics

extension TileLayout {
    /// The frame of every cell inside `visibleFrame`, in cell order: row-major for a row layout (the
    /// top row first, each row from left to right), column-major for a column layout (the left
    /// column first, each column from top to bottom).
    ///
    /// Each interior boundary is its cumulative fraction scaled to the visible frame, then
    /// rounded to a whole point on its own with `EdgeRounding.round`. The outermost boundaries
    /// are the rounded edges of `visibleFrame`. Neighbouring cells therefore share exact edges,
    /// with no gaps and no overlaps.
    ///
    /// A column layout gets its frames from its transpose: they are the transposed frames of the
    /// transposed row layout in the transposed visible frame, so that the rounding guarantees are
    /// the same for both orientations.
    ///
    /// The layout is assumed to be valid (see `validate()`), and `visibleFrame` to have a
    /// non-negative size.
    public func frames(in visibleFrame: CGRect) -> [CGRect] {
        switch orientation {
        case .rows:
            return rowFrames(in: visibleFrame)
        case .columns:
            return transposed.rowFrames(in: visibleFrame.transposed).map(\.transposed)
        }
    }

    /// The frames of a row layout, in row-major order.
    private func rowFrames(in visibleFrame: CGRect) -> [CGRect] {
        let rowEdges = Self.edges(
            from: visibleFrame.minY,
            extent: visibleFrame.height,
            to: visibleFrame.maxY,
            fractions: lines.map(\.height))
        var cells: [CGRect] = []
        cells.reserveCapacity(windowCount)
        for (index, row) in lines.enumerated() {
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
            edges.append(EdgeRounding.round(start + CGFloat(cumulative) * extent))
            cumulative += fraction
        }
        edges.append(EdgeRounding.round(end))
        return edges
    }
}

extension CGRect {
    /// The rectangle with x and y swapped, and width and height: the mirror image across the
    /// diagonal. Transposing twice gives the original.
    var transposed: CGRect {
        CGRect(x: minY, y: minX, width: height, height: width)
    }
}
