/// The positions of the dividers along one axis, as cumulative fractions of the whole.
///
/// A row with widths `[0.25, 0.5, 0.25]` has its dividers at `0.25` and `0.75`. A `TileLayout`
/// stores fractions, so these helpers convert between the two forms. The positions are sums of
/// the fractions, so they are exact only up to floating point rounding.
enum DividerPositions {
    /// The position of each divider: the sum of the fractions before it. A list of
    /// `fractions.count` fractions has `fractions.count - 1` dividers, and the last fraction ends
    /// the axis without one.
    static func interior(_ fractions: [Double]) -> [Double] {
        var sum = 0.0
        var positions: [Double] = []
        for fraction in fractions.dropLast() {
            sum += fraction
            positions.append(sum)
        }
        return positions
    }

    /// The fractions between consecutive positions, starting at 0 and ending at 1. The inverse of
    /// `interior` when the positions are increasing.
    static func fractions(_ positions: [Double]) -> [Double] {
        zip([0.0] + positions, positions + [1.0]).map { $1 - $0 }
    }

    /// Whether the positions give only fractions above zero, so that a layout built from them
    /// passes `TileLayout.validate()`.
    static func hasPositiveFractions(_ positions: [Double]) -> Bool {
        zip([0.0] + positions, positions + [1.0]).allSatisfy { $0 < $1 }
    }
}
