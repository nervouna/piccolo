import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// `WindowAnimator.bounce` against a fake clock and a clocked window: how the bounce is ticked, and what
/// becomes of the window when a call fails or the calls are slow.
private struct BounceStage {
    static let start = CGRect(x: 100, y: 80, width: 600, height: 400)

    let clock = FakeClock()
    let journal = Journal()
    let window: ClockedWindow

    init(at frame: CGRect = BounceStage.start) {
        window = ClockedWindow("W", at: frame, clock: clock, journal: journal)
    }

    var animator: WindowAnimator { WindowAnimator(clock) }

    @discardableResult
    func bounce(_ direction: Direction, duration: TimeInterval = EdgeBounce.duration) -> Bool {
        animator.bounce(window, from: BounceStage.start, towards: direction, duration: duration)
    }
}

@Suite("WindowAnimator: the bounce")
struct WindowAnimatorBounceTests {
    @Test("it plays the frames of EdgeBounce at the progress of the clock, the last tick at progress 1 on the start frame")
    func framesAndEnd() {
        let stage = BounceStage()

        let bounced = stage.bounce(.right)

        #expect(bounced)
        let frames = stage.journal.changes.map(\.frame)
        #expect(!frames.isEmpty)
        // Every frame is one EdgeBounce gives for some progress, and the last is the start frame.
        let possible = (0...100).map { EdgeBounce.frame(from: BounceStage.start, towards: .right, progress: Double($0) / 100) }
        #expect(frames.allSatisfy { possible.contains($0) })
        #expect(frames.last == BounceStage.start)
        #expect(frames.map(\.minX).max() == BounceStage.start.minX + 16)
        #expect(stage.window.frameValue == BounceStage.start)
        #expect(abs(stage.clock.elapsed - 0.2) < 1e-9)
    }

    @Test("it ticks at most 60 times a second, the first tick one tick after the start")
    func tickRate() {
        let stage = BounceStage()

        stage.bounce(.left)

        let times = stage.journal.changes.map(\.time)
        #expect(times.count <= 12)
        #expect(abs((times.first ?? 0) - (FakeClock.origin + 1.0 / 60)) < 1e-9)
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later - earlier >= 1.0 / 60 - 1e-9)
        }
    }

    @Test("a tick sends only what changed: the position for left, right and down, the size for up")
    func onlyWhatChanges() {
        for direction in [Direction.left, .right, .down] {
            let stage = BounceStage()
            stage.bounce(direction)
            #expect(stage.journal.changes.allSatisfy { $0.kind == .position }, "\(direction)")
        }
        let up = BounceStage()
        up.bounce(.up)
        #expect(up.journal.changes.allSatisfy { $0.kind == .size })
        #expect(up.journal.changes.allSatisfy { $0.frame.origin == BounceStage.start.origin })
    }

    @Test("slow calls drop frames and never stretch the bounce: the end still lands on the start frame")
    func slowCalls() {
        let stage = BounceStage()
        stage.window.cost = 0.03

        let bounced = stage.bounce(.left)

        #expect(bounced)
        #expect(stage.journal.changes.count < 12, "\(stage.journal.changes.count) changes")
        #expect(stage.journal.changes.last?.frame == BounceStage.start)
        #expect(stage.window.frameValue == BounceStage.start)
        // A tick that starts before the end can take its time, but no further tick follows the last.
        #expect(stage.clock.elapsed < 0.2 + 2 * 0.03 + 1e-9, "took \(stage.clock.elapsed) s")
    }

    @Test("sleeps that run long drop frames too, and the last tick is still at progress 1")
    func oversleeping() {
        let stage = BounceStage()
        stage.clock.oversleep = 0.02

        let bounced = stage.bounce(.down)

        #expect(bounced)
        #expect(stage.journal.changes.last?.frame == BounceStage.start)
    }

    @Test("a duration of zero or less bounces nothing and does not touch the clock", arguments: [0.0, -1.0])
    func noDuration(duration: TimeInterval) {
        let stage = BounceStage()

        let bounced = stage.bounce(.left, duration: duration)

        #expect(!bounced)
        #expect(stage.window.attempts == 0)
        #expect(stage.clock.sleeps.isEmpty && stage.clock.elapsed == 0)
    }

    @Test("a call that fails ends the bounce, and the window is put back where that works")
    func failureOnce() {
        let stage = BounceStage()
        stage.window.failOnAttempts = [3]

        let bounced = stage.bounce(.left)

        #expect(!bounced)
        #expect(stage.window.frameValue == BounceStage.start)
        #expect(stage.clock.elapsed < 0.2, "the bounce went on after the failure: \(stage.clock.elapsed) s")
    }

    @Test("a window that keeps failing is left where it is, and the bounce is not played")
    func failureForGood() {
        let stage = BounceStage()
        stage.window.failFromChange = 3

        let bounced = stage.bounce(.left)

        #expect(!bounced)
        // Two changes worked; the third failed, and so did the call that tried to put the window back.
        #expect(stage.window.attempts == 4)
        #expect(stage.window.frameValue != BounceStage.start)
    }

    @Test("a size that is not settable ends the squash at once, with nothing to put back")
    func upWithoutSize() {
        let stage = BounceStage()
        stage.window.sizeError = .attributeNotSettable("AXSize")

        let bounced = stage.bounce(.up)

        #expect(!bounced)
        #expect(stage.window.attempts == 1)
        #expect(stage.journal.changes.isEmpty)
        #expect(stage.window.frameValue == BounceStage.start)
    }

    @Test("a size that is not settable does not matter for the other directions")
    func sidewaysWithoutSize() {
        let stage = BounceStage()
        stage.window.sizeError = .attributeNotSettable("AXSize")

        let bounced = stage.bounce(.right)

        #expect(bounced)
        #expect(stage.window.frameValue == BounceStage.start)
    }
}
