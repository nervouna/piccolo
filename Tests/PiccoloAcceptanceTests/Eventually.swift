import Foundation

/// What one look at the system found.
enum Observation<Value> {
    /// The condition holds; `Value` is what the caller wanted to learn.
    case satisfied(Value)
    /// It does not hold yet. The text says what was seen instead, and ends up in the
    /// failure message if the condition never holds.
    case unsatisfied(String)
}

/// Looks at the system again and again until the condition holds.
///
/// Window changes reach the window server asynchronously, so a measurement right after
/// a command can still show the old state. Acceptance tests therefore poll for the
/// effect instead of sleeping for a fixed time: this returns as soon as the condition
/// holds and fails after `timeout`, saying what was awaited and what was last seen.
///
/// The probe always runs at least once, and once more at the deadline.
///
/// - Parameters:
///   - goal: What is being waited for, phrased to complete "timed out waiting for ...".
///   - timeout: How long to keep looking, in seconds.
///   - interval: The pause between looks, in seconds.
///   - probe: Looks once. A thrown error ends the wait at once.
func eventually<Value>(
    _ goal: @autoclosure () -> String,
    timeout: TimeInterval = 5,
    interval: TimeInterval = 0.05,
    _ probe: () throws -> Observation<Value>
) async throws -> Value {
    let clock = ContinuousClock()
    let start = clock.now
    var lastSeen = "nothing observed"
    while true {
        switch try probe() {
        case .satisfied(let value):
            return value
        case .unsatisfied(let seen):
            lastSeen = seen
        }
        let elapsed = start.duration(to: clock.now)
        if elapsed >= .seconds(timeout) {
            throw AcceptanceFailure(
                "timed out after \(String(format: "%.1f", timeout)) s waiting for \(goal()); last observed: \(lastSeen)"
            )
        }
        try await Task.sleep(for: .seconds(interval))
    }
}
