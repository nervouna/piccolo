import CoreGraphics
import Foundation
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for linked resize: after `arrangeGrid`, a `moveDivider` action moves the divider
/// next to the focused window, the neighbours follow, and the window server measures windows that
/// tile the visible frame with no gap and no overlap.
///
/// Every test runs inside `withLinkedResize`: the config in effect has no bindings and a known resize
/// step, the fixture starts with no windows, and the windows of the machine's owner never join a group
/// (every `arrangeGrid` and every `moveDivider` passes the fixture's pid as `onlyPid`). The design table
/// of #8 is written out as divider positions, and the expected frames come from `TileLayout` on the
/// visible frame of the display the app reports, not from `DividerMove`.
///
/// To start every row of a table from the same layout, the windows are arranged again before each row
/// (which also shows that arranging again replaces the display's group).
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the suite
/// it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Linked resize")
    struct LinkedResize {
        private static let step = LinkedRun.defaultStep
        private static let third = 1.0 / 3
        private static let twoThirds = 2.0 / 3

        /// One row of a table: the cell of the focused window, the key, and the dividers afterwards.
        private struct Row {
            var cell: Int
            var key: Direction
            var dividers: [Double]
        }

        // MARK: 1. Side by side, three windows

        @Test("linked 1. A | B | C: each window, left and right, moves the divider #8 names, and the three windows keep tiling the visible frame")
        func threeSideBySide() async throws {
            let grid = GridSpec(count: 3, rows: 1, columns: 3)
            let (third, twoThirds, step) = (Self.third, Self.twoThirds, Self.step)
            let table = [
                // A: the divider A|B goes where the key goes.
                Row(cell: 0, key: .left, dividers: [third - step, twoThirds]),
                Row(cell: 0, key: .right, dividers: [third + step, twoThirds]),
                // B: left moves A|B left (B grows), right moves B|C right (B grows).
                Row(cell: 1, key: .left, dividers: [third - step, twoThirds]),
                Row(cell: 1, key: .right, dividers: [third, twoThirds + step]),
                // C: left moves B|C left (C grows), right moves B|C right (C shrinks).
                Row(cell: 2, key: .left, dividers: [third, twoThirds - step]),
                Row(cell: 2, key: .right, dividers: [third, twoThirds + step]),
            ]

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "C"])
                for row in table {
                    try await run.arrange(windows, in: grid)

                    let reported = try await run.pressExpectingMove(row.key, from: windows[row.cell])

                    let layout = LinkedRun.row(dividers: row.dividers)
                    try await run.expectLayout(layout, windows: windows, reported: reported)
                }
            }
        }

        // MARK: 2. Side by side, two windows

        @Test("linked 2. two windows side by side: both windows, both directions, move the one divider")
        func twoSideBySide() async throws {
            let grid = GridSpec(count: 2, rows: 1, columns: 2)
            let step = Self.step
            let table = [
                Row(cell: 0, key: .left, dividers: [0.5 - step]),
                Row(cell: 0, key: .right, dividers: [0.5 + step]),
                Row(cell: 1, key: .left, dividers: [0.5 - step]),
                Row(cell: 1, key: .right, dividers: [0.5 + step]),
            ]

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B"])
                for row in table {
                    try await run.arrange(windows, in: grid)

                    let reported = try await run.pressExpectingMove(row.key, from: windows[row.cell])

                    try await run.expectLayout(
                        LinkedRun.row(dividers: row.dividers), windows: windows, reported: reported)
                }
            }
        }

        // MARK: 3. Stacked

        @Test("linked 3. stacked, 2×1 and 3×1: up and down from the top, the middle and the bottom window")
        func stacked() async throws {
            let (third, twoThirds, step) = (Self.third, Self.twoThirds, Self.step)
            let two = [
                Row(cell: 0, key: .up, dividers: [0.5 - step]),
                Row(cell: 0, key: .down, dividers: [0.5 + step]),
                Row(cell: 1, key: .up, dividers: [0.5 - step]),
                Row(cell: 1, key: .down, dividers: [0.5 + step]),
            ]
            let three = [
                // The top window: up moves its bottom edge up, down moves it down.
                Row(cell: 0, key: .up, dividers: [third - step, twoThirds]),
                Row(cell: 0, key: .down, dividers: [third + step, twoThirds]),
                // The middle window: up moves its top edge, down moves its bottom edge.
                Row(cell: 1, key: .up, dividers: [third - step, twoThirds]),
                Row(cell: 1, key: .down, dividers: [third, twoThirds + step]),
                // The bottom window: both keys move the divider above it.
                Row(cell: 2, key: .up, dividers: [third, twoThirds - step]),
                Row(cell: 2, key: .down, dividers: [third, twoThirds + step]),
            ]

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "C"])
                for (count, table) in [(2, two), (3, three)] {
                    let grid = GridSpec(count: count, rows: count, columns: 1)
                    let members = Array(windows.prefix(count))
                    for row in table {
                        try await run.arrange(members, in: grid)

                        let reported = try await run.pressExpectingMove(row.key, from: members[row.cell])

                        try await run.expectLayout(
                            LinkedRun.column(dividers: row.dividers), windows: members, reported: reported)
                    }
                }
            }
        }

        // MARK: 4. Grids

        @Test("linked 4a. 2×2: the vertical divider moves in both rows, the horizontal one across both columns")
        func twoByTwo() async throws {
            let grid = GridSpec(count: 4, rows: 2, columns: 2)
            let step = Self.step
            // The focused cell, the key, and the dividers of the top row, the bottom row, and between them.
            let cases: [(cell: Int, key: Direction, layout: TileLayout)] = [
                // A vertical move from any cell moves the divider in both rows.
                (1, .left, grid2x2(top: 0.5 - step, bottom: 0.5 - step)),
                (2, .right, grid2x2(top: 0.5 + step, bottom: 0.5 + step)),
                (3, .left, grid2x2(top: 0.5 - step, bottom: 0.5 - step)),
                // The horizontal divider spans both columns.
                (0, .down, grid2x2(top: 0.5, bottom: 0.5, split: 0.5 + step)),
                (3, .up, grid2x2(top: 0.5, bottom: 0.5, split: 0.5 - step)),
            ]

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "C", "D"])
                for test in cases {
                    try await run.arrange(windows, in: grid)

                    let reported = try await run.pressExpectingMove(test.key, from: windows[test.cell])

                    try await run.expectLayout(test.layout, windows: windows, reported: reported)
                }
            }
        }

        @Test("linked 4b. three in 2×2: the wide bottom window is not affected by a vertical move, and has no vertical divider of its own")
        func threeInTwoByTwo() async throws {
            let grid = GridSpec(count: 3, rows: 2, columns: 2)
            let step = Self.step

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "C"])
                let (_, arranged) = try await run.arrange(windows, in: grid)
                let bottom = arranged[2]

                // From a top window: the divider between the two top windows moves, the bottom one stays.
                let reported = try await run.pressExpectingMove(.right, from: windows[0])

                let moved = TileLayout(rows: [
                    TileLayout.Row(height: 0.5, widths: [0.5 + step, 0.5 - step]),
                    TileLayout.Row(height: 0.5, widths: [1]),
                ])
                let measured = try await run.expectLayout(moved, windows: windows, reported: reported)
                #expect(
                    framesMatch(measured[2], bottom),
                    "the bottom window moved from \(describe(bottom)) to \(describe(measured[2])) although only the vertical divider of the top row moved"
                )

                // From the bottom window: left and right have no divider to move.
                for key in [Direction.left, .right] {
                    let nothing = try await run.pressExpectingNothing(key, from: windows[2], reason: "cannotMove")
                    #expect(nothing.windowNumber == nil)
                }
                run.expectUnmoved(windows, at: measured)

                // Up and down move the divider between the rows.
                let up = try await run.pressExpectingMove(.up, from: windows[2], refocus: false)
                let raised = TileLayout(rows: [
                    TileLayout.Row(height: 0.5 - step, widths: [0.5 + step, 0.5 - step]),
                    TileLayout.Row(height: 0.5 + step, widths: [1]),
                ])
                try await run.expectLayout(raised, windows: windows, reported: up)
            }
        }

        // MARK: 5. The limit

        @Test("linked 5. repeated moves stop at the limit of 10%, and a further press does nothing")
        func limit() async throws {
            let grid = GridSpec(count: 2, rows: 1, columns: 2)
            let step = Self.step

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B"])
                try await run.arrange(windows, in: grid)

                // A grows by one step each time, B shrinks from 50% towards 10%.
                var presses = 0
                var measured: [CGRect] = []
                while presses < 20 {
                    let result = try await run.press(.right, from: windows[0], refocus: presses == 0)
                    guard case .moved(_, let reported) = result else { break }
                    presses += 1
                    measured = try await run.expectLayout(
                        LinkedRun.row(dividers: [0.5 + Double(presses) * step]), windows: windows,
                        reported: reported)
                }

                #expect(presses == 8, "the divider moved \(presses) times from 50% in steps of \(step), it should stop at 90% after 8")
                let limit = 0.1 * run.screen.visibleFrame.width
                #expect(
                    abs(measured[1].width - limit) <= LinkedRun.frameTolerance,
                    "B is \(measured[1].width) pt wide at the limit, 10% of the display is \(limit) pt")

                // A further press changes nothing.
                for _ in 0..<2 {
                    let nothing = try await run.pressExpectingNothing(.right, from: windows[0], reason: "cannotMove", refocus: false)
                    #expect(nothing.windowNumber == nil)
                }
                run.expectUnmoved(windows, at: measured)
                let group = try run.piccolo.groups().first { $0.display == run.screen.index }
                #expect(group != nil, "the group should still exist at the limit")

                // The other way still works.
                let back = try await run.pressExpectingMove(.left, from: windows[0], refocus: false)
                try await run.expectLayout(
                    LinkedRun.row(dividers: [0.9 - step]), windows: windows, reported: back)
            }
        }

        // MARK: 6. A window that refuses

        @Test("linked 6. a window whose minimum size the move would violate: the divider stops where it ends up, the neighbour fills the rest")
        func minimumSize() async throws {
            let grid = GridSpec(count: 2, rows: 1, columns: 2)
            let screen = try await ArrangeRun.screens()[0]
            // B is half the width. It will not get narrower than 20 points less, which a 5% step passes.
            let half = ArrangeRun.cells(2, in: grid, on: screen).frames[1].width
            let minimum = CGSize(width: half - 20, height: 300)
            guard Self.step * screen.visibleFrame.width > 40 else {
                try Test.cancel(
                    "a step of \(Self.step) is only \(Self.step * screen.visibleFrame.width) pt on this display, too little to cross a margin of 20 pt"
                )
            }

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B"], minSizes: ["B": minimum])
                try await run.arrange(windows, in: grid)

                let reported = try await run.pressExpectingMove(.right, from: windows[0])

                // B stopped at its minimum width, at the right edge of the display; A fills the rest.
                let width = run.screen.visibleFrame.width
                let divider = 1 - minimum.width / width
                let measured = try await run.expectLayout(
                    LinkedRun.row(dividers: [divider]), windows: windows)
                #expect(
                    abs(measured[1].width - minimum.width) <= LinkedRun.frameTolerance,
                    "B is \(measured[1].width) pt wide, its minimum is \(minimum.width) pt")
                #expect(
                    measured[1].maxX >= run.screen.visibleFrame.maxX - LinkedRun.frameTolerance,
                    "B ends at x \(measured[1].maxX), the display's visible frame at x \(run.screen.visibleFrame.maxX)")
                // The report shows that B was asked for less than it took.
                #expect(
                    reported[1].target.width < minimum.width - 10,
                    "B was asked for \(reported[1].target.width) pt, which should be less than its minimum \(minimum.width) pt")
                #expect(
                    (reported[1].achieved?.width ?? 0) >= minimum.width - LinkedRun.frameTolerance,
                    "B is reported at \(reported[1].achieved.map { describe($0) } ?? "no frame"), its minimum width is \(minimum.width) pt")

                // The group holds where the divider is: the other way works, from there.
                let back = try await run.pressExpectingMove(.left, from: windows[0], refocus: false)
                try await run.expectLayout(
                    LinkedRun.row(dividers: [divider - Self.step]), windows: windows, reported: back)
            }
        }

        // MARK: 7. Dissolution

        @Test("linked 7a. after a member is moved, moveDivider does nothing, says why, and the group is gone")
        func movedMemberDissolvesTheGroup() async throws {
            let grid = GridSpec(count: 3, rows: 1, columns: 3)

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "C"])
                let (_, arranged) = try await run.arrange(windows, in: grid)

                // Somebody moves A: 40 pt to the right and 30 pt narrower.
                try await Focus.bring(windows[0], of: run.fixture)
                let moved = CGRect(
                    x: arranged[0].minX + 40, y: arranged[0].minY, width: arranged[0].width - 70,
                    height: arranged[0].height)
                _ = try run.piccolo.setFocusedFrame(moved)
                _ = try await run.waitForFrame(of: windows[0], matching: moved)
                let before = try run.measuredFrames(windows)

                let nothing = try await run.pressExpectingNothing(
                    .right, from: windows[0], reason: "dissolved", refocus: false)

                #expect(nothing.cause == "moved", "the group was dissolved because of \(nothing.cause ?? "nothing") (\(nothing.message)), expected a moved member")
                #expect(
                    nothing.windowNumber == windows[0].windowNumber,
                    "the group was dissolved because of window \(nothing.windowNumber.map(String.init) ?? "none"), the moved one is A = \(windows[0].windowNumber)"
                )
                run.expectUnmoved(windows, at: before)
                try expectNoGroup(containing: windows, on: run)

                // And it stays dissolved.
                _ = try await run.pressExpectingNothing(.right, from: windows[0], reason: "noGroup", refocus: false)
                run.expectUnmoved(windows, at: before)
            }
        }

        @Test("linked 7b. after a member is closed, moveDivider does nothing, says why, and the group is gone")
        func closedMemberDissolvesTheGroup() async throws {
            let grid = GridSpec(count: 3, rows: 1, columns: 3)

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "C"])
                try await run.arrange(windows, in: grid)

                try run.fixture.close(id: "C")
                _ = try await eventually("window C to leave the screen") {
                    Measure.frame(ofWindow: windows[2].windowNumber) == nil
                        ? Observation.satisfied(()) : .unsatisfied("it is still listed as on screen")
                }
                let remaining = Array(windows[0..<2])
                let before = try run.measuredFrames(remaining)

                let nothing = try await run.pressExpectingNothing(.right, from: windows[0], reason: "dissolved")

                #expect(nothing.cause == "missing", "the group was dissolved because of \(nothing.cause ?? "nothing") (\(nothing.message)), expected a missing member")
                #expect(
                    nothing.windowNumber == windows[2].windowNumber,
                    "the group was dissolved because of window \(nothing.windowNumber.map(String.init) ?? "none"), the closed one is C = \(windows[2].windowNumber)"
                )
                run.expectUnmoved(remaining, at: before)
                try expectNoGroup(containing: windows, on: run)
            }
        }

        // MARK: 8. Arranging again

        @Test("linked 8. arranging again replaces the display's group")
        func arrangingAgainReplacesTheGroup() async throws {
            let three = GridSpec(count: 3, rows: 1, columns: 3)
            let two = GridSpec(count: 2, rows: 1, columns: 2)

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "C"])

                try await run.arrange(windows, in: three)
                let first = try run.piccolo.groups().filter { $0.display == run.screen.index }
                #expect(first.count == 1 && first.first?.windows.count == 3, "after the first arrangement: \(first)")

                // A and B again, as two. C is not in the group any more.
                let members = Array(windows[0..<2])
                try await run.arrange(members, in: two)

                let groups = try run.piccolo.groups().filter { $0.display == run.screen.index }
                #expect(groups.count == 1, "the display has \(groups.count) groups, it should have one: \(groups)")
                #expect(
                    groups.first?.windows.map(\.windowNumber) == members.map(\.windowNumber),
                    "the group holds \(groups.first?.windows.map(\.windowNumber) ?? []), expected A and B: \(members.map(\.windowNumber))"
                )
                try expectNoGroup(containing: [windows[2]], on: run)

                // The new group is the one that moves: A | B, one divider.
                let reported = try await run.pressExpectingMove(.right, from: windows[0])
                try await run.expectLayout(
                    LinkedRun.row(dividers: [0.5 + Self.step]), windows: members, reported: reported)
            }
        }

        // MARK: 9. A window in no group

        @Test("linked 9. a focused window that is in no group: nothing happens, in every direction")
        func windowInNoGroup() async throws {
            let grid = GridSpec(count: 2, rows: 1, columns: 2)

            try await withLinkedResize { run in
                let windows = try await run.open(["A", "B", "X"])
                // X was never focused, so the two windows that were are the ones arranged.
                let members = Array(windows[0..<2])
                let (layout, arranged) = try await run.arrange(members, in: grid)
                let outsider = windows[2]
                let outsiderFrame = windows[2].frame
                let before = try run.measuredFrames(windows)

                for key in Direction.allCases {
                    let nothing = try await run.pressExpectingNothing(
                        key, from: outsider, reason: "noGroup", refocus: key == .left)
                    #expect(nothing.windowNumber == nil)
                }

                run.expectUnmoved(windows, at: before)
                #expect(
                    framesMatch(before[2], outsiderFrame),
                    "X was opened at \(describe(outsiderFrame)) and is measured at \(describe(before[2]))")
                // The group of A and B is left as it was.
                try run.expectGroup(members, layout: layout, frames: arranged)
            }
        }

        @Test("linked 9b. with no group at all, a press does nothing")
        func noGroupAtAll() async throws {
            try await withLinkedResize { run in
                let windows = try await run.open(["solo"])
                try await Focus.bring(windows[0], of: run.fixture)
                let before = try run.measuredFrames(windows)

                for key in Direction.allCases {
                    _ = try await run.pressExpectingNothing(key, from: windows[0], reason: "noGroup", refocus: false)
                }

                run.expectUnmoved(windows, at: before)
                try expectNoGroup(containing: windows, on: run)
            }
        }

        // MARK: 10. The step is the config's

        @Test("linked 10. the divider moves by the resize step of the loaded config")
        func stepFromTheConfig() async throws {
            let grid = GridSpec(count: 2, rows: 1, columns: 2)

            for step in [0.1, 0.02] {
                try await withLinkedResize(step: step) { run in
                    let windows = try await run.open(["A", "B"])
                    try await run.arrange(windows, in: grid)

                    let reported = try await run.pressExpectingMove(.right, from: windows[0])

                    try await run.expectLayout(
                        LinkedRun.row(dividers: [0.5 + step]), windows: windows, reported: reported)
                }
            }
        }

        // MARK: Helpers

        private func grid2x2(top: Double, bottom: Double, split: Double = 0.5) -> TileLayout {
            TileLayout(rows: [
                TileLayout.Row(height: split, widths: [top, 1 - top]),
                TileLayout.Row(height: 1 - split, widths: [bottom, 1 - bottom]),
            ])
        }

        /// Checks that Piccolo tracks no group that holds one of these windows.
        private func expectNoGroup(containing windows: [FixtureWindow], on run: LinkedRun) throws {
            let numbers = Set(windows.map(\.windowNumber))
            let groups = try run.piccolo.groups()
            for group in groups where group.windows.contains(where: { numbers.contains($0.windowNumber) }) {
                Issue.record("groups.list still has a group on display \(group.display) with the windows \(group.windows.map(\.windowNumber)), none of \(numbers.sorted()) should be in a group")
            }
        }
    }
}
