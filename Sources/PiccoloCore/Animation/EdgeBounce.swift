import CoreGraphics
import Foundation

/// The frames a window passes through when it bounces towards a side and back, the answer of a Swap
/// Window press that finds no window on that side.
///
/// The motion is a damped spring: the window darts out ``amplitude`` points, comes back past its start
/// by about 2 points, and settles, in ``duration`` seconds.
///
/// Pure arithmetic, like ``FrameInterpolation``: the animator in `PiccoloSystem` asks for the frame at
/// the progress the clock says and sends the window what changed.
public enum EdgeBounce {
    /// How far the window goes out, in points: the height of the first peak of the spring.
    public static let amplitude: CGFloat = 16

    /// How long the bounce takes, in seconds, whatever the speed of the window animation.
    public static let duration: TimeInterval = 0.42

    /// The period of the spring's swing, in seconds.
    private static let period: TimeInterval = 0.26

    /// The time constant of the damping, in seconds: the swing shrinks to 1/e of its size in this time.
    private static let decay: TimeInterval = 0.07

    /// The angular frequency of the swing, 2π / period, in radians a second.
    private static let omega = 2 * Double.pi / period

    /// The elapsed time of the first peak, s* = atan(ωτ) / ω, about 0.043 s: where the derivative of the
    /// spring is zero.
    private static let peakTime = atan(omega * decay) / omega

    /// The value of e^(−s/τ) · sin(ωs) at the first peak. Dividing the spring by it makes the peak exactly
    /// ``amplitude``.
    private static let peakValue = exp(-peakTime / decay) * sin(omega * peakTime)

    /// How far out the window is at `progress`, in whole points.
    ///
    /// At elapsed time `s = progress × duration` the window is at `amplitude × e^(−s/τ) × sin(2πs/T) / m`,
    /// with `T` = 0.26 s, `τ` = 0.07 s and `m` the same product at its first peak. The first peak is 16 pt
    /// at about 0.043 s; the swing then crosses the start at 0.13 s and goes to an overshoot of about
    /// 2.5 points, about 0.17 s, which rounds to 2 points on the other side of the start; after that the
    /// swings are under half a point, so the window is at rest from 0.26 s on.
    ///
    /// The result is rounded with the one rounding rule of Piccolo (a half rounds up). The progress is held
    /// to `0...1`, and a value that is not a number counts as 0. The offset is exactly 0 at progress 0 and
    /// at progress 1, whatever the formula gives there, so the last tick puts the window back on its start
    /// frame. A negative offset is the overshoot, past the start.
    public static func offset(at progress: Double) -> CGFloat {
        let t = clamped(progress)
        guard t > 0, t < 1 else { return 0 }
        let s = t * duration
        let spring = exp(-s / decay) * sin(omega * s) / peakValue
        return EdgeRounding.round(amplitude * CGFloat(spring))
    }

    /// The frame at `progress` of a bounce of `start` towards `direction`.
    ///
    /// `left`, `right` and `down` move the whole frame by ``offset(at:)`` towards smaller x, larger x and
    /// larger y; the size stays. `up` squashes instead: the top edge stays and the bottom edge moves up by
    /// the offset, so the height shrinks by it, because macOS keeps windows below the menu bar and would
    /// not let a window go further up. A negative offset (the overshoot) moves the frame the other way,
    /// past the start: `left` to the right of it, `right` to the left, `down` above it, and `up` grows the
    /// height, with the top edge still in place.
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
