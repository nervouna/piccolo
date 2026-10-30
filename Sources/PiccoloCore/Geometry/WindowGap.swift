import CoreGraphics

/// The window gap: the space, in points, between windows Piccolo places side by side and between
/// those windows and the edges of the visible frame.
///
/// This is the one place the rule is written. Every frame Piccolo computes (presets, custom
/// frames, the cycling steps, the cells of a grid and of a group, the display move) is computed
/// without a gap first, with its edges rounded to whole points as before, and goes through
/// ``inset(_:gap:in:)`` last.
public enum WindowGap {
    /// The gaps a config can hold, in points.
    public static let range = 0...64

    /// The gap of a config that does not set one.
    public static let `default` = 0

    /// Two edges this close, in points, are the same edge: a frame edge on the visible frame's edge.
    static let edgeTolerance: CGFloat = 1

    /// `frame`, which was computed without a gap, with the gap applied inside `visibleFrame`.
    ///
    /// An edge of `frame` that lies on the same edge of `visibleFrame` (within 1 pt) moves inwards
    /// by `gap`. Any other edge is shared with a neighbour (or is free in the middle of the screen)
    /// and moves inwards by half the gap, so two neighbours end up `gap` apart.
    ///
    /// Rounding: a shared edge is already one whole number, rounded once when the frames were
    /// computed. The two halves of an odd gap cannot both be whole, so the near side of a divider
    /// takes the smaller half: a left or top edge moves in by `gap - gap / 2` and a right or bottom
    /// edge by `gap / 2` (integer division). Facing edges are therefore exactly `gap` apart for any
    /// gap and any visible frame, and the result stays on whole points.
    ///
    /// A side that would be left with less than one point keeps one point instead. With a gap of 0
    /// the frame comes back unchanged.
    public static func inset(_ frame: CGRect, gap: Int, in visibleFrame: CGRect) -> CGRect {
        guard gap > 0 else { return frame }
        let full = CGFloat(gap)
        let low = CGFloat(gap - gap / 2)
        let high = CGFloat(gap / 2)

        let left = frame.minX + (onEdge(frame.minX, visibleFrame.minX) ? full : low)
        let right = frame.maxX - (onEdge(frame.maxX, visibleFrame.maxX) ? full : high)
        let top = frame.minY + (onEdge(frame.minY, visibleFrame.minY) ? full : low)
        let bottom = frame.maxY - (onEdge(frame.maxY, visibleFrame.maxY) ? full : high)
        return CGRect(
            x: left, y: top,
            width: max(right - left, 1), height: max(bottom - top, 1))
    }

    /// `visibleFrame` with `gap` taken off every side: the area a window with a gap on all sides
    /// can use.
    public static func inset(_ visibleFrame: CGRect, by gap: Int) -> CGRect {
        guard gap > 0 else { return visibleFrame }
        let amount = CGFloat(gap)
        return CGRect(
            x: visibleFrame.minX + amount, y: visibleFrame.minY + amount,
            width: max(visibleFrame.width - 2 * amount, 1),
            height: max(visibleFrame.height - 2 * amount, 1))
    }

    private static func onEdge(_ edge: CGFloat, _ screenEdge: CGFloat) -> Bool {
        abs(edge - screenEdge) <= edgeTolerance
    }
}
