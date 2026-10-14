import CoreGraphics
import Foundation

import PiccoloCore

@testable import PiccoloSystem

/// A clock that only moves when the code under test sleeps or a fake window "takes time", so that
/// the animator runs instantly and deterministically.
///
/// The origin is not zero, to catch code that mixes absolute and relative times.
final class FakeClock: @unchecked Sendable {
    static let origin: TimeInterval = 100

    private(set) var time: TimeInterval = FakeClock.origin
    /// Every sleep the code asked for, in order.
    private(set) var sleeps: [TimeInterval] = []
    /// How much longer than asked every sleep takes, as a real one does.
    var oversleep: TimeInterval = 0

    var clock: AnimationClock {
        AnimationClock(
            now: { [self] in time },
            sleep: { [self] seconds in
                sleeps.append(seconds)
                time += seconds + oversleep
            })
    }

    func advance(by seconds: TimeInterval) {
        time += seconds
    }

    /// Seconds since the clock was created.
    var elapsed: TimeInterval { time - Self.origin }
}

/// What the fake windows did, in the order it happened, across all windows.
final class Journal: @unchecked Sendable {
    struct Change: Equatable {
        enum Kind: String { case size, position }
        var window: String
        var kind: Kind
        /// The time of the call, before it took any time.
        var time: TimeInterval
        /// The window's frame after the change.
        var frame: CGRect
    }

    private(set) var changes: [Change] = []

    func record(_ change: Change) { changes.append(change) }

    func changes(of window: String) -> [Change] {
        changes.filter { $0.window == window }
    }
}

/// A window that records every change with the time it happened, can take time to answer, and can be
/// made to fail. It does not clamp or move anything by itself: it takes what it is given.
final class ClockedWindow: WindowFrameAccess, @unchecked Sendable {
    let name: String
    let clock: FakeClock
    let journal: Journal
    private(set) var frameValue: CGRect

    /// How long each change takes on the clock.
    var cost: TimeInterval = 0
    /// Every `setSize` fails with this error.
    var sizeError: WindowError?
    /// Every `setPosition` fails with this error.
    var positionError: WindowError?
    /// The call numbered this (counting size and position changes together, from 1) and every later
    /// one fail with a plain Accessibility error.
    var failFromChange: Int?
    /// Only the calls numbered like this fail (counting from 1), each with a plain Accessibility error.
    var failOnAttempts: Set<Int> = []
    /// How many changes were tried, those that failed too.
    private(set) var attempts = 0

    init(_ name: String, at frame: CGRect, clock: FakeClock, journal: Journal) {
        self.name = name
        self.clock = clock
        self.journal = journal
        self.frameValue = frame
    }

    func frame() throws -> CGRect { frameValue }

    func setSize(_ size: CGSize) throws {
        try change(.size, error: sizeError) { frameValue.size = size }
    }

    func setPosition(_ origin: CGPoint) throws {
        try change(.position, error: positionError) { frameValue.origin = origin }
    }

    private func change(_ kind: Journal.Change.Kind, error: WindowError?, _ apply: () -> Void) throws {
        attempts += 1
        let time = clock.time
        clock.advance(by: cost)
        if let error { throw error }
        if failOnAttempts.contains(attempts) || (failFromChange.map { attempts >= $0 } ?? false) {
            throw WindowError.accessibility(operation: "set \(kind.rawValue)", code: -25204)
        }
        apply()
        journal.record(Journal.Change(window: name, kind: kind, time: time, frame: frameValue))
    }
}

extension WindowAnimator {
    /// A window animator over `clock`.
    init(_ clock: FakeClock) {
        self.init(clock: clock.clock)
    }
}

extension Sequence where Element: Equatable {
    /// The elements without repeats, in order of first appearance (`CGRect` is not `Hashable` before
    /// macOS 15, so a `Set` will not do).
    var distinct: [Element] {
        var seen: [Element] = []
        for element in self where !seen.contains(element) { seen.append(element) }
        return seen
    }
}
