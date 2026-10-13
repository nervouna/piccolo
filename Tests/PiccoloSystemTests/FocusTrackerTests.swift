import Foundation
import Testing
import os

import PiccoloCore

@testable import PiccoloSystem

/// An event source that the test fires by hand.
private final class FakeEvents: FocusEventSource, @unchecked Sendable {
    private let handler = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)
    private let starts = OSAllocatedUnfairLock(initialState: 0)

    var startCount: Int { starts.withLock { $0 } }

    func start(onChange: @escaping @Sendable () -> Void) {
        starts.withLock { $0 += 1 }
        handler.withLock { $0 = onChange }
    }

    /// Reports a change, as the system would.
    func fire() {
        handler.withLock { $0 }?()
    }
}

/// The window that has the focus, which the test changes.
private final class Focus: @unchecked Sendable {
    private let current = OSAllocatedUnfairLock<WindowID?>(initialState: nil)
    private let looks = OSAllocatedUnfairLock(initialState: 0)

    var lookCount: Int { looks.withLock { $0 } }

    func set(_ number: UInt32?) {
        current.withLock { $0 = number.map { WindowID(rawValue: $0) } }
    }

    func read() -> WindowID? {
        looks.withLock { $0 += 1 }
        return current.withLock { $0 }
    }
}

private func id(_ number: UInt32) -> WindowID { WindowID(rawValue: number) }

@Suite("FocusTracker")
struct FocusTrackerTests {
    private func tracker(
        _ events: FakeEvents, _ focus: Focus, capacity: Int = 256
    ) -> FocusTracker {
        FocusTracker(source: events, focusedWindow: { focus.read() }, capacity: capacity)
    }

    @Test("nothing is recorded until the tracker starts")
    func idleBeforeStart() {
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(FakeEvents(), focus)

        tracked.settle()

        #expect(tracked.history.order.isEmpty)
        #expect(focus.lookCount == 0)
    }

    @Test("it records the focused window at start")
    func recordsAtStart() {
        let focus = Focus()
        focus.set(7)
        let tracked = tracker(FakeEvents(), focus)

        tracked.start()
        tracked.settle()

        #expect(tracked.history.order == [id(7)])
    }

    @Test("a change event records the window that has the focus now")
    func recordsOnEvent() {
        let events = FakeEvents()
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(events, focus)
        tracked.start()
        tracked.settle()

        for number: UInt32 in [2, 3, 4] {
            focus.set(number)
            events.fire()
            tracked.settle()
        }

        #expect(tracked.history.order == [4, 3, 2, 1].map(id))
    }

    @Test("a window focused again moves to the front")
    func refocus() {
        let events = FakeEvents()
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(events, focus)
        tracked.start()
        tracked.settle()

        for number: UInt32 in [2, 3, 1] {
            focus.set(number)
            events.fire()
            tracked.settle()
        }

        #expect(tracked.history.order == [1, 3, 2].map(id))
    }

    @Test("events that find the same window change nothing")
    func repeatedEvents() {
        let events = FakeEvents()
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(events, focus)
        tracked.start()
        tracked.settle()
        focus.set(2)

        for _ in 0..<5 { events.fire() }
        tracked.settle()

        #expect(tracked.history.order == [2, 1].map(id))
    }

    @Test("an event with no focused window leaves the history alone")
    func noFocusedWindow() {
        let events = FakeEvents()
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(events, focus)
        tracked.start()
        tracked.settle()

        focus.set(nil)
        events.fire()
        tracked.settle()

        #expect(tracked.history.order == [id(1)])
    }

    @Test("starting twice listens once and looks once")
    func startIsIdempotent() {
        let events = FakeEvents()
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(events, focus)

        tracked.start()
        tracked.start()
        tracked.settle()

        #expect(events.startCount == 1)
        #expect(focus.lookCount == 1)
    }

    @Test("starts from several threads listen once")
    func concurrentStart() async {
        let events = FakeEvents()
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(events, focus)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { tracked.start() }
            }
        }
        tracked.settle()

        #expect(events.startCount == 1)
        #expect(focus.lookCount == 1)
    }

    @Test("events from several threads are all handled, and the history stays consistent")
    func concurrentEvents() async {
        let events = FakeEvents()
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(events, focus)
        tracked.start()
        tracked.settle()
        focus.set(2)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    events.fire()
                    _ = tracked.history
                }
            }
        }
        tracked.settle()

        #expect(tracked.history.order == [2, 1].map(id))
    }

    @Test("the history forgets the oldest windows beyond its capacity")
    func capacity() {
        let events = FakeEvents()
        let focus = Focus()
        let tracked = tracker(events, focus, capacity: 3)
        tracked.start()

        for number: UInt32 in 1...5 {
            focus.set(number)
            events.fire()
            tracked.settle()
        }

        #expect(tracked.history.order == [5, 4, 3].map(id))
    }

    @Test("the history read earlier is a snapshot")
    func snapshot() {
        let events = FakeEvents()
        let focus = Focus()
        focus.set(1)
        let tracked = tracker(events, focus)
        tracked.start()
        tracked.settle()

        let before = tracked.history
        focus.set(2)
        events.fire()
        tracked.settle()

        #expect(before.order == [id(1)])
        #expect(tracked.history.order == [2, 1].map(id))
    }
}
