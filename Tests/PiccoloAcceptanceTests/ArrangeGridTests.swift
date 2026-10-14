import CoreGraphics
import Foundation
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for `arrangeGrid`: the installed Debug Piccolo lays out the most recently focused
/// windows of the fixture app, and every frame is measured in the window server.
///
/// Every test passes the fixture's pid as `onlyPid` (`ArrangeRun` does, and cannot be told not to), so
/// that the windows of the machine's owner are never candidates, and focuses its windows one by one
/// with `Focus.bring` before arranging. Expected frames come from `TileLayout` on the display's visible
/// frame, with the one point tolerance of every frame measurement (see "Desktop acceptance" in
/// `CLAUDE.md`): neighbouring cells must share an edge within a point.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the suite
/// it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Arrange grid")
    struct ArrangeGrid {
        private static let fourInTwoByTwo = GridSpec(count: 4, rows: 2, columns: 2)

        // MARK: 1. Four windows

        @Test("arrange 1. four windows focused W1…W4 in 2×2: W4 top-left, W3 top-right, W2 bottom-left, W1 bottom-right")
        func fourWindows() async throws {
            let screen = try await ArrangeRun.screens()[0]
            let grid = Self.fourInTwoByTwo

            try await withFixtureOnDefaultSettings { fixture in
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(["W1", "W2", "W3", "W4"], on: screen)
                try await run.focus(windows)
                let stackingBefore = ArrangeRun.stacking(of: windows)

                let result = try run.arrange(grid)

                let measured = try await run.expectArranged(
                    result, order: windows.reversed(), grid: grid, on: screen)
                run.expectTiled(measured, layout: ArrangeRun.cells(4, in: grid, on: screen).layout, on: screen)
                // The cells themselves, by position: W4 top-left, W3 top-right, W2 bottom-left, W1 bottom-right.
                let (w4, w3, w2, w1) = (measured[0], measured[1], measured[2], measured[3])
                #expect(w4.minX < w3.minX && w2.minX < w1.minX, "W4 and W2 should be left of W3 and W1")
                #expect(w4.minY < w2.minY && w3.minY < w1.minY, "W4 and W3 should be above W2 and W1")

                // Arranging raises and focuses nothing: the stacking is as it was, and W4 still has the focus.
                let stackingAfter = ArrangeRun.stacking(of: windows)
                #expect(
                    stackingAfter == stackingBefore,
                    "the windows were stacked front to back as \(stackingBefore) before and as \(stackingAfter) after arranging")
                let focused = try run.piccolo.focusedWindow()
                #expect(
                    fixture.processIDs().contains(focused.pid) && framesMatch(focused.frame, w4),
                    "the focused window is at \(describe(focused.frame)) of pid \(focused.pid), it should still be W4 at \(describe(w4))"
                )
            }
        }

        // MARK: 2. Three windows

        @Test("arrange 2. three windows in 2×2: two on top and the third across the full width below")
        func threeWindows() async throws {
            let screen = try await ArrangeRun.screens()[0]
            let grid = Self.fourInTwoByTwo

            try await withFixtureOnDefaultSettings { fixture in
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(["W1", "W2", "W3"], on: screen)
                try await run.focus(windows)

                let result = try run.arrange(grid)

                let measured = try await run.expectArranged(
                    result, order: windows.reversed(), grid: grid, on: screen)
                run.expectTiled(measured, layout: ArrangeRun.cells(3, in: grid, on: screen).layout, on: screen)
                let wide = measured[2]
                #expect(
                    approximatelyEqual(wide.width, screen.visibleFrame.width),
                    "the third window should span the full width \(screen.visibleFrame.width), it is measured at \(describe(wide))"
                )
                #expect(
                    measured[0].maxY <= wide.minY + frameTolerance,
                    "the top two windows should be above the third: \(describe(measured[0])) and \(describe(wide))")
            }
        }

        // MARK: 3. More windows than the grid holds

        @Test("arrange 3. six windows in 2×2: the four most recently focused are arranged, the other two keep their frames")
        func sixWindows() async throws {
            let screen = try await ArrangeRun.screens()[0]
            let grid = Self.fourInTwoByTwo

            try await withFixtureOnDefaultSettings { fixture in
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(["W1", "W2", "W3", "W4", "W5", "W6"], on: screen)
                try await run.focus(windows)
                let untouched = Array(windows[0..<2])

                let result = try run.arrange(grid)

                let arranged = Array(windows[2...].reversed())
                let measured = try await run.expectArranged(result, order: arranged, grid: grid, on: screen)
                run.expectTiled(measured, layout: ArrangeRun.cells(4, in: grid, on: screen).layout, on: screen)
                run.expectUnmoved(untouched, at: untouched.map(\.frame))
            }
        }

        // MARK: 4. Two windows, side by side and stacked

        @Test("arrange 4. two windows: 2 in 1×2 puts them side by side, 2 in 2×1 stacks them")
        func twoWindows() async throws {
            let screen = try await ArrangeRun.screens()[0]
            let sideBySide = GridSpec(count: 2, rows: 1, columns: 2)
            let stacked = GridSpec(count: 2, rows: 2, columns: 1)

            try await withFixtureOnDefaultSettings { fixture in
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(["W1", "W2"], on: screen)
                try await run.focus(windows)
                let order = Array(windows.reversed())

                let left = try await run.expectArranged(
                    try run.arrange(sideBySide), order: order, grid: sideBySide, on: screen)
                run.expectTiled(left, layout: ArrangeRun.cells(2, in: sideBySide, on: screen).layout, on: screen)
                #expect(
                    left[0].minX < left[1].minX && approximatelyEqual(left[0].minY, left[1].minY),
                    "side by side: W2 should be left of W1 at the same height, they are \(describe(left[0])) and \(describe(left[1]))"
                )

                let top = try await run.expectArranged(
                    try run.arrange(stacked), order: order, grid: stacked, on: screen)
                run.expectTiled(top, layout: ArrangeRun.cells(2, in: stacked, on: screen).layout, on: screen)
                #expect(
                    top[0].minY < top[1].minY && approximatelyEqual(top[0].minX, top[1].minX),
                    "stacked: W2 should be above W1 at the same left edge, they are \(describe(top[0])) and \(describe(top[1]))"
                )
            }
        }

        // MARK: 5. A minimized window

        @Test("arrange 5. a minimized window is skipped: with W4 minimized, W3, W2 and W1 are arranged as three")
        func minimizedWindowIsSkipped() async throws {
            let screen = try await ArrangeRun.screens()[0]
            let grid = Self.fourInTwoByTwo

            try await withFixtureOnDefaultSettings { fixture in
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(["W1", "W2", "W3", "W4"], on: screen)
                try await run.focus(windows)

                try fixture.miniaturize(id: "W4")
                _ = try await eventually("window W4 to leave the screen") {
                    Measure.frame(ofWindow: windows[3].windowNumber) == nil
                        ? Observation.satisfied(()) : .unsatisfied("it is still listed as on screen")
                }
                // Minimizing hands the focus to another window of the fixture; make it W3.
                try await Focus.bring(windows[2], of: fixture)

                let result = try run.arrange(grid)

                let arranged = [windows[2], windows[1], windows[0]]
                let measured = try await run.expectArranged(result, order: arranged, grid: grid, on: screen)
                run.expectTiled(measured, layout: ArrangeRun.cells(3, in: grid, on: screen).layout, on: screen)
                #expect(try fixture.isMiniaturized(id: "W4"), "W4 should still be minimized")
                #expect(Measure.frame(ofWindow: windows[3].windowNumber) == nil, "W4 should still be off the screen")
            }
        }

        // MARK: 6. Two displays

        @Test(
            "arrange 6. with two displays the focused window's display is arranged and the other display's windows keep their frames",
            .enabled(if: Acceptance.displayCount >= 2, "needs two or more displays")
        )
        func twoDisplays() async throws {
            let screens = try await ArrangeRun.screens()
            let grid = Self.fourInTwoByTwo

            try await withFixtureOnDefaultSettings { fixture in
                let run = ArrangeRun(fixture: fixture)
                for screen in screens {
                    guard let other = screens.first(where: { $0.index != screen.index }) else {
                        throw AcceptanceFailure("the display list has no display besides \(screen.index): \(screens)")
                    }
                    // A1 and A2 on the display under test, B1 and B2 on the other one. A2 is focused
                    // last, so the focused window is on the display under test and the windows of the
                    // other display were focused before it.
                    let here = try await run.open(["A1", "A2"], on: screen)
                    let there = try await run.open(["B1", "B2"], on: other)
                    try await run.focus(there + here)

                    let result = try run.arrange(grid)

                    let measured = try await run.expectArranged(
                        result, order: here.reversed(), grid: grid, on: screen)
                    run.expectTiled(measured, layout: ArrangeRun.cells(2, in: grid, on: screen).layout, on: screen)
                    run.expectUnmoved(there, at: there.map(\.frame))

                    try fixture.closeAll()
                }
            }
        }

        // MARK: 7. A window that refuses its cell's size

        @Test("arrange 7. a window whose minimum size exceeds its cell reports and has the achieved frame, the others land on their cells")
        func windowRefusingTheCell() async throws {
            let screen = try await ArrangeRun.screens()[0]
            let grid = Self.fourInTwoByTwo
            let cells = ArrangeRun.cells(4, in: grid, on: screen).frames
            // W3 takes the top-right cell, which it cannot fill: it needs more width and height.
            let minimum = CGSize(width: cells[1].width + 150, height: cells[1].height + 100)
            guard minimum.width + 80 <= screen.visibleFrame.width, minimum.height + 80 <= screen.visibleFrame.height
            else {
                try Test.cancel(
                    "the display (\(describe(screen.visibleFrame.size))) is too small for a window of \(describe(minimum))"
                )
            }

            try await withFixtureOnDefaultSettings { fixture in
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(
                    ["W1", "W2", "W3", "W4"], on: screen, minSizes: ["W3": minimum])
                try await run.focus(windows)

                let result = try run.arrange(grid)

                let measured = try await run.expectArranged(
                    result, order: windows.reversed(), grid: grid, on: screen, refusing: ["W3"])
                let refuser = measured[1]
                #expect(
                    refuser.width >= minimum.width - frameTolerance && refuser.height >= minimum.height - frameTolerance,
                    "W3 is measured at \(describe(refuser)), it cannot be smaller than its minimum \(describe(minimum))"
                )
                #expect(
                    !sizesMatch(refuser.size, cells[1].size),
                    "W3 took its cell's size \(describe(cells[1].size)) although it needs at least \(describe(minimum))"
                )
                #expect(
                    screen.visibleFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(refuser),
                    "W3 is measured at \(describe(refuser)), outside the visible frame \(describe(screen.visibleFrame))"
                )
                // The cells of the windows that fit are unaffected: W4 top-left, W2 bottom-left, W1 bottom-right.
                for (index, cell) in cells.enumerated() where index != 1 {
                    #expect(
                        framesMatch(measured[index], cell),
                        "\(windows.reversed()[index].id) is measured at \(describe(measured[index])), its cell is \(describe(cell))"
                    )
                }
            }
        }

        // MARK: 8. Nothing to arrange

        @Test("arrange 8. with no fixture window open, arrangeGrid says there is nothing to do")
        func nothingToDo() async throws {
            try await withFixture { fixture in
                let run = ArrangeRun(fixture: fixture)

                let result = try run.arrange(Self.fourInTwoByTwo)

                #expect(result == .nothingToDo, "arrangeGrid answered \(result) with no fixture window open")
            }
        }

        // MARK: 9. The focus history

        @Test("arrange 9. focus.history lists the fixture's windows in the order they were focused, most recent first")
        func focusHistory() async throws {
            let screen = try await ArrangeRun.screens()[0]

            try await withFixture { fixture in
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(["W1", "W2", "W3", "W4"], on: screen)

                // Focused W1, W2, W3, W4: the history is W4, W3, W2, W1 (waited for inside).
                try await run.focus(windows)

                // Focus W2 again: it moves to the front, the rest keep their order.
                try await Focus.bring(windows[1], of: fixture)
                try await run.waitForHistory(of: [windows[0], windows[2], windows[3], windows[1]])
            }
        }

        // MARK: 10. The tracker starts at launch

        @Test("arrange 10. a freshly launched Piccolo that has run no action yet has the history of the windows focused since it started")
        func trackerStartsAtLaunch() async throws {
            let screen = try await ArrangeRun.screens()[0]

            try await withFixture { fixture in
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(["W1", "W2"], on: screen)

                // A new process, which nobody has asked for anything: no action has run, and nothing
                // has asked for the history either. Only what the app itself does at launch can have
                // started the tracker.
                try await PiccoloProcess.restart()

                // Focused W1, then W2: the history lists W2, W1 (waited for inside).
                try await run.focus(windows)
            }
        }
    }
}
