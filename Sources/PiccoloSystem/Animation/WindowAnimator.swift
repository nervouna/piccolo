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

        let interval = 1 / Self.ticksPerSecond
        let begin = clock.now()
        let end = begin + duration
        var previousTick = begin
        while !active.isEmpty {
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
            previousTick = tickStart
            if isLast { break }
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
