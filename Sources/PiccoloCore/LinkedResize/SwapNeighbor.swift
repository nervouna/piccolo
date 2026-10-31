import CoreGraphics

/// The cell a window trades places with in a swap.
///
/// The choice is geometric, so it works the same on row layouts and column layouts, with no
/// transpose. Cells are compared in a fixed reference frame without a window gap (see
/// ``referenceFrame``), where neighbouring cells share their edges exactly.
public enum SwapNeighbor {
    /// The frame the layout is laid out in. It is large, so that fractions of a layout round to
    /// whole points that tell any two different edges apart, and it has no gap, so that
    /// neighbouring cells share their edges.
    static let referenceFrame = CGRect(x: 0, y: 0, width: 10_000, height: 10_000)

    /// Edges are whole points. Two edges within this distance are the same edge.
    private static let edgeTolerance: CGFloat = 0.5

    /// The index of the cell the window in `cell` swaps with when the key for `direction` is
    /// pressed, or `nil` when no cell is on that side.
    ///
    /// A candidate is a cell whose edge facing the focused cell coincides with the focused cell's
    /// edge on the side of `direction` (for `left`: the candidate's right edge is the focused cell's
    /// left edge), and whose extent on the other axis overlaps the focused cell's by a positive
    /// length. The candidate with the longest overlap wins; on a tie, the lowest cell index.
    ///
    /// - Parameters:
    ///   - cell: the index of the focused window's cell, in cell order (row-major for a row layout,
    ///     column-major for a column layout). A cell outside the layout has no neighbour.
    ///   - direction: the key that was pressed.
    ///   - layout: the layout of the group, a row layout or a column layout. It must pass
    ///     `TileLayout.validate()`.
    public static func neighbor(of cell: Int, direction: Direction, in layout: TileLayout) -> Int? {
        let frames = layout.frames(in: referenceFrame)
        guard frames.indices.contains(cell) else { return nil }
        let focused = frames[cell]

        var best: (cell: Int, overlap: CGFloat)?
        for (index, candidate) in frames.enumerated() where index != cell {
            let overlap: CGFloat
            switch direction {
            case .left:
                guard coincide(candidate.maxX, focused.minX) else { continue }
                overlap = overlapLength(candidate.minY, candidate.maxY, focused.minY, focused.maxY)
            case .right:
                guard coincide(candidate.minX, focused.maxX) else { continue }
                overlap = overlapLength(candidate.minY, candidate.maxY, focused.minY, focused.maxY)
            case .up:
                guard coincide(candidate.maxY, focused.minY) else { continue }
                overlap = overlapLength(candidate.minX, candidate.maxX, focused.minX, focused.maxX)
            case .down:
                guard coincide(candidate.minY, focused.maxY) else { continue }
                overlap = overlapLength(candidate.minX, candidate.maxX, focused.minX, focused.maxX)
            }
            guard overlap > 0 else { continue }
            // Strictly longer wins, so that on a tie the first (lowest) index stays.
            if let current = best, overlap <= current.overlap { continue }
            best = (index, overlap)
        }
        return best?.cell
    }

    private static func coincide(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) <= edgeTolerance
    }

    /// The length two spans `a0...a1` and `b0...b1` share; zero or less when they do not overlap.
    private static func overlapLength(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
        min(a1, b1) - max(a0, b0)
    }
}
