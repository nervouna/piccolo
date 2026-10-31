import CoreGraphics
import Foundation
import PiccoloCore
import Testing

/// Acceptance tests for Swap Window: in a group that Piccolo arranged, a `swapWindow` action exchanges
/// the focused window with its neighbour on that side, the two windows trade cells, and the group stays
/// linked.
///
/// Every test runs inside `withLinkedResize`: the config in effect has a known resize step, the fixture
/// starts with no windows, and the windows of the machine's owner never join a group (every
/// `arrangeGrid` and every `swapWindow` passes the fixture's pid as `onlyPid`; the hotkeys of the
/// preview and notice tests act on the fixture's focused window, which is in a group of fixture
/// windows only). The expected frames come from `TileLayout` on the visible frame of the display the
/// app reports, except for the window gap, whose rule is written out here as the gap tests do. Frames
/// are compared within 1 pt.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Swap window")
    struct SwapWindow {
        private let piccolo = PiccoloClient()
        private static let step = LinkedRun.defaultStep

        // MARK: 1. Two windows

        @Test("swap 1. two windows arranged 1 × 2, the right one focused: swapWindow left exchanges the frames and the group's order, and swapWindow right from the same window brings them back")
        func exchangeAndBack() async throws {
            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B"])
                let (a, b) = (windows[0], windows[1])
                let (layout, _) = try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                let cells = layout.frames(in: run.screen.visibleFrame)

                let reported = try await run.swapExpectingSwap(.left, from: b)

                try await run.expectSwapped(order: [b, a], at: cells, reported: reported)

                // The focused window moved with its cell and kept the focus, so the same press the other
                // way brings both back.
                let back = try await run.swapExpectingSwap(.right, from: b, refocus: false)

                try await run.expectSwapped(order: [a, b], at: cells, reported: back)
            }
        }

        // MARK: 2. Sizes stay with the cells

        @Test("swap 2. after a moveDivider right the left window is wide: swapWindow right gives the window that was narrow the wide cell, and a following moveDivider answers moved")
        func sizesStayWithTheCells() async throws {
            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B"])
                let (a, b) = (windows[0], windows[1])
                try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                _ = try await run.pressExpectingMove(.right, from: a)
                let layout = LinkedRun.row(dividers: [0.5 + Self.step])
                let cells = layout.frames(in: run.screen.visibleFrame)
                try await run.expectLayout(layout, windows: windows)
                #expect(cells[0].width > cells[1].width, "the left cell should be the wide one")

                let reported = try await run.swapExpectingSwap(.right, from: a, refocus: false)

                // B was narrow and now has the wide cell, A the narrow one.
                try await run.expectSwapped(order: [b, a], at: cells, reported: reported)
                let wide = try #require(Measure.frame(ofWindow: b.windowNumber))
                let narrow = try #require(Measure.frame(ofWindow: a.windowNumber))
                #expect(wide.width > narrow.width, "B measures \(describe(wide)) and A \(describe(narrow)) after the swap")

                // The group stays linked: B is in the left cell now, and the key moves the divider again.
                let moved = try await run.pressExpectingMove(.right, from: b, refocus: false)
                try await run.expectLayout(
                    LinkedRun.row(dividers: [0.5 + 2 * Self.step]), windows: [b, a], reported: moved)
            }
        }

        // MARK: 3. A grid

        @Test("swap 3. four windows in 2 × 2: swapWindow down from the top-left window trades with the bottom-left one, and the other two do not move")
        func twoByTwo() async throws {
            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "C", "D"])
                let (a, b, c, d) = (windows[0], windows[1], windows[2], windows[3])
                let (layout, _) = try await run.arrange(windows, in: GridSpec(count: 4, rows: 2, columns: 2))
                let cells = layout.frames(in: run.screen.visibleFrame)
                let before = try run.measuredFrames([b, d])

                let reported = try await run.swapExpectingSwap(.down, from: a)

                try await run.expectSwapped(order: [c, b, a, d], at: cells, reported: reported)
                run.expectUnmoved([b, d], at: before)
            }
        }

        // MARK: 4. No neighbour

        @Test("swap 4. swapWindow left from the leftmost window: nothingToDo with noNeighbour, and nothing moves; up and down in a single row too")
        func noNeighbour() async throws {
            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B"])
                let a = windows[0]
                let (layout, arranged) = try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                let cells = layout.frames(in: run.screen.visibleFrame)
                try await Focus.bring(a, of: run.fixture)

                for key in [Direction.left, .up, .down] {
                    let nothing = try await run.swapExpectingNothing(key, from: a, reason: "noNeighbour", refocus: false)
                    #expect(!nothing.message.isEmpty)
                }

                // A swap that did something would show within the glide, so watch for a while.
                try await Task.sleep(for: .milliseconds(500))
                run.expectUnmoved(windows, at: arranged)
                try run.expectGroup(order: windows, at: cells)
            }
        }

        // MARK: 5. Window gap

        @Test("swap 5. with a window gap of 12, the swapped windows are at the gapped cells")
        func gap() async throws {
            let gap: CGFloat = 12
            try await withLinkedResize(gap: Int(gap)) { run in
                let v = run.screen.visibleFrame
                let windows = try await run.open(["A", "B"])
                let (a, b) = (windows[0], windows[1])
                try await run.run.focus(windows.reversed())
                let arranged = try run.run.arrange(GridSpec(count: 2, rows: 1, columns: 2))
                guard case .arranged(_, let placed) = arranged, placed.count == 2 else {
                    throw AcceptanceFailure("arrangeGrid answered \(arranged), expected an arrangement of two windows")
                }
                // The gap rule: `gap` to the edges of the visible frame, half of it to the divider.
                let middle = v.minX + v.width / 2
                let left = CGRect(
                    x: v.minX + gap, y: v.minY + gap, width: middle - gap / 2 - (v.minX + gap), height: v.height - 2 * gap)
                let right = CGRect(
                    x: middle + gap / 2, y: v.minY + gap, width: v.maxX - gap - (middle + gap / 2), height: v.height - 2 * gap)
                _ = try await Measure.waitForFrame(ofWindow: a.windowNumber, matching: left)
                _ = try await Measure.waitForFrame(ofWindow: b.windowNumber, matching: right)

                let reported = try await run.swapExpectingSwap(.left, from: b)

                try await run.expectSwapped(order: [b, a], at: [left, right], reported: reported)
                let first = try #require(Measure.frame(ofWindow: b.windowNumber))
                let second = try #require(Measure.frame(ofWindow: a.windowNumber))
                #expect(approximatelyEqual(second.minX - first.maxX, gap), "the windows are \(second.minX - first.maxX) pt apart")
                #expect(approximatelyEqual(first.minX - v.minX, gap) && approximatelyEqual(v.maxX - second.maxX, gap))
            }
        }

        // MARK: 6. Destination preview

        @Test("swap 6. holding a swapWindow shortcut shows highlights at the two exchanged frames and leaves the windows alone; the release swaps them")
        func preview() async throws {
            let swap = KeyBinding(action: .swapWindow(.left), shortcut: TestShortcut.f13)
            try await withLinkedResize(bindings: [swap]) { run in
                let windows = try await run.open(["A", "B"])
                let (a, b) = (windows[0], windows[1])
                let (layout, arranged) = try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                let cells = layout.frames(in: run.screen.visibleFrame)
                try await Focus.bring(b, of: run.fixture)
                let pid = try piccolo.pid()

                try piccolo.pressHotkey(swap.id)

                let state = try await eventually(
                    "preview.state to show the two exchanged frames \(cells.map(describe))", timeout: 8
                ) { () -> Observation<PiccoloClient.PreviewState> in
                    let state = try piccolo.previewState()
                    guard state.visible, state.frames.count == 2 else {
                        return .unsatisfied(
                            "visible: \(state.visible), frames: \(state.frames.map(describe)), planning error: \(state.planningError ?? "none")")
                    }
                    return .satisfied(state)
                }
                // The two windows that would trade, in cell order after the swap: B in the left cell,
                // A in the right one.
                #expect(state.windows == [b.windowNumber, a.windowNumber], "the preview refers to \(String(describing: state.windows))")
                for (index, cell) in cells.enumerated() {
                    #expect(
                        framesMatch(state.frames[index], cell),
                        "highlight \(index) is at \(describe(state.frames[index])), the cell is \(describe(cell))")
                }
                _ = try await PiccoloOverlays.waitForHighlights(pid: pid, at: cells)
                run.expectUnmoved(windows, at: arranged)

                try piccolo.releaseHotkey(swap.id)

                try await PiccoloOverlays.waitForNoHighlight(pid: pid, at: cells)
                _ = try await Measure.waitForFrame(ofWindow: b.windowNumber, matching: cells[0])
                _ = try await Measure.waitForFrame(ofWindow: a.windowNumber, matching: cells[1])
                try run.expectGroup(order: [b, a], at: cells)
                let after = try piccolo.previewState()
                #expect(
                    after.last == PiccoloClient.PreviewState.Last(bindingID: swap.id, result: "ran", previewShown: true),
                    "last is \(String(describing: after.last))")
            }
        }

        // MARK: 7. The notice

        @Test("swap 7. with window animation Off, a swapWindow shortcut with no neighbour shows the noNeighbour notice, and nothing moves")
        func noNeighbourNotice() async throws {
            let swap = KeyBinding(action: .swapWindow(.left), shortcut: TestShortcut.f13)
            try await withLinkedResize(animation: .off, destinationPreview: false, bindings: [swap]) { run in
                let windows = try await run.open(["A", "B"])
                let a = windows[0]
                let (_, arranged) = try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                try await Focus.bring(a, of: run.fixture)
                let texts = try InterfaceTexts.current(piccolo)

                try piccolo.simulateHotkey(swap.id)

                let state = try await eventually("notice.state to be visible with a last notice", timeout: 5) {
                    () -> Observation<NoticeState> in
                    let state = try piccolo.noticeState()
                    return state.visible && state.last != nil ? .satisfied(state) : .unsatisfied("\(state)")
                }
                let last = try #require(state.last)
                #expect(last.kind == "noNeighbour", "the kind is \(last.kind)")
                #expect(last.text == texts.notice(.noNeighbour), "the text is \"\(last.text)\"")
                run.expectUnmoved(windows, at: arranged)
            }
        }

        // MARK: 8. The bounce

        @Test("swap 8. with window animation Fast, swapWindow left from the leftmost window of a 1 × 2 group answers noNeighbour with bounced true, the window goes out to the left and is back at its frame, and a following moveDivider answers moved")
        func bounceLeft() async throws {
            try await withLinkedResize(animation: .fast) { run in
                let windows = try await run.open(["A", "B"])
                let a = windows[0]
                let (layout, arranged) = try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                let cells = layout.frames(in: run.screen.visibleFrame)
                try await Focus.bring(a, of: run.fixture)

                let (nothing, samples) = try await run.swapSampled(.left, from: a)

                #expect(nothing.bounced == true, "bounced is \(String(describing: nothing.bounced)), the answer is \(nothing)")
                run.expectBounce(of: arranged[0], towards: .left, samples: samples)
                _ = try await Measure.waitForFrame(ofWindow: a.windowNumber, matching: arranged[0])
                run.expectUnmoved(windows, at: arranged)
                try run.expectGroup(order: windows, at: cells)

                // The group is still linked: the window is at its recorded frame.
                let moved = try await run.pressExpectingMove(.right, from: a, refocus: false)
                try await run.expectLayout(
                    LinkedRun.row(dividers: [0.5 + Self.step]), windows: windows, reported: moved)
            }
        }

        @Test("swap 9. with window animation Fast, swapWindow up from a window of a 1 × 2 group bounces too: the window is squashed from below, and keeps its frame afterwards")
        func bounceUp() async throws {
            try await withLinkedResize(animation: .fast) { run in
                let windows = try await run.open(["A", "B"])
                let b = windows[1]
                let (layout, arranged) = try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                let cells = layout.frames(in: run.screen.visibleFrame)
                try await Focus.bring(b, of: run.fixture)

                let (nothing, samples) = try await run.swapSampled(.up, from: b)

                #expect(nothing.bounced == true, "bounced is \(String(describing: nothing.bounced)), the answer is \(nothing)")
                run.expectBounce(of: arranged[1], towards: .up, samples: samples)
                _ = try await Measure.waitForFrame(ofWindow: b.windowNumber, matching: arranged[1])
                run.expectUnmoved(windows, at: arranged)
                try run.expectGroup(order: windows, at: cells)
            }
        }

        @Test("swap 10. with window animation Off, swapWindow left and up answer noNeighbour with bounced false, and the window is never seen anywhere but at its frame")
        func noBounceWhenOff() async throws {
            try await withLinkedResize(animation: .off) { run in
                let windows = try await run.open(["A", "B"])
                let a = windows[0]
                let (layout, arranged) = try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                let cells = layout.frames(in: run.screen.visibleFrame)
                try await Focus.bring(a, of: run.fixture)

                for key in [Direction.left, .up] {
                    let (nothing, samples) = try await run.swapSampled(key, from: a)

                    #expect(nothing.bounced == false, "\(key): bounced is \(String(describing: nothing.bounced)), the answer is \(nothing)")
                    #expect(!samples.isEmpty, "\(key): no sample of the window")
                    for sample in samples {
                        #expect(
                            framesMatch(sample, arranged[0]),
                            "\(key): the window was seen at \(describe(sample)), its frame is \(describe(arranged[0]))")
                    }
                }
                run.expectUnmoved(windows, at: arranged)
                try run.expectGroup(order: windows, at: cells)
            }
        }

        @Test("swap 11. with window animation Fast, a swapWindow shortcut with no neighbour bounces the window and shows no notice")
        func noNoticeWhenBouncing() async throws {
            let swap = KeyBinding(action: .swapWindow(.left), shortcut: TestShortcut.f13)
            try await withLinkedResize(animation: .fast, destinationPreview: false, bindings: [swap]) { run in
                let windows = try await run.open(["A", "B"])
                let a = windows[0]
                let (_, arranged) = try await run.arrange(windows, in: GridSpec(count: 2, rows: 1, columns: 2))
                try await Focus.bring(a, of: run.fixture)
                let before = try piccolo.noticeState().last
                let sampler = FrameSampler(window: a.windowNumber)

                try piccolo.simulateHotkey(swap.id)

                // The window bounces; a negative result (no notice) has to be watched for a while.
                let clock = ContinuousClock()
                let begin = clock.now
                var failure: String?
                while failure == nil, begin.duration(to: clock.now) < .seconds(1.5) {
                    let state = try piccolo.noticeState()
                    if state.visible { failure = "a notice became visible: \(state)" }
                    if state.last != before { failure = "a notice was shown: \(String(describing: state.last))" }
                    try await Task.sleep(for: .milliseconds(50))
                }
                let samples = sampler.stop()
                if let failure { Issue.record("\(failure)") }
                run.expectBounce(of: arranged[0], towards: .left, samples: samples)
                run.expectUnmoved(windows, at: arranged)
            }
        }
    }
}

/// Samples a window's frame from the window server on a thread of its own, every few milliseconds. A
/// bounce is over when the command that makes it answers, so it can only be seen from outside.
private final class FrameSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [CGRect] = []
    private var running = true
    private let finished = DispatchSemaphore(value: 0)

    init(window windowNumber: Int, interval: TimeInterval = 0.004) {
        Thread.detachNewThread { [self] in
            while isRunning {
                if let frame = Measure.frame(ofWindow: windowNumber) { record(frame) }
                Thread.sleep(forTimeInterval: interval)
            }
            finished.signal()
        }
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func record(_ frame: CGRect) {
        lock.lock()
        defer { lock.unlock() }
        frames.append(frame)
    }

    /// Stops sampling and returns the frames seen, in order.
    func stop() -> [CGRect] {
        lock.lock()
        let wasRunning = running
        running = false
        lock.unlock()
        if wasRunning { finished.wait() }
        lock.lock()
        defer { lock.unlock() }
        return frames
    }
}

// MARK: - Steps

extension LinkedRun {
    /// Presses the swap key from `window`, which already has the focus, while its frame is sampled
    /// from the window server (see `FrameSampler`), and expects the answer `noNeighbour`. Keeps sampling
    /// for a moment after the answer, to show what the window does when it should be at rest.
    ///
    /// - Returns: the answer and the frames seen, in order.
    fileprivate func swapSampled(
        _ key: Direction, from window: FixtureWindow
    ) async throws -> (nothing: PiccoloClient.SwapNothingToDo, samples: [CGRect]) {
        let sampler = FrameSampler(window: window.windowNumber)
        do {
            let nothing = try await swapExpectingNothing(key, from: window, reason: "noNeighbour", refocus: false)
            try await Task.sleep(for: .milliseconds(200))
            return (nothing, sampler.stop())
        } catch {
            _ = sampler.stop()
            throw error
        }
    }

    /// Checks the frames seen during a bounce of a window that started at `start`: it went out towards
    /// `direction` by at least 8 pt and by no more than the amplitude (1 pt tolerance), then overshot
    /// the start by no more than 4 pt, and it is back on the start frame at the end. The whole frame
    /// moves for left, right and down, and only the bottom edge for up (the top edge and the width
    /// stay); the overshoot of up grows the height.
    fileprivate func expectBounce(of start: CGRect, towards direction: Direction, samples: [CGRect]) {
        #expect(samples.count >= 10, "\(direction): only \(samples.count) samples of the window")
        var deepest: CGFloat = 0
        var problems: [String] = []
        for sample in samples {
            let depth: CGFloat
            let stays: Bool
            switch direction {
            case .left:
                depth = start.minX - sample.minX
                stays = approximatelyEqual(sample.minY, start.minY) && sizesMatch(sample.size, start.size)
            case .right:
                depth = sample.minX - start.minX
                stays = approximatelyEqual(sample.minY, start.minY) && sizesMatch(sample.size, start.size)
            case .down:
                depth = sample.minY - start.minY
                stays = approximatelyEqual(sample.minX, start.minX) && sizesMatch(sample.size, start.size)
            case .up:
                depth = start.maxY - sample.maxY
                stays =
                    approximatelyEqual(sample.minX, start.minX) && approximatelyEqual(sample.minY, start.minY)
                    && approximatelyEqual(sample.width, start.width)
            }
            deepest = max(deepest, depth)
            if !stays { problems.append("seen at \(describe(sample)), more than the bounce changes") }
            if depth > EdgeBounce.amplitude + 1 {
                problems.append("seen \(depth) pt out at \(describe(sample)), the bounce is \(EdgeBounce.amplitude) pt")
            }
            // The spring overshoots the start by about 2 pt, on the other side.
            if depth < -4 {
                problems.append("seen \(-depth) pt past the start at \(describe(sample)), the overshoot is at most 4 pt")
            }
        }
        if let last = samples.last, !framesMatch(last, start) {
            problems.append("the last frame seen is \(describe(last)), the window should be back on \(describe(start))")
        }
        #expect(problems.isEmpty, "\(direction) from \(describe(start)): \(problems.prefix(3))")
        #expect(
            deepest >= 8,
            "\(direction) from \(describe(start)): the window was seen at most \(deepest) pt out in \(samples.count) samples, a bounce is \(EdgeBounce.amplitude) pt"
        )
    }

    /// Focuses `window` (unless `refocus` is false: the window already has the focus) and presses the
    /// swap key.
    fileprivate func swap(
        _ key: Direction, from window: FixtureWindow, refocus: Bool = true
    ) async throws -> PiccoloClient.SwapWindowResult {
        if refocus { try await Focus.bring(window, of: fixture) }
        return try piccolo.swapWindow(key, onlyPid: try fixture.processID())
    }

    /// Presses the swap key and expects the windows to trade cells.
    ///
    /// - Returns: The windows of the group in cell order after the swap, with what Piccolo reports.
    fileprivate func swapExpectingSwap(
        _ key: Direction, from window: FixtureWindow, refocus: Bool = true
    ) async throws -> [PiccoloClient.ArrangedWindow] {
        let result = try await swap(key, from: window, refocus: refocus)
        guard case .swapped(let display, let reported) = result else {
            throw AcceptanceFailure("swap \(key) from window '\(window.id)' answered \(result), expected the windows to swap")
        }
        #expect(display == screen.index, "the group is on display \(display), the test is about display \(screen.index)")
        return reported
    }

    /// Presses the swap key and expects nothing to happen, for this reason.
    @discardableResult
    fileprivate func swapExpectingNothing(
        _ key: Direction, from window: FixtureWindow, reason: String, refocus: Bool = true
    ) async throws -> PiccoloClient.SwapNothingToDo {
        let result = try await swap(key, from: window, refocus: refocus)
        guard case .nothingToDo(let nothing) = result else {
            throw AcceptanceFailure(
                "swap \(key) from window '\(window.id)' answered \(result), expected nothing to do (\(reason))")
        }
        #expect(
            nothing.reason == reason,
            "swap \(key) from window '\(window.id)' did nothing because \"\(nothing.reason)\" (\(nothing.message)), expected \"\(reason)\"")
        return nothing
    }

    /// Checks that the windows, in cell order, are measured at `cells` (within 1 pt), that Piccolo's
    /// answer (when given) lists them in that order with their cell as the target and no error, and that
    /// `groups.list` holds them in that order at those frames.
    fileprivate func expectSwapped(
        order windows: [FixtureWindow], at cells: [CGRect], reported: [PiccoloClient.ArrangedWindow]? = nil
    ) async throws {
        for (window, cell) in zip(windows, cells) {
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: cell)
        }
        if let reported {
            #expect(
                reported.map(\.windowNumber) == windows.map(\.windowNumber),
                "the answer lists the windows \(reported.map(\.windowNumber)), expected \(windows.map { "\($0.id)=\($0.windowNumber)" }) in cell order"
            )
            for (index, entry) in reported.enumerated() where index < cells.count {
                #expect(
                    framesMatch(entry.target, cells[index]),
                    "window \(entry.windowNumber) was sent to \(describe(entry.target)), cell \(index) is \(describe(cells[index]))")
                if let error = entry.error {
                    Issue.record("window \(entry.windowNumber) could not be moved: \(error)")
                }
            }
        }
        try expectGroup(order: windows, at: cells)
    }

    /// Checks `groups.list`: one group on the display under test that holds exactly these windows in
    /// this order, recorded at these frames (within 1 pt).
    fileprivate func expectGroup(order windows: [FixtureWindow], at cells: [CGRect]) throws {
        let groups = try piccolo.groups()
        guard let group = groups.first(where: { $0.display == screen.index }) else {
            throw AcceptanceFailure("groups.list has no group for display \(screen.index): \(groups)")
        }
        #expect(
            group.windows.map(\.windowNumber) == windows.map(\.windowNumber),
            "the group holds the windows \(group.windows.map(\.windowNumber)), expected \(windows.map { "\($0.id)=\($0.windowNumber)" }) in cell order"
        )
        for (member, cell) in zip(group.windows, cells) {
            #expect(
                framesMatch(member.frame, cell),
                "the group recorded \(describe(member.frame)) for window \(member.windowNumber), the cell is \(describe(cell))")
        }
    }
}
