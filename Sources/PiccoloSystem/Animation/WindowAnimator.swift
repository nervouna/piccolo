import CoreGraphics
import Foundation
import PiccoloCore

/// A window that takes part in an animation, with the frame it is at and the frame it goes to.
public struct AnimatedWindow {
    public var window: any WindowFrameAccess
    /// The frame the window has now.
    public var start: CGRect
    /// The frame the animation ends at.
    public var target: CGRect

    public init(window: any WindowFrameAccess, start: CGRect, target: CGRect) {
        self.window = window
        self.start = start
        self.target = target
    }
}

/// Moves windows to their new frames in small steps, over a duration, on one clock.
///
/// The animator only does the part in between: it sends each window the frame `FrameInterpolation`
/// gives for the moment, and ends with every window at its target frame (or dropped from the
/// animation). What it does not do is the final placement: the caller applies each window's target
/// with ``FrameSetter/apply(_:to:within:)`` afterwards, as it does without animation, so that the
/// achieved frames, the shift into the visible frame and the errors are the ones of an action without
/// animation.
///
/// It is synchronous and blocks the calling thread between ticks, like the actions it belongs to.
/// All windows share one clock: they start together, show the same progress at every tick and arrive
/// together.
///
/// - Ticks start at least 1/60 s apart. Progress is the time since the start over the duration,
///   not the number of ticks, so that slow Accessibility calls drop frames instead of stretching the
///   animation. The first tick comes one tick after the start, and the last is at progress 1, sending
///   every window its target frame, at the end of the duration (or at the first tick after it when
///   the calls were late).
/// - A tick sends a window only what changed: the size, the position, or both. When the window's
///   left or top edge moves towards the top-left corner, the position goes first; otherwise the size
///   goes first. In both cases the window stays within the union of its old and its new frame between
///   the two calls, so it neither covers the space of a neighbour that has not moved yet nor hangs out
///   beyond the screen edge it is at.
/// - A window whose size cannot be set (`WindowError/attributeNotSettable`) animates its position
///   only. A window whose change fails otherwise, or whose tick takes longer than the whole duration,
///   is dropped from the animation: it gets nothing more, and the caller's final placement deals with
///   it. The other windows carry on, unless `ordered` is set.
///
/// ``bounce(_:from:towards:duration:)`` plays the bounce of a Swap Window press with no neighbour on the
/// same ticks.
public struct WindowAnimator: Sendable {
    /// The most ticks per second.
    public static let ticksPerSecond = 60.0

    /// How much earlier than a whole tick the end may be for a tick to still count as a regular one.
    private static let epsilon = 1e-6

    public var clock: AnimationClock

    public init(clock: AnimationClock = .system) {
        self.clock = clock
    }

    /// Plays the animation of `windows` to their targets and returns when the last tick is done.
    ///
    /// - Parameters:
    ///   - windows: The windows with their start and target frames. Each tick visits them in this
    ///     order. A window that is not animated (see ``AnimationEligibility``) is skipped.
    ///   - duration: Seconds. Zero or less animates nothing and does not touch the clock.
    ///   - displays: The displays, to tell the windows that change display from those that do not.
    ///   - ordered: Whether each window leaves room for the ones after it, as in a divider move where
    ///     the windows that shrink come first. A dropped window then ends the animation for all
    ///     windows behind it too, so that none of them grows into space that was not freed.
    public func animate(
        _ windows: [AnimatedWindow], duration: TimeInterval, displays: [Display], ordered: Bool = false
    ) {
        guard duration > 0 else { return }
        var glides = windows.compactMap { window -> Glide? in
            AnimationEligibility.isAnimated(from: window.start, to: window.target, displays: displays)
                ? Glide(window) : nil
        }
        var active = Array(glides.indices)
        guard !active.isEmpty else { return }

        ticks(for: duration) { progress in
            var position = 0
            while position < active.count {
                let began = clock.now()
                var dropped = false
                do {
                    try glides[active[position]].send(progress: progress)
                } catch {
                    dropped = true
                }
                if !dropped, clock.now() - began > duration { dropped = true }
                if dropped {
                    active.removeSubrange(position..<(ordered ? active.count : position + 1))
                } else {
                    position += 1
                }
            }
            return !active.isEmpty
        }
    }

    /// Plays the bounce of one window towards `direction` and back, and returns whether it did.
    ///
    /// The window goes through the frames of ``EdgeBounce`` on the same ticks as an animation: at most
    /// 60 a second, progress taken from the clock, and the last tick at progress 1, which is the start
    /// frame, so that the window ends exactly where it began. A tick sends only what changed: the
    /// position for `left`, `right` and `down`, the size for `up`. The window is neither shifted into a
    /// visible frame nor read back, and a tick that is slow is not a reason to drop the window: the
    /// ticks that follow are fewer, and the last one still comes.
    ///
    /// A call that throws ends the bounce at once, and the window is put back at `start` with the calls
    /// that still work. That is how a window whose size is not settable answers `up`: its first tick
    /// throws, and nothing has changed yet. The result is then `false`.
    ///
    /// - Parameters:
    ///   - window: The window to bounce.
    ///   - start: The frame it is at, and comes back to.
    ///   - direction: The side to bounce towards.
    ///   - duration: Seconds. Zero or less bounces nothing and does not touch the clock.
    /// - Returns: `true` when the window went out and came back, `false` when there was no bounce, or it
    ///   was cut short.
    public func bounce(
        _ window: any WindowFrameAccess, from start: CGRect, towards direction: Direction,
        duration: TimeInterval = EdgeBounce.duration
    ) -> Bool {
        guard duration > 0 else { return false }
        // What the window has, as far as the animator knows: the start, then what it was sent.
        var sent = start
        var failed = false
        ticks(for: duration) { progress in
            let frame = EdgeBounce.frame(from: start, towards: direction, progress: progress)
            do {
                if frame.origin != sent.origin {
                    try window.setPosition(frame.origin)
                    sent.origin = frame.origin
                }
                if frame.size != sent.size {
                    try window.setSize(frame.size)
                    sent.size = frame.size
                }
                return true
            } catch {
                failed = true
                return false
            }
        }
        guard failed else { return true }
        // Back to the start frame, as far as the window lets us.
        if sent.origin != start.origin { try? window.setPosition(start.origin) }
        if sent.size != start.size { try? window.setSize(start.size) }
        return false
    }

    /// Calls `tick` with the progress of an animation of `duration` seconds, once per tick, until the
    /// last tick (at progress 1) or until `tick` answers `false`. Zero or less never gets here.
    ///
    /// Ticks start at least 1/60 s apart; the progress is the time since the start over the duration,
    /// and the last tick waits for the end of the duration, or comes at the first tick after it when
    /// the calls were late.
    private func ticks(for duration: TimeInterval, _ tick: (_ progress: Double) -> Bool) {
        let interval = 1 / Self.ticksPerSecond
        let begin = clock.now()
        let end = begin + duration
        var previousTick = begin
        while true {
            // The next tick is one interval after the last one. When the end falls before the tick
            // after that, this is the last tick, and it waits for the end.
            var wake = previousTick + interval
            var isLast = false
            if end - wake < interval - Self.epsilon {
                wake = max(end, wake)
                isLast = true
            }
            let wait = wake - clock.now()
            if wait > 0 { clock.sleep(wait) }

            let tickStart = clock.now()
            isLast = isLast || tickStart >= end
            let progress = isLast ? 1 : (tickStart - begin) / duration

            let more = tick(progress)
            previousTick = tickStart
            if isLast || !more { break }
        }
    }
}

/// The state of one window during an animation: what it was last sent.
private struct Glide {
    let window: any WindowFrameAccess
    let start: CGRect
    let target: CGRect
    /// The frame the window has, as far as the animator knows: the start, then what it sent.
    var sent: CGRect
    /// False once the window has said it cannot be resized.
    var canResize = true

    init(_ animated: AnimatedWindow) {
        window = animated.window
        start = animated.start
        target = animated.target
        sent = animated.start
    }

    /// Sends the window the frame for `progress`: only the size, only the position or both.
    mutating func send(progress: Double) throws {
        let frame = FrameInterpolation.frame(from: start, to: target, progress: progress)
        if frame.minX < sent.minX || frame.minY < sent.minY {
            try sendPosition(frame.origin)
            try sendSize(frame.size)
        } else {
            try sendSize(frame.size)
            try sendPosition(frame.origin)
        }
    }

    private mutating func sendSize(_ size: CGSize) throws {
        guard canResize, size != sent.size else { return }
        do {
            try window.setSize(size)
        } catch WindowError.attributeNotSettable {
            canResize = false
            return
        }
        sent.size = size
    }

    private mutating func sendPosition(_ origin: CGPoint) throws {
        guard origin != sent.origin else { return }
        try window.setPosition(origin)
        sent.origin = origin
    }
}
