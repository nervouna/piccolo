import CoreGraphics

/// Which windows an animation moves step by step, and which it leaves to jump.
public enum AnimationEligibility {
    /// Two edges this close or closer are the same edge.
    public static let sameFrameTolerance: CGFloat = 1

    /// Whether a window that goes from `start` to `target` is animated.
    ///
    /// It is not when
    /// - `start` and `target` are within ``sameFrameTolerance`` of each other on every edge: there is
    ///   nothing to see, and the calls would only cost time; or
    /// - the display that holds the larger part of `start` is not the one that holds the larger part of
    ///   `target` (see ``DisplayLayout/index(containing:in:)``): a window cannot be larger than the
    ///   display it is on, so it could not take the sizes in between; or
    /// - there is no display to tell.
    public static func isAnimated(from start: CGRect, to target: CGRect, displays: [Display]) -> Bool {
        guard !isSameFrame(start, target) else { return false }
        guard
            let from = DisplayLayout.index(containing: start, in: displays),
            let to = DisplayLayout.index(containing: target, in: displays)
        else { return false }
        return from == to
    }

    /// Whether every edge of `a` is within ``sameFrameTolerance`` of the same edge of `b`.
    static func isSameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= sameFrameTolerance && abs(a.minY - b.minY) <= sameFrameTolerance
            && abs(a.maxX - b.maxX) <= sameFrameTolerance && abs(a.maxY - b.maxY) <= sameFrameTolerance
    }
}
