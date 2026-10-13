import CoreGraphics

/// Moves a frame back inside a visible frame without resizing it.
public enum FrameFitting {
    /// The frame with the same size, with its origin shifted the least that makes it lie inside
    /// `visibleFrame`.
    ///
    /// The window is shifted left and up when it sticks out on the right or at the bottom, but never
    /// past the top-left corner of `visibleFrame`: a window larger than `visibleFrame` is aligned to
    /// that corner and sticks out on the right and at the bottom. A frame already inside is returned
    /// unchanged.
    public static func shifted(_ frame: CGRect, into visibleFrame: CGRect) -> CGRect {
        let x = max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - frame.width))
        let y = max(visibleFrame.minY, min(frame.minY, visibleFrame.maxY - frame.height))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }
}
