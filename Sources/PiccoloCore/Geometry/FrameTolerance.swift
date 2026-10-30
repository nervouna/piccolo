import CoreGraphics

/// Compares frames the way Piccolo recognises a window where it left it.
public enum FrameTolerance {
    /// The distance in points that an edge may be off and still count as the same place.
    public static let points: CGFloat = 2

    /// Whether every edge of `lhs` is within `tolerance` of the same edge of `rhs`.
    public static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = points) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.maxX - rhs.maxX) <= tolerance && abs(lhs.maxY - rhs.maxY) <= tolerance
    }
}
