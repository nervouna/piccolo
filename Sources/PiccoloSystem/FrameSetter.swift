import CoreGraphics
import PiccoloCore

/// The operations on a window's frame that Piccolo needs, in canonical coordinates
/// (global, top-left origin, y down). A seam for fakes in tests.
public protocol WindowFrameAccess {
    /// The window's current frame.
    func frame() throws -> CGRect
    func setSize(_ size: CGSize) throws
    func setPosition(_ origin: CGPoint) throws
    /// The window's number, which keys Piccolo's record of it, or `nil` when the window has none (it
    /// is then neither recorded nor restorable).
    var windowID: WindowID? { get }
}

extension WindowFrameAccess {
    public var windowID: WindowID? { nil }
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
    /// requested size (minimum and maximum sizes, aspect ratio, resize increments). A window
    /// whose size cannot be set at all (a fixed-size window) is still moved to the target's
    /// origin and keeps its size.
    ///
    /// When `visibleFrame` is given and the window ends up sticking out of it, which happens when
    /// the window refused the size, its origin is shifted so that it lies inside, where possible,
    /// and never beyond the top-left corner of `visibleFrame` (see ``FrameFitting``). Without it
    /// the window stays where the target put it.
    ///
    /// - Parameters:
    ///   - target: The frame to apply, in canonical coordinates.
    ///   - window: The window to move.
    ///   - visibleFrame: The visible frame of the display the window is meant to end up on.
    /// - Returns: The frame read back after the last step.
    /// - Throws: Whatever the window throws, except that a size that is not settable is skipped.
    @discardableResult
    public static func apply(
        _ target: CGRect,
        to window: some WindowFrameAccess,
        within visibleFrame: CGRect? = nil
    ) throws -> CGRect {
        try setSizeIfPossible(target.size, of: window)
        try window.setPosition(target.origin)
        try setSizeIfPossible(target.size, of: window)
        var achieved = try window.frame()

        if let visibleFrame {
            let fitted = FrameFitting.shifted(achieved, into: visibleFrame)
            if fitted.origin != achieved.origin {
                try window.setPosition(fitted.origin)
                achieved = try window.frame()
            }
        }
        return achieved
    }

    /// Sets the size, unless the window does not allow it, which is how a fixed-size window says
    /// no. Every other failure is real and propagates.
    private static func setSizeIfPossible(_ size: CGSize, of window: some WindowFrameAccess) throws {
        do {
            try window.setSize(size)
        } catch WindowError.attributeNotSettable {
            return
        }
    }
}
