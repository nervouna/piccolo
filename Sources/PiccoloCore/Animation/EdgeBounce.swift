import CoreGraphics
import Foundation

/// The frames a window passes through when it bounces towards a side and back, the answer of a Swap
/// Window press that finds no window on that side.
///
/// Pure arithmetic, like ``FrameInterpolation``: the animator in `PiccoloSystem` asks for the frame at
/// the progress the clock says and sends the window what changed.
public enum EdgeBounce {
    /// How far the window goes out, in points.
    public static let amplitude: CGFloat = 16

    /// How long the bounce takes, in seconds, whatever the speed of the window animation.
    public static let duration: TimeInterval = 0.2

    /// How far out the window is at `progress`, in whole points.
    ///
    /// It goes out along the ease-out cubic of ``FrameInterpolation/easeOut(_:)`` for the first half,
    /// `amplitude × easeOut(2t)`, and comes back along the ease-in cubic for the second,
    /// `amplitude × (1 − easeIn(2t − 1))` with `easeIn(u) = u³`. So it is exactly 0 at progress 0 and 1,
    /// and exactly ``amplitude`` at 0.5. The progress is held to `0...1`; a value that is not a number
    /// counts as 0. The result is rounded with the one rounding rule of Piccolo (a half rounds up).
    public static func offset(at progress: Double) -> CGFloat {
        let t = clamped(progress)
        let depth: Double
        if t <= 0.5 {
            depth = FrameInterpolation.easeOut(2 * t)
        } else {
            let u = 2 * t - 1
            depth = 1 - u * u * u
        }
        return EdgeRounding.round(amplitude * CGFloat(depth))
    }

    /// The frame at `progress` of a bounce of `start` towards `direction`.
    ///
    /// `left`, `right` and `down` move the whole frame by ``offset(at:)`` towards smaller x, larger x
    /// and larger y; the size stays. `up` squashes instead: the top edge stays and the bottom edge
    /// moves up by the offset, so the height shrinks by it, because macOS keeps windows below the menu
    /// bar and would not let a window go further up.
    ///
    /// At progress 0 and 1 the result is exactly `start`, whatever its edges are.
    public static func frame(from start: CGRect, towards direction: Direction, progress: Double) -> CGRect {
        let d = offset(at: progress)
        guard d != 0 else { return start }
        var frame = start
        switch direction {
        case .left: frame.origin.x -= d
        case .right: frame.origin.x += d
        case .down: frame.origin.y += d
        case .up: frame.size.height -= d
        }
        return frame
    }

    private static func clamped(_ progress: Double) -> Double {
        if progress.isNaN { return 0 }
        return min(max(progress, 0), 1)
    }
}
