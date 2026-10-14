import CoreGraphics

/// The frames a window passes through on its way from one frame to another.
///
/// Pure arithmetic: the animator in `PiccoloSystem` asks for the frame at the progress the clock
/// says and sends it to the window.
public enum FrameInterpolation {
    /// The ease-out cubic, `1 - (1 - t)^3`: fast at the start, slowing down towards the end.
    ///
    /// `t` is held to `0...1`; a value that is not a number counts as 0. The result is exactly 0 at
    /// 0 and exactly 1 at 1.
    public static func easeOut(_ progress: Double) -> Double {
        let t = clamped(progress)
        let rest = 1 - t
        return 1 - rest * rest * rest
    }

    /// The frame at `progress` on the way from `start` to `target`.
    ///
    /// Each of the four edges (left, top, right, bottom) moves from its place in `start` to its place
    /// in `target` along ``easeOut(_:)`` and is rounded to a whole point with the one rounding rule of
    /// Piccolo (a half rounds up). Interpolating edges rather than origin and size has two effects that
    /// matter: two windows that share an edge in `start` and in `target` share it at every progress, so
    /// neighbours never overlap and leave no gap on the way; and every edge moves one way only.
    ///
    /// At progress 0 the result is exactly `start`, and at 1 exactly `target`, whatever their
    /// edges are, so that an animation begins and ends where the caller says.
    public static func frame(from start: CGRect, to target: CGRect, progress: Double) -> CGRect {
        let t = clamped(progress)
        if t <= 0 { return start }
        if t >= 1 { return target }

        let eased = CGFloat(easeOut(t))
        func edge(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
            EdgeRounding.round(from + (to - from) * eased)
        }
        let minX = edge(start.minX, target.minX)
        let minY = edge(start.minY, target.minY)
        let maxX = edge(start.maxX, target.maxX)
        let maxY = edge(start.maxY, target.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func clamped(_ progress: Double) -> Double {
        if progress.isNaN { return 0 }
        return min(max(progress, 0), 1)
    }
}
