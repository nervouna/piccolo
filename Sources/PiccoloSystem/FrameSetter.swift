import CoreGraphics

/// The operations on a window's frame that Piccolo needs, in canonical coordinates
/// (global, top-left origin, y down). A seam for fakes in tests.
public protocol WindowFrameAccess {
    /// The window's current frame.
    func frame() throws -> CGRect
    func setSize(_ size: CGSize) throws
    func setPosition(_ origin: CGPoint) throws
}

public enum FrameSetter {
    /// Moves and resizes a window to `target` and returns the frame it ended up with.
    ///
    /// The size is applied, then the position, then the size again. A window cannot
    /// be larger than the display it is currently on, so a single size-then-move (or
    /// move-then-size) sequence fails when the target is on a display of a different
    /// size: the first size is clamped to the old display, the move puts the window
    /// on the new one, and the second size reaches the requested value.
    ///
    /// The result is read back rather than assumed, since the window may refuse the
    /// requested size (minimum and maximum sizes, aspect ratio, resize increments).
    ///
    /// - Returns: The frame read back after the last step.
    @discardableResult
    public static func apply(_ target: CGRect, to window: some WindowFrameAccess) throws -> CGRect {
        try window.setSize(target.size)
        try window.setPosition(target.origin)
        try window.setSize(target.size)
        return try window.frame()
    }
}
