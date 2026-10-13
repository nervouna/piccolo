import CoreGraphics

/// Turns a `FrameSpec` into the frame a window gets on a screen.
public enum FrameResolver {
    /// The target frame for `spec`, in the canonical space.
    ///
    /// - Presets with a fraction and custom rects resolve edge by edge against `visibleFrame`.
    /// - `.preset(.center)` keeps the size of `currentFrame`, capped to `visibleFrame` in each
    ///   dimension, and centres the result in `visibleFrame`.
    public static func frame(
        for spec: FrameSpec,
        visibleFrame: CGRect,
        currentFrame: CGRect
    ) -> CGRect {
        switch spec {
        case .custom(let rect):
            return fractionalFrame(rect, in: visibleFrame)
        case .preset(let preset):
            // `.center` is the only preset without a fraction.
            guard let rect = preset.fractionalRect else {
                return centeredFrame(size: currentFrame.size, in: visibleFrame)
            }
            return fractionalFrame(rect, in: visibleFrame)
        }
    }

    /// Resolves fractions of `visible` with the edge rounding rule.
    static func fractionalFrame(_ rect: FractionalRect, in visible: CGRect) -> CGRect {
        let fx = CGFloat(rect.x)
        let fy = CGFloat(rect.y)
        let fw = CGFloat(rect.width)
        let fh = CGFloat(rect.height)
        return roundEdges(
            minX: visible.minX + fx * visible.width,
            maxX: visible.minX + (fx + fw) * visible.width,
            minY: visible.minY + fy * visible.height,
            maxY: visible.minY + (fy + fh) * visible.height)
    }

    /// Centres a frame of `size` in `visible`, capping the size to `visible` in each dimension.
    private static func centeredFrame(size: CGSize, in visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        // The origin is rounded, then clamped. For integral inputs the clamp changes nothing.
        // It keeps the result inside `visible` when `visible` has fractional edges.
        let originX = visible.minX + (visible.width - width) / 2
        let originY = visible.minY + (visible.height - height) / 2
        let x = clamp(originX.rounded(.toNearestOrAwayFromZero), from: visible.minX, to: visible.maxX - width)
        let y = clamp(originY.rounded(.toNearestOrAwayFromZero), from: visible.minY, to: visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Rounds each edge to the nearest integer, ties away from zero, independently of the others.
    ///
    /// The width and height are the differences of the rounded edges. Neighbouring frames that share
    /// an unrounded edge therefore share the rounded edge too: no gaps and no overlaps.
    static func roundEdges(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGRect {
        let left = minX.rounded(.toNearestOrAwayFromZero)
        let right = maxX.rounded(.toNearestOrAwayFromZero)
        let top = minY.rounded(.toNearestOrAwayFromZero)
        let bottom = maxY.rounded(.toNearestOrAwayFromZero)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func clamp(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
