/// The divider a direction key moves in a linked group, and the new layout after the move.
///
/// The divider is picked from the focused cell (see `plan`). It moves by one step in the direction
/// of the key. Vertical dividers that are aligned in other rows move with it, so that a grid stays
/// a grid.
public enum DividerMove {
    /// Two divider positions this close are the same position, which is how aligned dividers are
    /// found.
    private static let alignmentTolerance = 1e-9

    /// A move smaller than this is no move at all.
    private static let movementTolerance = 1e-9

    /// The layout after the focused window's divider moves by `step` in the direction of `direction`,
    /// or `nil` when nothing moves.
    ///
    /// - `left` and `right` move a vertical divider of the focused cell's row. `left` takes the
    ///   cell's left edge when the cell has a neighbour on the left, and its right edge otherwise.
    ///   `right` takes the right edge when there is a neighbour on the right, and the left edge
    ///   otherwise. The divider moves by `-step` for `left` and by `+step` for `right`, as fractions
    ///   of the row's width.
    /// - `up` and `down` move the horizontal divider between the focused row and a neighbouring
    ///   row. `up` takes the top edge when there is a row above, and the bottom edge otherwise.
    ///   `down` takes the bottom edge when there is a row below, and the top edge otherwise. The
    ///   divider moves by `-step` for `up` and by `+step` for `down`, as fractions of the height.
    /// - A vertical divider in another row moves too when its position is the moved divider's
    ///   position, within `1e-9`. Its own two cells are involved in the move. A row without a
    ///   divider at that position does not move. Horizontal dividers span the full width, so they
    ///   have no aligned counterparts.
    /// - No cell may become narrower or lower than `minimumFraction`. Every cell involved in the
    ///   move is checked: the cells of the moved divider and those of every aligned divider. A cell
    ///   that grows has no limit. When the full step would break a limit, the move is shortened to
    ///   the largest amount that keeps every involved cell at `minimumFraction` or more. When that
    ///   amount is zero within `1e-9`, the result is `nil`.
    ///
    /// The result is `nil` as well when there is no divider to move: a single cell in the row for
    /// `left` and `right`, a single row for `up` and `down`, or a `focusedCell` outside the layout.
    ///
    /// - Parameters:
    ///   - layout: the layout to move the divider in. It must pass `TileLayout.validate()`, and so
    ///     does the result.
    ///   - focusedCell: the row-major index of the focused window's cell.
    ///   - direction: the key that was pressed.
    ///   - step: the fraction a divider moves by, greater than zero.
    ///   - minimumFraction: the smallest width or height a cell may be left with, greater than zero.
    /// - Precondition: `step` and `minimumFraction` are finite and greater than zero.
    public static func plan(
        layout: TileLayout,
        focusedCell: Int,
        direction: Direction,
        step: Double,
        minimumFraction: Double = 0.1
    ) -> TileLayout? {
        precondition(step.isFinite && step > 0, "step must be a positive, finite fraction")
        precondition(
            minimumFraction.isFinite && minimumFraction > 0,
            "minimumFraction must be a positive, finite fraction")
        guard let cell = locate(focusedCell, in: layout) else { return nil }
        switch direction {
        case .left, .right:
            return moveVerticalDivider(
                in: layout, row: cell.row, column: cell.column, direction: direction,
                step: step, minimumFraction: minimumFraction)
        case .up, .down:
            return moveHorizontalDivider(
                in: layout, row: cell.row, direction: direction,
                step: step, minimumFraction: minimumFraction)
        }
    }

    /// The row and column of the cell with the row-major index `cell`, or `nil` when there is none.
    private static func locate(_ cell: Int, in layout: TileLayout) -> (row: Int, column: Int)? {
        guard cell >= 0 else { return nil }
        var first = 0
        for (row, rowLayout) in layout.rows.enumerated() {
            let count = rowLayout.widths.count
            if cell < first + count {
                return (row: row, column: cell - first)
            }
            first += count
        }
        return nil
    }

    /// Moves the vertical divider that `left` or `right` takes in the focused row, with the aligned
    /// dividers of the other rows.
    private static func moveVerticalDivider(
        in layout: TileLayout,
        row: Int,
        column: Int,
        direction: Direction,
        step: Double,
        minimumFraction: Double
    ) -> TileLayout? {
        let cells = layout.rows[row].widths.count
        guard cells >= 2 else { return nil }

        // Divider k lies between cells k and k + 1.
        let divider: Int
        let sign: Double
        if direction == .left {
            divider = column > 0 ? column - 1 : column
            sign = -1
        } else {
            divider = column < cells - 1 ? column : column - 1
            sign = 1
        }

        let position = DividerPositions.interior(layout.rows[row].widths)[divider]
        var sides: [(row: Int, divider: Int)] = [(row: row, divider: divider)]
        for other in layout.rows.indices where other != row {
            let positions = DividerPositions.interior(layout.rows[other].widths)
            if let aligned = positions.firstIndex(where: { abs($0 - position) <= alignmentTolerance }) {
                sides.append((row: other, divider: aligned))
            }
        }

        // The cell on the side the divider moves away from is the one that shrinks, so it is the
        // only one that can run out of room.
        let amount = sides.reduce(step) { limit, side in
            let widths = layout.rows[side.row].widths
            let shrinking = sign > 0 ? widths[side.divider + 1] : widths[side.divider]
            return min(limit, shrinking - minimumFraction)
        }
        guard amount > movementTolerance else { return nil }

        var result = layout
        for side in sides {
            result.rows[side.row].widths[side.divider] += sign * amount
            result.rows[side.row].widths[side.divider + 1] -= sign * amount
        }
        return result
    }

    /// Moves the horizontal divider that `up` or `down` takes next to the focused row.
    private static func moveHorizontalDivider(
        in layout: TileLayout,
        row: Int,
        direction: Direction,
        step: Double,
        minimumFraction: Double
    ) -> TileLayout? {
        let rows = layout.rows.count
        guard rows >= 2 else { return nil }

        // Divider k lies between rows k and k + 1.
        let divider: Int
        let sign: Double
        if direction == .up {
            divider = row > 0 ? row - 1 : row
            sign = -1
        } else {
            divider = row < rows - 1 ? row : row - 1
            sign = 1
        }

        // Horizontal dividers span the full width, so only the two rows on either side are
        // involved, and the row that shrinks is the only one that can run out of room.
        let heights = layout.rows.map(\.height)
        let shrinking = sign > 0 ? heights[divider + 1] : heights[divider]
        let amount = min(step, shrinking - minimumFraction)
        guard amount > movementTolerance else { return nil }

        var result = layout
        result.rows[divider].height += sign * amount
        result.rows[divider + 1].height -= sign * amount
        return result
    }
}
