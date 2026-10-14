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
}
