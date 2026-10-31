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

        @Test("swap 7. a swapWindow shortcut with no neighbour shows the noNeighbour notice, and nothing moves")
        func noNeighbourNotice() async throws {
            let swap = KeyBinding(action: .swapWindow(.left), shortcut: TestShortcut.f13)
            try await withLinkedResize(destinationPreview: false, bindings: [swap]) { run in
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
    }
}

// MARK: - Steps

extension LinkedRun {
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
