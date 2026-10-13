import CoreGraphics

/// Conversion between AppKit's global screen space and Piccolo's canonical space.
///
/// - AppKit space (`NSScreen.frame`, `NSEvent.mouseLocation`): the origin is the
///   bottom-left corner of the primary display and y points up.
/// - Canonical space (Accessibility and CGWindow APIs, and everything inside
///   `PiccoloCore`): the origin is the top-left corner of the primary display
///   and y points down.
///
/// Both spaces span all displays, so the x axis is shared and only the y axis
/// is mirrored around the primary display's height. Displays above the primary
/// have negative canonical y, displays to its left have negative x in both
/// spaces. Conversions are pure functions of the rect and the primary display's
/// height, and each one is the inverse of the other.
public enum ScreenSpace {
    /// Converts a rect from AppKit screen space to canonical space.
    ///
    /// - Parameters:
    ///   - rect: A rect in AppKit space (bottom-left origin, y up).
    ///   - primaryDisplayHeight: The height of the primary display, in points.
    /// - Returns: The same rectangle in canonical space (top-left origin, y down),
    ///   with a non-negative size.
    public static func canonicalRect(
        fromAppKit rect: CGRect,
        primaryDisplayHeight: CGFloat
    ) -> CGRect {
        mirrorVertically(rect, aroundHeight: primaryDisplayHeight)
    }

    /// Converts a rect from canonical space to AppKit screen space.
    ///
    /// - Parameters:
    ///   - rect: A rect in canonical space (top-left origin, y down).
    ///   - primaryDisplayHeight: The height of the primary display, in points.
    /// - Returns: The same rectangle in AppKit space (bottom-left origin, y up),
    ///   with a non-negative size.
    public static func appKitRect(
        fromCanonical rect: CGRect,
        primaryDisplayHeight: CGFloat
    ) -> CGRect {
        mirrorVertically(rect, aroundHeight: primaryDisplayHeight)
    }

    /// Flipping the y axis around the primary display's height is its own inverse.
    /// `minX`, `maxY`, `width` and `height` are all derived from the standardized
    /// rect, so a rect with a negative size is normalized rather than mirrored wrongly.
    private static func mirrorVertically(_ rect: CGRect, aroundHeight height: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
