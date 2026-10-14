import Foundation

/// Time for the animator: a reading of a clock that only runs forward, and a way to wait. Both are
/// injected, so that tests run an animation on a fake clock without waiting for it.
public struct AnimationClock: Sendable {
    /// Seconds on a monotonic clock. Only differences mean anything.
    public var now: @Sendable () -> TimeInterval
    /// Blocks the calling thread for `seconds`.
    public var sleep: @Sendable (_ seconds: TimeInterval) -> Void

    public init(
        now: @escaping @Sendable () -> TimeInterval,
        sleep: @escaping @Sendable (_ seconds: TimeInterval) -> Void
    ) {
        self.now = now
        self.sleep = sleep
    }

    /// The system's uptime clock and `Thread.sleep`.
    public static let system = AnimationClock(
        now: { ProcessInfo.processInfo.systemUptime },
        sleep: { Thread.sleep(forTimeInterval: $0) })
}
