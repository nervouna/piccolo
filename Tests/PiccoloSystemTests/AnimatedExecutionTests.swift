import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// The executor with an animator, against fake windows and a fake clock: what is animated, with which
/// duration, and that the windows end up exactly where they end up without it.

// MARK: - A single window

private enum Rig {
    static let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 0, y: 30, width: 1550, height: 970))
    static let secondary = Display(
        frame: CGRect(x: -1200, y: 200, width: 1200, height: 800),
        visibleFrame: CGRect(x: -1200, y: 230, width: 1200, height: 770))
    static let both = [primary, secondary]

    static let onPrimary = CGRect(x: 100, y: 100, width: 600, height: 400)
}

/// One run of an action on a clocked window, with or without an animator.
private struct Run {
    let clock = FakeClock()
    let journal = Journal()
    let window: ClockedWindow
    let executor: ActionExecutor

    init(animator: Bool = true, at frame: CGRect = Rig.onPrimary, displays: [Display] = Rig.both) {
        let clock = clock
        let window = ClockedWindow("W", at: frame, clock: clock, journal: journal)
        self.window = window
        executor = ActionExecutor(
            window: { window }, displays: { displays }, animator: animator ? WindowAnimator(clock) : nil)
    }

    func run(_ action: Action, _ animation: WindowAnimation) throws -> ActionOutcome {
        try executor.run(action, settings: ActionSettings(animation: animation))
    }

    /// What the window was sent, without the times.
    var steps: [Step] { journal.changes.map { Step(kind: $0.kind, frame: $0.frame) } }
}

private struct Step: Equatable {
    var kind: Journal.Change.Kind
    var frame: CGRect
}

@Suite("ActionExecutor with an animator: one window")
struct AnimatedSingleWindowTests {
    @Test("placeWindow glides to the frame, then ends exactly as it does without animation")
    func placeWindowGlides() throws {
        let animated = Run()
        let plain = Run()

        let outcome = try animated.run(.placeWindow(.preset(.leftHalf)), .fast)
        let reference = try plain.run(.placeWindow(.preset(.leftHalf)), .off)

        #expect(outcome == reference)
        #expect(animated.window.frameValue == plain.window.frameValue)
        // Without animation: the three steps of FrameSetter, and no waiting.
        #expect(plain.steps.map(\.kind) == [.size, .position, .size])
        #expect(plain.clock.sleeps.isEmpty)
        // With it: the same three steps come last, after a number of intermediate frames.
        #expect(animated.steps.suffix(plain.steps.count).map(\.kind) == plain.steps.map(\.kind))
        #expect(animated.steps.last?.frame == plain.steps.last?.frame)
        let intermediate = animated.steps.dropLast(plain.steps.count)
        let target = plain.window.frameValue
        let frames = intermediate.map(\.frame).distinct.filter { $0 != target && $0 != Rig.onPrimary }
        #expect(frames.count >= 3, "only \(frames.count) frames between the start and the target")
    }

    @Test(
        "the duration of the setting is the length of the glide",
        arguments: [(WindowAnimation.fast, 0.15), (.medium, 0.25), (.slow, 0.4)])
    func duration(animation: WindowAnimation, seconds: TimeInterval) throws {
        let run = Run()

        _ = try run.run(.placeWindow(.preset(.rightHalf)), animation)

        #expect(abs(run.clock.elapsed - seconds) < 1e-9, "\(animation) took \(run.clock.elapsed) s")
    }

    @Test("off makes no intermediate change and does not touch the clock")
    func off() throws {
        let run = Run()

        _ = try run.run(.placeWindow(.preset(.leftHalf)), .off)

        #expect(run.steps.count == 3)
        #expect(run.clock.sleeps.isEmpty && run.clock.elapsed == 0)
    }

    @Test("an executor without an animator never animates, whatever the settings say")
    func noAnimator() throws {
        let run = Run(animator: false)

        _ = try run.run(.placeWindow(.preset(.leftHalf)), .slow)

        #expect(run.steps.count == 3)
        #expect(run.clock.sleeps.isEmpty)
    }

    @Test("the default settings are animated: Fast")
    func defaultSettingsAnimate() throws {
        let run = Run()

        _ = try run.executor.run(.placeWindow(.preset(.leftHalf)))

        #expect(run.steps.count > 3)
        #expect(abs(run.clock.elapsed - WindowAnimation.fast.duration) < 1e-9)
    }

    @Test("a window that is already at its target is not animated")
    func alreadyThere() throws {
        // The visible frame of the primary display is the target of maximize.
        let run = Run(at: Rig.primary.visibleFrame)

        let outcome = try run.run(.placeWindow(.preset(.maximize)), .slow)

        #expect(outcome == .placed(target: Rig.primary.visibleFrame, achieved: Rig.primary.visibleFrame))
        #expect(run.steps.count == 3)
        #expect(run.clock.sleeps.isEmpty)
    }

    @Test("moveToDisplay to a display where the window would mostly be elsewhere is applied without a glide")
    func moveToAnotherDisplay() throws {
        let animated = Run()
        let plain = Run()

        let outcome = try animated.run(.moveToDisplay(.next), .slow)
        let reference = try plain.run(.moveToDisplay(.next), .off)

        #expect(outcome == reference)
        #expect(animated.steps == plain.steps, "a window cannot be larger than the display it is on, so it jumps")
        #expect(animated.clock.sleeps.isEmpty)
    }

    @Test("nothingToDo is nothing: no glide, no change")
    func nothingToDo() throws {
        let run = Run(displays: [Rig.primary])

        let outcome = try run.run(.moveToDisplay(.next), .slow)

        #expect(outcome == .nothingToDo)
        #expect(run.steps.isEmpty && run.clock.sleeps.isEmpty)
    }

    @Test("a change that fails during the glide only costs the glide: the final apply still places the window")
    func intermediateFailure() throws {
        let animated = Run()
        animated.window.failOnAttempts = [2]  // the position of the first tick
        let plain = Run()

        let outcome = try animated.run(.placeWindow(.preset(.leftHalf)), .fast)
        let reference = try plain.run(.placeWindow(.preset(.leftHalf)), .off)

        #expect(outcome == reference)
        #expect(animated.window.frameValue == plain.window.frameValue)
        #expect(animated.clock.elapsed < 0.05, "the window was dropped, so nothing waits for the duration")
    }

    @Test("a window that cannot be changed makes the run fail as it does without animation")
    func finalFailureIsReported() {
        let animated = Run()
        animated.window.positionError = .windowGone
        let plain = Run()
        plain.window.positionError = .windowGone

        #expect(throws: WindowError.windowGone) {
            try animated.run(.placeWindow(.preset(.leftHalf)), .fast)
        }
        #expect(throws: WindowError.windowGone) {
            try plain.run(.placeWindow(.preset(.leftHalf)), .off)
        }
    }

    @Test("a fixed-size window glides by its position and keeps its size")
    func fixedSize() throws {
        let animated = Run()
        animated.window.sizeError = .attributeNotSettable("AXSize")
        let plain = Run()
        plain.window.sizeError = .attributeNotSettable("AXSize")

        let outcome = try animated.run(.placeWindow(.preset(.leftHalf)), .fast)
        let reference = try plain.run(.placeWindow(.preset(.leftHalf)), .off)

        #expect(outcome == reference)
        #expect(animated.window.frameValue == plain.window.frameValue)
        #expect(animated.window.frameValue.size == Rig.onPrimary.size)
        #expect(animated.steps.count > plain.steps.count)
        #expect(animated.steps.allSatisfy { $0.kind == .position })
    }
}

// MARK: - A grid

@Suite("ActionExecutor with an animator: arrangeGrid")
struct AnimatedArrangeTests {
    private static let grid = GridSpec(count: 3, rows: 2, columns: 2)

    private func makeDesk(animator clock: FakeClock?) -> Desk {
        let desk = Desk()
        desk.openWindows(3)
        if let clock { desk.executor.animator = WindowAnimator(clock) }
        return desk
    }

    @Test("all windows glide together to the same frames as without animation, and the group is the same")
    func sameResult() throws {
        let clock = FakeClock()
        let animated = makeDesk(animator: clock)
        let plain = makeDesk(animator: nil)

        let outcome = try animated.executor.run(
            .arrangeGrid(Self.grid), settings: ActionSettings(animation: .slow))
        let reference = try plain.executor.run(
            .arrangeGrid(Self.grid), settings: ActionSettings(animation: .off))

        #expect(outcome == reference)
        #expect(try animated.frames(3) == plain.frames(3))
        #expect(animated.executor.linkedGroups.map(\.group.frames) == plain.executor.linkedGroups.map(\.group.frames))
        #expect(animated.executor.linkedGroups.count == 1)
    }

    @Test("every window shows intermediate frames, all of them within one duration, then the final apply of today")
    func everyWindowGlides() throws {
        let clock = FakeClock()
        let animated = makeDesk(animator: clock)
        let plain = makeDesk(animator: nil)

        _ = try animated.executor.run(.arrangeGrid(Self.grid), settings: ActionSettings(animation: .slow))
        _ = try plain.executor.run(.arrangeGrid(Self.grid), settings: ActionSettings(animation: .off))

        #expect(abs(clock.elapsed - 0.4) < 1e-9, "three windows took \(clock.elapsed) s: they must share one clock")
        // The last calls are the plain run's, in the same order.
        #expect(Array(animated.log.suffix(plain.log.count)) == plain.log)
        let glide = animated.log.dropLast(plain.log.count)
        for number in 1...3 {
            let calls = glide.filter { $0.hasPrefix("\(number) ") }
            #expect(calls.count > 6, "window \(number) got \(calls.count) intermediate changes")
        }
        // Each tick visits the windows in the order of the cells: size and position of window 1, then 2, then 3.
        #expect(Array(glide.prefix(6).map { $0.split(separator: " ")[0] }) == ["1", "1", "2", "2", "3", "3"], "\(glide.prefix(6))")
    }

    @Test("off with an animator makes no intermediate call at all")
    func off() throws {
        let clock = FakeClock()
        let animated = makeDesk(animator: clock)
        let plain = makeDesk(animator: nil)

        _ = try animated.executor.run(.arrangeGrid(Self.grid), settings: ActionSettings(animation: .off))
        _ = try plain.executor.run(.arrangeGrid(Self.grid), settings: ActionSettings(animation: .off))

        #expect(animated.log == plain.log)
        #expect(clock.sleeps.isEmpty && clock.elapsed == 0)
    }

    @Test("a window that fails during the arrangement is reported as without animation, and the others are placed")
    func failingWindow() throws {
        let clock = FakeClock()
        let animated = makeDesk(animator: clock)
        let plain = makeDesk(animator: nil)
        animated.window(2).fake.failPositionWith = .attributeNotSettable("AXPosition")
        plain.window(2).fake.failPositionWith = .attributeNotSettable("AXPosition")

        let outcome = try animated.executor.run(.arrangeGrid(Self.grid), settings: ActionSettings(animation: .fast))
        let reference = try plain.executor.run(.arrangeGrid(Self.grid), settings: ActionSettings(animation: .off))

        #expect(outcome == reference)
        #expect(try animated.frame(of: 1) == plain.frame(of: 1))
        #expect(try animated.frame(of: 3) == plain.frame(of: 3))
        #expect(animated.executor.linkedGroups.isEmpty && plain.executor.linkedGroups.isEmpty)
    }

    @Test("a window whose start and cell are the same is not animated, the others are")
    func windowAlreadyInItsCell() throws {
        let clock = FakeClock()
        let animated = makeDesk(animator: clock)
        let cells = TileLayout.grid(windowCount: 3, rows: 2, columns: 2).frames(in: DeskRig.primary.visibleFrame)
        // Window 1 takes the top-left cell: put it there first.
        let first = animated.window(1)
        try first.setSize(cells[0].size)
        try first.setPosition(cells[0].origin)
        let mark = animated.log.count

        _ = try animated.executor.run(.arrangeGrid(Self.grid), settings: ActionSettings(animation: .fast))

        let calls = animated.calls(since: mark)
        #expect(calls.filter { $0.hasPrefix("1 ") }.count == 3, "window 1 only gets the final apply: \(calls)")
        #expect(calls.filter { $0.hasPrefix("2 ") }.count > 3)
        #expect(calls.filter { $0.hasPrefix("3 ") }.count > 3)
    }
}

// MARK: - A divider

@Suite("ActionExecutor with an animator: moveDivider")
struct AnimatedDividerTests {
    private static let step = DeskRig.step

    /// A desk with `count` windows arranged in `rows` by `columns` (without animation), then the
    /// animator switched on.
    private func makeDesk(count: Int, rows: Int, columns: Int, clock: FakeClock?) throws -> Desk {
        let desk = Desk()
        desk.openWindows(count)
        try desk.arrange(count: count, rows: rows, columns: columns)
        if let clock { desk.executor.animator = WindowAnimator(clock) }
        return desk
    }

    private func move(_ desk: Desk, _ direction: Direction, _ animation: WindowAnimation) throws -> ActionOutcome {
        try desk.executor.run(
            .moveDivider(direction), settings: ActionSettings(resizeStep: Self.step, animation: animation))
    }

    @Test("the divider glides, and the windows end where they do without animation")
    func sameResult() throws {
        let clock = FakeClock()
        let animated = try makeDesk(count: 2, rows: 1, columns: 2, clock: clock)
        let plain = try makeDesk(count: 2, rows: 1, columns: 2, clock: nil)
        let markAnimated = animated.log.count
        let markPlain = plain.log.count

        let outcome = try move(animated, .right, .slow)
        let reference = try move(plain, .right, .off)

        #expect(outcome == reference)
        #expect(try animated.frames(2) == plain.frames(2))
        #expect(animated.executor.linkedGroups.map(\.group.frames) == plain.executor.linkedGroups.map(\.group.frames))
        #expect(abs(clock.elapsed - 0.4) < 1e-9)
        // The final apply is the plain run's, in the same order, after the glide.
        let plainCalls = plain.calls(since: markPlain)
        let animatedCalls = animated.calls(since: markAnimated)
        #expect(Array(animatedCalls.suffix(plainCalls.count)) == plainCalls)
        #expect(animatedCalls.count > plainCalls.count + 12)
    }

    @Test("in every tick the window that shrinks is sent before the window that grows")
    func shrinkingFirst() throws {
        let clock = FakeClock()
        let desk = try makeDesk(count: 2, rows: 1, columns: 2, clock: clock)
        let plainCalls = 3 * 2  // the final apply of the two windows
        let mark = desk.log.count

        // B (window 2) shrinks and A grows when the divider moves right.
        _ = try move(desk, .right, .slow)

        let glide = desk.calls(since: mark).dropLast(plainCalls)
        var visits: [Substring] = []
        for call in glide {
            let number = call.split(separator: " ")[0]
            if visits.last != number { visits.append(number) }
        }
        #expect(visits.count >= 20)
        for (index, number) in visits.enumerated() {
            #expect(number == (index.isMultiple(of: 2) ? "2" : "1"), "visit \(index): \(visits.prefix(8))")
        }
    }

    @Test("the second round, for a window that refused its size, is applied without a glide")
    func secondRoundIsNotAnimated() throws {
        let clock = FakeClock()
        let animated = try makeDesk(count: 2, rows: 1, columns: 2, clock: clock)
        let plain = try makeDesk(count: 2, rows: 1, columns: 2, clock: nil)
        // B is 600 wide. A move right asks for 540, B cannot be narrower than 560.
        animated.window(2).fake.minimumSize = CGSize(width: 560, height: 100)
        plain.window(2).fake.minimumSize = CGSize(width: 560, height: 100)
        let markAnimated = animated.log.count
        let markPlain = plain.log.count

        let outcome = try move(animated, .right, .slow)
        let reference = try move(plain, .right, .off)

        #expect(outcome == reference)
        #expect(try animated.frames(2) == plain.frames(2))
        // One glide of 0.4 s, not two: the compensation is applied at once. Everything after the glide is
        // the plain run's calls, first round and second round together.
        #expect(abs(clock.elapsed - 0.4) < 1e-9)
        let plainCalls = plain.calls(since: markPlain)
        // B (4 calls: it is also shifted back inside the display), A (3), and A again (3).
        #expect(plainCalls.count == 10, "the plain run: \(plainCalls)")
        #expect(Array(animated.calls(since: markAnimated).suffix(plainCalls.count)) == plainCalls)
    }

    @Test("off with an animator makes no intermediate call at all")
    func off() throws {
        let clock = FakeClock()
        let animated = try makeDesk(count: 3, rows: 1, columns: 3, clock: clock)
        let plain = try makeDesk(count: 3, rows: 1, columns: 3, clock: nil)
        let markAnimated = animated.log.count
        let markPlain = plain.log.count

        _ = try move(animated, .left, .off)
        _ = try move(plain, .left, .off)

        #expect(animated.calls(since: markAnimated) == plain.calls(since: markPlain))
        #expect(clock.sleeps.isEmpty)
    }

    @Test("a window that cannot be changed ends the move as before: the windows after it are not touched at all")
    func failingShrinkingWindow() throws {
        let clock = FakeClock()
        let animated = try makeDesk(count: 2, rows: 1, columns: 2, clock: clock)
        let plain = try makeDesk(count: 2, rows: 1, columns: 2, clock: nil)
        let before = try animated.frames(2)
        // B shrinks first on a move to the right.
        let failure = WindowError.accessibility(operation: "set AXSize", code: -25204)
        animated.window(2).fake.failSizeWith = failure
        plain.window(2).fake.failSizeWith = failure
        let mark = animated.log.count

        let outcome = try move(animated, .right, .slow)
        let reference = try move(plain, .right, .off)

        #expect(outcome == reference)
        #expect(try animated.frames(2) == before, "A must not grow into B's space when B did not shrink")
        #expect(animated.calls(since: mark).allSatisfy { $0.hasPrefix("2 ") }, "\(animated.calls(since: mark))")
        #expect(animated.executor.linkedGroups.isEmpty)
    }

    @Test("no two windows overlap at any moment of an animated move, in any direction, from any window")
    func neverOverlapping() throws {
        let layouts: [(count: Int, rows: Int, columns: Int)] = [(2, 1, 2), (3, 1, 3), (2, 2, 1), (4, 2, 2), (3, 2, 2)]
        for layout in layouts {
            for focused in 1...layout.count {
                for direction in Direction.allCases {
                    let clock = FakeClock()
                    let desk = try makeDesk(count: layout.count, rows: layout.rows, columns: layout.columns, clock: clock)
                    desk.focused = UInt32(focused)
                    desk.startWatchingOverlaps()

                    _ = try move(desk, direction, .medium)
                    _ = try move(desk, direction, .medium)

                    #expect(
                        desk.overlaps.isEmpty,
                        "\(layout.count) windows in \(layout.rows)×\(layout.columns), window \(focused) \(direction): \(desk.overlaps)"
                    )
                }
            }
        }
    }
}
