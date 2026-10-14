import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// The animator against a fake clock and fake windows. Nothing here sleeps for real: the clock moves
/// when the animator sleeps and when a fake window "takes time".
private struct Stage {
    static let left = Display(
        frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 970))
    static let right = Display(
        frame: CGRect(x: 1600, y: 0, width: 1200, height: 800),
        visibleFrame: CGRect(x: 1600, y: 30, width: 1200, height: 770))
    static let displays = [left, right]

    /// Where a typical test window starts, and where it goes: a move that also resizes, on the left display.
    static let start = CGRect(x: 100, y: 100, width: 600, height: 400)
    static let target = CGRect(x: 700, y: 300, width: 800, height: 500)

    let clock = FakeClock()
    let journal = Journal()

    var animator: WindowAnimator { WindowAnimator(clock) }

    func window(_ name: String, at frame: CGRect = Stage.start) -> ClockedWindow {
        ClockedWindow(name, at: frame, clock: clock, journal: journal)
    }

    func run(
        _ windows: [(window: ClockedWindow, start: CGRect, target: CGRect)], duration: TimeInterval,
        ordered: Bool = false
    ) {
        animator.animate(
            windows.map { AnimatedWindow(window: $0.window, start: $0.start, target: $0.target) },
            duration: duration, displays: Self.displays, ordered: ordered)
    }

    /// Animates one window from `Stage.start` to `Stage.target`.
    func run(_ window: ClockedWindow, to target: CGRect = Stage.target, duration: TimeInterval) {
        run([(window, Stage.start, target)], duration: duration)
    }

    /// The times at which some window was changed, once per tick (the changes of one window in one tick
    /// happen at the same time when the fake window takes no time, so this is for zero-cost windows).
    var tickTimes: [TimeInterval] {
        var times: [TimeInterval] = []
        for change in journal.changes where times.last != change.time {
            times.append(change.time)
        }
        return times
    }
}

@Suite("WindowAnimator: when nothing is animated")
struct WindowAnimatorOffTests {
    @Test("a duration of zero changes nothing and never touches the clock", arguments: [0.0, -1.0])
    func off(duration: TimeInterval) {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, duration: duration)

        #expect(stage.journal.changes.isEmpty)
        #expect(window.attempts == 0)
        #expect(stage.clock.sleeps.isEmpty)
        #expect(stage.clock.elapsed == 0)
    }

    @Test("no window at all: nothing happens")
    func noWindows() {
        let stage = Stage()

        stage.run([], duration: 0.4)

        #expect(stage.clock.sleeps.isEmpty && stage.clock.elapsed == 0)
    }

    @Test("a window that is already at its target is left alone, and nothing waits for it")
    func equalFrames() {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, to: Stage.start, duration: 0.4)

        #expect(window.attempts == 0)
        #expect(stage.clock.sleeps.isEmpty && stage.clock.elapsed == 0)
    }

    @Test("a window within a point of its target is left alone")
    func nearlyEqualFrames() {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, to: Stage.start.offsetBy(dx: 1, dy: -1), duration: 0.4)

        #expect(window.attempts == 0)
        #expect(stage.clock.elapsed == 0)
    }

    @Test("a window that goes to the other display is left alone")
    func otherDisplay() {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, to: CGRect(x: 1800, y: 100, width: 600, height: 400), duration: 0.4)

        #expect(window.attempts == 0)
        #expect(stage.clock.elapsed == 0)
    }

    @Test("the windows that qualify are animated while the others are not")
    func mixed() {
        let stage = Stage()
        let moving = stage.window("moving")
        let still = stage.window("still")
        let leaving = stage.window("leaving")

        stage.run(
            [
                (moving, Stage.start, Stage.target),
                (still, Stage.start, Stage.start),
                (leaving, Stage.start, CGRect(x: 1800, y: 100, width: 600, height: 400)),
            ], duration: 0.15)

        #expect(!stage.journal.changes(of: "moving").isEmpty)
        #expect(still.attempts == 0 && leaving.attempts == 0)
    }
}

@Suite("WindowAnimator: ticks and progress")
struct WindowAnimatorTickTests {
    @Test("the last tick is the target, exactly, and it comes when the duration is over")
    func lastTickIsTheTarget() {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, duration: 0.4)

        #expect(window.frameValue == Stage.target)
        #expect(stage.journal.changes.last?.frame == Stage.target)
        #expect(abs(stage.clock.elapsed - 0.4) < 1e-9, "the animation took \(stage.clock.elapsed) s")
    }

    @Test(
        "the last tick is the target for the durations of the settings, and for others",
        arguments: [0.15, 0.25, 0.4, 0.1, 0.037, 1.0])
    func lastTickForEveryDuration(duration: TimeInterval) {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, duration: duration)

        #expect(window.frameValue == Stage.target)
        #expect(abs(stage.clock.elapsed - duration) < 1e-9, "\(duration) s took \(stage.clock.elapsed) s")
    }

    @Test("it ticks at most 60 times a second, and with fast calls it does tick that often")
    func tickRate() {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, duration: 1)

        // With calls that take no time, a tick is one sleep.
        let sleeps = stage.clock.sleeps
        #expect(sleeps.count <= 60, "\(sleeps.count) ticks in one second")
        #expect(sleeps.count >= 59, "only \(sleeps.count) ticks in one second")
        for (index, sleep) in sleeps.enumerated() {
            #expect(sleep >= 1.0 / 60 - 1e-9, "tick \(index) came \(sleep) s after the one before")
        }
    }

    @Test(
        "the settings tick 60 times a second: 9, 15 and 24 ticks",
        arguments: [(0.15, 9), (0.25, 15), (0.4, 24)])
    func tickCountOfTheSettings(duration: TimeInterval, ticks: Int) {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, duration: duration)

        #expect(stage.clock.sleeps.count == ticks)
    }

    @Test("a sleep that takes longer than asked lowers the rate, never raises it")
    func oversleeping() {
        let stage = Stage()
        stage.clock.oversleep = 0.004
        let window = stage.window("A")

        stage.run(window, duration: 0.4)

        #expect(stage.clock.sleeps.count < 24)
        for sleep in stage.clock.sleeps {
            #expect(sleep + 0.004 >= 1.0 / 60 - 1e-9)
        }
        #expect(window.frameValue == Stage.target)
    }

    @Test("progress is time: slow calls drop frames instead of stretching the animation")
    func progressFollowsTheClock() {
        let stage = Stage()
        let window = stage.window("A")
        window.cost = 0.05  // a tick (size and position) takes 0.1 s, six times the length of a frame
        let duration = 0.4

        stage.run(window, duration: duration)

        let changes = stage.journal.changes
        #expect(changes.count.isMultiple(of: 2), "every tick changes the size and the position: \(changes.count) changes")
        let ticks = stride(from: 0, to: changes.count, by: 2).map { (changes[$0], changes[$0 + 1]) }
        #expect(ticks.count < 24, "\(ticks.count) ticks: slow calls must drop frames")
        #expect(ticks.count >= 3)
        for (index, (first, second)) in ticks.enumerated() {
            let isLast = index == ticks.count - 1
            let progress = isLast ? 1 : (first.time - FakeClock.origin) / duration
            let expected = FrameInterpolation.frame(from: Stage.start, to: Stage.target, progress: progress)
            #expect(second.frame == expected, "tick \(index) at \(first.time - FakeClock.origin) s shows \(second.frame), progress \(progress) is \(expected)")
        }
        // The animation is not stretched: the last tick starts within one tick of the end.
        let lastStart = (ticks.last?.0.time ?? 0) - FakeClock.origin
        #expect(lastStart >= duration && lastStart <= duration + 0.1 + 1e-9, "the last tick started at \(lastStart) s")
        #expect(window.frameValue == Stage.target)
    }

    @Test("every tick shows a frame further along than the one before, up to the target")
    func framesAdvance() {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, duration: 0.4)

        var previousDistance = CGFloat.infinity
        for change in stage.journal.changes where change.kind == .position {
            let distance = abs(change.frame.minX - Stage.target.minX) + abs(change.frame.minY - Stage.target.minY)
            #expect(distance <= previousDistance)
            previousDistance = distance
        }
        let origins = stage.journal.changes.filter { $0.kind == .position }.map(\.frame.origin).distinct
        #expect(origins.count >= 10, "the window showed \(origins.count) different positions")
    }
}

@Suite("WindowAnimator: what a tick sends")
struct WindowAnimatorSendTests {
    @Test("only the attributes that change are sent: a window that only moves gets no size")
    func moveOnly() {
        let stage = Stage()
        let window = stage.window("A")

        stage.run(window, to: Stage.start.offsetBy(dx: 500, dy: 100), duration: 0.15)

        #expect(!stage.journal.changes.isEmpty)
        #expect(stage.journal.changes.allSatisfy { $0.kind == .position })
        #expect(window.frameValue == Stage.start.offsetBy(dx: 500, dy: 100))
    }

    @Test("only the attributes that change are sent: a window that only grows gets no position")
    func resizeOnly() {
        let stage = Stage()
        let window = stage.window("A")
        let target = CGRect(origin: Stage.start.origin, size: CGSize(width: 900, height: 700))

        stage.run(window, to: target, duration: 0.15)

        #expect(!stage.journal.changes.isEmpty)
        #expect(stage.journal.changes.allSatisfy { $0.kind == .size })
        #expect(window.frameValue == target)
    }

    @Test("a window that moves and shrinks away from the top-left gets its size first, so it never sticks out")
    func shrinkingFromTheLeftSizesFirst() {
        let stage = Stage()
        let window = stage.window("A")
        let target = CGRect(x: 400, y: 100, width: 300, height: 400)  // the left edge moves right

        stage.run(window, to: target, duration: 0.15)

        let first = Array(stage.journal.changes.prefix(2))
        #expect(first.map(\.kind) == [.size, .position], "\(first)")
        // Between the two calls the window lies within the old and the new frame together.
        let hull = Stage.start.union(target)
        #expect(stage.journal.changes.allSatisfy { hull.contains($0.frame) })
    }

    @Test("a window that grows towards the top-left gets its position first, so it never sticks out")
    func growingTowardsTheLeftMovesFirst() {
        let stage = Stage()
        let window = stage.window("A")
        let target = CGRect(x: 0, y: 40, width: 700, height: 460)  // the left and top edges move away

        stage.run(window, to: target, duration: 0.15)

        let first = Array(stage.journal.changes.prefix(2))
        #expect(first.map(\.kind) == [.position, .size], "\(first)")
        let hull = Stage.start.union(target)
        #expect(stage.journal.changes.allSatisfy { hull.contains($0.frame) })
    }

    @Test("each tick visits the windows in the order given")
    func orderOfWindows() {
        let stage = Stage()
        let names = ["A", "B", "C"]
        let windows = names.map { stage.window($0) }

        stage.run(windows.map { ($0, Stage.start, Stage.target) }, duration: 0.15)

        // The windows all do the same, so every tick has all of them: A, B, C, A, B, C, ...
        var visits: [String] = []
        for change in stage.journal.changes where visits.last != change.window {
            visits.append(change.window)
        }
        #expect(visits.count >= 3 * names.count)
        #expect(visits.count.isMultiple(of: names.count))
        for (index, name) in visits.enumerated() {
            #expect(name == names[index % names.count], "visit \(index) was \(name): \(visits)")
        }
    }

    @Test("windows travel together: at each tick they show the frame of the same progress")
    func sharedClock() {
        let stage = Stage()
        let a = stage.window("A")
        let bStart = CGRect(x: 100, y: 600, width: 600, height: 300)
        let b = stage.window("B", at: bStart)
        let bTarget = CGRect(x: 900, y: 600, width: 700, height: 300)
        let duration = 0.4

        stage.animator.animate(
            [
                AnimatedWindow(window: a, start: Stage.start, target: Stage.target),
                AnimatedWindow(window: b, start: bStart, target: bTarget),
            ], duration: duration, displays: Stage.displays)

        let tickTimes = stage.tickTimes
        #expect(tickTimes.count >= 15)
        for time in tickTimes {
            let progress = time - FakeClock.origin >= duration - 1e-9 ? 1 : (time - FakeClock.origin) / duration
            for (name, start, target) in [("A", Stage.start, Stage.target), ("B", bStart, bTarget)] {
                // What the window shows after the last change of this tick (a window that already
                // reached its target has no change in the late ticks).
                guard let shown = stage.journal.changes(of: name).last(where: { $0.time <= time }) else { continue }
                let expected = FrameInterpolation.frame(from: start, to: target, progress: progress)
                #expect(shown.frame == expected, "\(name) at \(time - FakeClock.origin) s shows \(shown.frame), progress \(progress) is \(expected)")
            }
        }
        #expect(a.frameValue == Stage.target && b.frameValue == bTarget)
    }
}

@Suite("WindowAnimator: windows that fail or are slow")
struct WindowAnimatorFailureTests {
    @Test("a window whose change throws is dropped and not tried again, the others finish")
    func throwingWindowIsDropped() {
        let stage = Stage()
        let failing = stage.window("failing")
        failing.failFromChange = 3  // the first tick works, the second fails on its first call
        let healthy = stage.window("healthy")

        stage.run(
            [(failing, Stage.start, Stage.target), (healthy, Stage.start, Stage.target)], duration: 0.4)

        #expect(failing.attempts == 3, "the failing window was tried \(failing.attempts) times")
        #expect(healthy.frameValue == Stage.target)
        #expect(stage.journal.changes(of: "healthy").count > 10)
        #expect(failing.frameValue != Stage.target)
    }

    @Test("a window whose position throws is dropped too, after the size that went through")
    func throwingPosition() {
        let stage = Stage()
        let failing = stage.window("failing")
        failing.positionError = .windowGone
        let healthy = stage.window("healthy")

        stage.run(
            [(failing, Stage.start, Stage.target), (healthy, Stage.start, Stage.target)], duration: 0.4)

        #expect(failing.attempts <= 2, "tried \(failing.attempts) times")
        #expect(healthy.frameValue == Stage.target)
    }

    @Test("a window that takes longer than the whole duration to answer is dropped after that tick")
    func slowWindowIsDropped() {
        let stage = Stage()
        let slow = stage.window("slow")
        slow.cost = 1  // its first tick takes two seconds, the animation lasts 0.4
        let healthy = stage.window("healthy")

        stage.run(
            [(slow, Stage.start, Stage.target), (healthy, Stage.start, Stage.target)], duration: 0.4)

        #expect(slow.attempts == 2, "the slow window was tried \(slow.attempts) times")
        #expect(healthy.frameValue == Stage.target)
    }

    @Test("a window whose tick takes almost the whole duration is not dropped")
    func windowAtTheLimit() {
        let stage = Stage()
        let window = stage.window("A")
        window.cost = 0.19  // size and position: 0.38 s, almost the whole duration, but not longer

        stage.run(window, duration: 0.4)

        #expect(window.attempts >= 2)
        #expect(window.frameValue == Stage.target)
    }

    @Test("a window whose size cannot be set animates its position only")
    func fixedSizeWindow() {
        let stage = Stage()
        let fixed = stage.window("fixed")
        fixed.sizeError = .attributeNotSettable("AXSize")
        let target = CGRect(x: 700, y: 300, width: 800, height: 500)

        stage.run(fixed, to: target, duration: 0.4)

        let positions = stage.journal.changes(of: "fixed")
        #expect(positions.allSatisfy { $0.kind == .position })
        #expect(positions.count >= 10, "the position was sent \(positions.count) times")
        #expect(fixed.frameValue.origin == target.origin)
        #expect(fixed.frameValue.size == Stage.start.size)
        // One failed attempt at the size, then it is not tried again.
        #expect(fixed.attempts == positions.count + 1, "\(fixed.attempts) attempts, \(positions.count) positions")
    }

    @Test("when every window is dropped the animation ends there and then")
    func everyWindowDropped() {
        let stage = Stage()
        let failing = stage.window("failing")
        failing.failFromChange = 1

        stage.run(failing, duration: 0.4)

        #expect(stage.clock.sleeps.count == 1, "it kept ticking: \(stage.clock.sleeps)")
        #expect(stage.clock.elapsed < 0.05)
    }

    @Test("windows that depend on each other's order: after a dropped window the ones behind it stop")
    func orderedStopsTheWindowsBehind() {
        let stage = Stage()
        let shrinking = stage.window("shrinking")
        shrinking.failFromChange = 3
        let growing = stage.window("growing")

        stage.run(
            [(shrinking, Stage.start, Stage.target), (growing, Stage.start, Stage.target)], duration: 0.4,
            ordered: true)

        // The first tick reached both windows. At the second, the first window failed, and the second,
        // which would have grown into the space it leaves, was not sent anything.
        #expect(shrinking.attempts == 3)
        #expect(stage.journal.changes(of: "growing").count == 2, "\(stage.journal.changes(of: "growing"))")
        #expect(growing.frameValue != Stage.target)
    }

    @Test("without the order the windows are independent: the others carry on")
    func unorderedCarriesOn() {
        let stage = Stage()
        let failing = stage.window("failing")
        failing.failFromChange = 3
        let other = stage.window("other")

        stage.run([(failing, Stage.start, Stage.target), (other, Stage.start, Stage.target)], duration: 0.4)

        #expect(other.frameValue == Stage.target)
    }

    @Test("with the order, a window that is only slow also stops the windows behind it")
    func orderedStopsBehindASlowWindow() {
        let stage = Stage()
        let slow = stage.window("slow")
        slow.cost = 1
        let behind = stage.window("behind")

        stage.run([(slow, Stage.start, Stage.target), (behind, Stage.start, Stage.target)], duration: 0.4, ordered: true)

        #expect(slow.attempts == 2)
        #expect(behind.attempts == 0, "the window behind the slow one was sent \(behind.attempts) changes")
    }
}
