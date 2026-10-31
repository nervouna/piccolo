import CoreGraphics
import PiccoloCore

extension ActionExecutor {
    /// Moves `windows` towards their targets in small steps, over the duration of
    /// `settings.animation`, before the caller places them for good with ``FrameSetter``. Does nothing
    /// when the animation is off or the executor has no animator, so that the path without animation is
    /// the one that runs.
    ///
    /// - Parameters:
    ///   - displays: The displays the windows are on, to leave a window that changes display alone.
    ///   - ordered: See ``WindowAnimator/animate(_:duration:displays:ordered:)``.
    func glide(
        _ windows: [AnimatedWindow], settings: ActionSettings, displays: [Display], ordered: Bool = false
    ) {
        guard settings.animation != .off, let animator, !windows.isEmpty else { return }
        animator.animate(
            windows, duration: settings.animation.duration, displays: displays, ordered: ordered)
    }

    /// Bounces `window` towards `direction` and back over ``EdgeBounce/duration``, whatever the speed of
    /// `settings.animation`, and says whether it did. Does nothing, and answers `false`, when the
    /// animation is off or the executor has no animator, so that the path without animation is the one
    /// that runs. See ``WindowAnimator/bounce(_:from:towards:duration:)`` for the rest.
    ///
    /// - Parameters:
    ///   - start: The frame the window is at, and is put back at.
    func bounce(
        _ window: any WindowFrameAccess, from start: CGRect, towards direction: Direction,
        settings: ActionSettings
    ) -> Bool {
        guard settings.animation != .off, let animator else { return false }
        return animator.bounce(window, from: start, towards: direction)
    }
}
