import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// A `swapWindow` press that finds no neighbour, with an animator on a fake clock: the focused window
/// bounces towards that side and back, or the outcome says that it did not.
private struct BounceRig {
    let clock = FakeClock()
    let desk = Desk()

    /// A group of `count` windows in `rows` by `columns` cells, arranged without animation, then the
    /// animator and the clock switched on. Window `focus` has the focus.
    init(
        count: Int = 2, rows: Int = 1, columns: Int = 2, focus: UInt32 = 1, animator: Bool = true
    ) throws {
        desk.openWindows(count)
        try desk.arrange(count: count, rows: rows, columns: columns)
        desk.focused = focus
        desk.clock = clock
        if animator { desk.executor.animator = WindowAnimator(clock) }
    }

    /// Presses the swap key with this animation.
    func swap(_ direction: Direction, _ animation: WindowAnimation = .fast) throws -> SwapOutcome {
        try desk.swap(direction, settings: ActionSettings(animation: animation))
    }

    /// The changes the windows took since `mark`.
    func changes(since mark: Int) -> [Desk.Change] {
        Array(desk.trace[mark...])
    }
}

/// How far out a frame is from `start` towards `direction`, in points: 0 at the start.
private func depth(of frame: CGRect, from start: CGRect, towards direction: Direction) -> CGFloat {
    switch direction {
    case .left: start.minX - frame.minX
    case .right: frame.minX - start.minX
    case .down: frame.minY - start.minY
    case .up: start.maxY - frame.maxY
    }
}

@Suite("ActionExecutor: swapWindow bounces at the edge")
struct SwapBounceTests {
    @Test("with Fast and no neighbour on the left the window goes out up to 16 pt and comes back to the start frame")
    func bouncesLeft() throws {
        let rig = try BounceRig()
        let start = try rig.desk.frame(of: 1)
        let groups = rig.desk.executor.linkedGroups
        let records = rig.desk.executor.windowRecords.map(\.record)
        let mark = rig.desk.trace.count

        let outcome = try rig.swap(.left, .fast)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: true)))
        let moves = rig.changes(since: mark)
        #expect(!moves.isEmpty)
        // Only the focused window, only its position, and its size and y never change.
        #expect(moves.allSatisfy { $0.window == 1 && $0.kind == .position })
        #expect(moves.allSatisfy { $0.frame.size == start.size && $0.frame.minY == start.minY })
        let depths = moves.map { depth(of: $0.frame, from: start, towards: .left) }
        #expect(depths.max() == 16, "the deepest point of the bounce is \(depths.max() ?? -1) pt")
        #expect(depths.allSatisfy { (0...16).contains($0) }, "\(depths)")
        // The window goes out to the left of the display (no shift into the visible frame) and comes back.
        #expect(moves.map(\.frame.minX).min() == start.minX - 16)
        #expect(moves.last?.frame == start, "the last frame is \(String(describing: moves.last?.frame)), the start is \(start)")
        #expect(try rig.desk.frame(of: 1) == start)
        // Nothing else changed: the other window, the group and the records.
        #expect(try rig.desk.frame(of: 2) == groups[0].group.frames[1])
        #expect(rig.desk.executor.linkedGroups == groups)
        #expect(rig.desk.executor.windowRecords.map(\.record) == records)
    }

    @Test(
        "the bounce lasts 0.2 s whatever the animation speed",
        arguments: [WindowAnimation.fast, .medium, .slow])
    func duration(animation: WindowAnimation) throws {
        let rig = try BounceRig()

        let outcome = try rig.swap(.left, animation)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: true)))
        #expect(abs(rig.clock.elapsed - 0.2) < 1e-9, "\(animation) took \(rig.clock.elapsed) s")
    }

    @Test(
        "the same frames whatever the animation speed",
        arguments: [WindowAnimation.medium, .slow])
    func sameFramesForEverySpeed(animation: WindowAnimation) throws {
        let fast = try BounceRig()
        let other = try BounceRig()
        let fastMark = fast.desk.trace.count
        let otherMark = other.desk.trace.count

        _ = try fast.swap(.left, .fast)
        _ = try other.swap(.left, animation)

        #expect(
            fast.changes(since: fastMark).map(\.frame) == other.changes(since: otherMark).map(\.frame))
    }

    @Test("it ticks at most 60 times a second, and the last tick is at the end of the 0.2 s")
    func ticks() throws {
        let rig = try BounceRig()
        let mark = rig.desk.trace.count

        _ = try rig.swap(.left)

        let times = rig.changes(since: mark).map(\.time)
        #expect(times.count <= 12, "\(times.count) changes in 0.2 s")
        #expect(times.count >= 8, "only \(times.count) changes in 0.2 s")
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later - earlier >= 1.0 / 60 - 1e-9, "ticks \(later - earlier) s apart")
        }
        #expect(abs((times.last ?? 0) - (FakeClock.origin + 0.2)) < 1e-9, "the last change is at \(times.last ?? 0)")
    }

    @Test("it goes out and comes back: the depth rises to the middle and falls after it")
    func shape() throws {
        let rig = try BounceRig()
        let start = try rig.desk.frame(of: 1)
        let mark = rig.desk.trace.count

        _ = try rig.swap(.left)

        let depths = rig.changes(since: mark).map { depth(of: $0.frame, from: start, towards: .left) }
        let peak = try #require(depths.firstIndex(of: 16))
        let rising = Array(depths[...peak])
        let falling = Array(depths[peak...])
        #expect(rising == rising.sorted(), "\(depths)")
        #expect(falling == falling.sorted(by: >), "\(depths)")
        #expect(depths.first.map { $0 > 0 } == true)
        #expect(depths.last == 0)
    }

    @Test("every key without a neighbour bounces towards its side: right, down, and up by squashing")
    func everyDirection() throws {
        // Window 1 is the left cell and 2 the right one of a single row: no neighbour on the outer side,
        // above or below.
        let cases: [(focus: UInt32, direction: Direction)] = [
            (1, .left), (2, .right), (1, .down), (2, .down), (1, .up), (2, .up),
        ]
        for (focus, direction) in cases {
            let rig = try BounceRig(focus: focus)
            let start = try rig.desk.frame(of: focus)
            let mark = rig.desk.trace.count

            let outcome = try rig.swap(direction)

            #expect(outcome == .nothingToDo(.noNeighbour(bounced: true)), "window \(focus) \(direction)")
            let moves = rig.changes(since: mark)
            let depths = moves.map { depth(of: $0.frame, from: start, towards: direction) }
            #expect(depths.max() == 16, "window \(focus) \(direction): \(depths)")
            #expect(moves.last?.frame == start, "window \(focus) \(direction)")
            #expect(try rig.desk.frame(of: focus) == start, "window \(focus) \(direction)")
        }
    }

    @Test("up sends sizes only and keeps the origin: the top edge stays and the bottom edge comes up by 16 pt")
    func upSquashes() throws {
        let rig = try BounceRig()
        let start = try rig.desk.frame(of: 1)
        let mark = rig.desk.trace.count

        let outcome = try rig.swap(.up)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: true)))
        let moves = rig.changes(since: mark)
        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy { $0.window == 1 && $0.kind == .size }, "\(moves.map(\.kind))")
        #expect(moves.allSatisfy { $0.frame.origin == start.origin && $0.frame.width == start.width })
        #expect(moves.map(\.frame.height).min() == start.height - 16)
        #expect(moves.allSatisfy { $0.frame.height <= start.height })
        #expect(moves.last?.frame == start)
    }

    @Test("down and right send positions only, and keep the size")
    func positionsOnly() throws {
        for (focus, direction) in [(UInt32(2), Direction.right), (1, .down)] {
            let rig = try BounceRig(focus: focus)
            let start = try rig.desk.frame(of: focus)
            let mark = rig.desk.trace.count

            _ = try rig.swap(direction)

            let moves = rig.changes(since: mark)
            #expect(!moves.isEmpty && moves.allSatisfy { $0.kind == .position && $0.frame.size == start.size })
        }
    }

    @Test("a window nudged by a point from its cell comes back to where it was, not to the cell")
    func startIsTheWindowsOwnFrame() throws {
        let rig = try BounceRig()
        let fake = rig.desk.window(1).fake
        fake.origin = CGPoint(x: fake.origin.x + 1, y: fake.origin.y + 1)
        let start = try rig.desk.frame(of: 1)
        let groups = rig.desk.executor.linkedGroups

        let outcome = try rig.swap(.left)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: true)))
        #expect(try rig.desk.frame(of: 1) == start)
        #expect(rig.desk.executor.linkedGroups == groups, "the group is neither recorded again nor dissolved")
    }

    @Test("the group stays linked: a divider move works after the bounce")
    func stillLinked() throws {
        let rig = try BounceRig()
        _ = try rig.swap(.left)

        let moved = try rig.desk.moved(.right)

        #expect(moved.windows.count == 2)
        #expect(rig.desk.executor.linkedGroups.count == 1)
    }

    @Test("a window that refuses to be resized still bounces left: only its position changes")
    func fixedSizeWindowBouncesLeft() throws {
        let rig = try BounceRig()
        rig.desk.window(1).fake.isFixedSize = true
        let start = try rig.desk.frame(of: 1)
        let mark = rig.desk.trace.count

        let outcome = try rig.swap(.left)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: true)))
        #expect(rig.changes(since: mark).allSatisfy { $0.kind == .position })
        #expect(try rig.desk.frame(of: 1) == start)
    }
}

@Suite("ActionExecutor: swapWindow does not bounce")
struct SwapNoBounceTests {
    @Test("with animation Off no frame is sent, the clock is not touched and the outcome is not bounced")
    func off() throws {
        let rig = try BounceRig()
        let before = try rig.desk.frames(2)
        let mark = rig.desk.log.count

        let outcome = try rig.swap(.left, .off)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: false)))
        #expect(rig.desk.calls(since: mark).isEmpty)
        #expect(rig.clock.sleeps.isEmpty && rig.clock.elapsed == 0)
        #expect(try rig.desk.frames(2) == before)
    }

    @Test("an executor without an animator does not bounce, whatever the animation is")
    func noAnimator() throws {
        // Window 1 has no neighbour left, above or below; window 2 has none on the right.
        let cases: [(focus: UInt32, direction: Direction)] = [(1, .left), (1, .up), (1, .down), (2, .right)]
        for (focus, direction) in cases {
            let rig = try BounceRig(focus: focus, animator: false)
            let mark = rig.desk.log.count

            let outcome = try rig.swap(direction, .slow)

            #expect(outcome == .nothingToDo(.noNeighbour(bounced: false)), "window \(focus) \(direction)")
            #expect(rig.desk.calls(since: mark).isEmpty, "window \(focus) \(direction)")
            #expect(rig.clock.sleeps.isEmpty, "window \(focus) \(direction)")
        }
    }

    @Test("up on a window whose size is not settable does not bounce, and nothing moves")
    func upOnFixedSizeWindow() throws {
        let rig = try BounceRig()
        rig.desk.window(1).fake.isFixedSize = true
        let start = try rig.desk.frame(of: 1)
        let groups = rig.desk.executor.linkedGroups
        let mark = rig.desk.trace.count

        let outcome = try rig.swap(.up)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: false)))
        #expect(rig.changes(since: mark).isEmpty)
        #expect(try rig.desk.frame(of: 1) == start)
        #expect(rig.desk.executor.linkedGroups == groups)
    }

    @Test("a window whose position fails during the bounce is not bounced, and is put back where that works")
    func throwsOnce() throws {
        let rig = try BounceRig()
        let fake = rig.desk.window(1).fake
        let start = try rig.desk.frame(of: 1)
        let groups = rig.desk.executor.linkedGroups
        let positionCalls = fake.calls.filter { $0 == "position" }.count
        // The third position change of the bounce fails; the call that puts the window back works.
        fake.failPositionOnCalls = [positionCalls + 3]

        let outcome = try rig.swap(.left)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: false)))
        let now = try rig.desk.frame(of: 1)
        #expect(now == start, "the window was left at \(now)")
        #expect(rig.desk.executor.linkedGroups == groups)
        // The bounce was abandoned: no more ticks after the failure.
        #expect(rig.clock.elapsed < 0.2)
    }

    @Test("a window that keeps failing is not bounced, and the run does not throw")
    func throwsForGood() throws {
        let rig = try BounceRig()
        let fake = rig.desk.window(1).fake
        let groups = rig.desk.executor.linkedGroups
        let positionCalls = fake.calls.filter { $0 == "position" }.count
        fake.failPositionWith = .accessibility(operation: "set AXPosition", code: -25204)
        fake.failPositionFromCall = positionCalls + 3

        let outcome = try rig.swap(.left)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: false)))
        // It could not be put back, so the group is left for the next press to validate.
        #expect(rig.desk.executor.linkedGroups == groups)
    }

    @Test("a size that fails during the squash is not bounced, and the size is put back")
    func upThrowsOnce() throws {
        let rig = try BounceRig()
        let fake = rig.desk.window(1).fake
        let start = try rig.desk.frame(of: 1)
        let sizeCalls = fake.calls.filter { $0 == "size" }.count
        fake.failSizeOnCalls = [sizeCalls + 3]

        let outcome = try rig.swap(.up)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: false)))
        #expect(try rig.desk.frame(of: 1) == start)
    }

    @Test("a window that is gone is not bounced, and the run does not throw")
    func windowGone() throws {
        let rig = try BounceRig()
        let fake = rig.desk.window(1).fake
        fake.failPositionWith = .windowGone

        let outcome = try rig.swap(.left)

        #expect(outcome == .nothingToDo(.noNeighbour(bounced: false)))
    }

    @Test("planning never bounces: the destinations of a swap without a neighbour are empty and nothing moves")
    func destinationsDoNotBounce() throws {
        let rig = try BounceRig()
        let before = try rig.desk.frames(2)
        let mark = rig.desk.log.count

        let destinations = try rig.desk.executor.destinations(
            for: .swapWindow(.left), settings: ActionSettings(animation: .slow))

        #expect(destinations.isEmpty)
        #expect(rig.desk.calls(since: mark).isEmpty)
        #expect(rig.clock.sleeps.isEmpty && rig.clock.elapsed == 0)
        #expect(try rig.desk.frames(2) == before)
    }

    @Test("a swap that finds a neighbour is not a bounce: the windows trade cells")
    func swapIsNotABounce() throws {
        let rig = try BounceRig()

        let outcome = try rig.swap(.right)

        guard case .swapped = outcome else {
            Issue.record("expected the windows to swap, got \(outcome)")
            return
        }
    }

    @Test("the other no-op reasons do not bounce: no group, no focused window")
    func otherReasons() throws {
        let rig = try BounceRig()
        rig.desk.focused = nil
        #expect(try rig.swap(.left) == .nothingToDo(.noFocusedWindow))

        let ungrouped = Desk()
        ungrouped.openWindows(2)
        ungrouped.clock = rig.clock
        ungrouped.executor.animator = WindowAnimator(rig.clock)
        #expect(try ungrouped.swap(.left) == .nothingToDo(.noGroup))
        #expect(ungrouped.trace.isEmpty)
        #expect(rig.clock.sleeps.isEmpty)
    }
}
