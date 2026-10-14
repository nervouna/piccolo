import CoreGraphics
import Foundation
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for column-first grids: with `gridFillOrder` set to `"columns"`, `arrangeGrid`
/// fills the grid column by column, and a linked resize moves the dividers of the group it records.
///
/// Every test runs inside `withLinkedResize(gridFillOrder: .columns)`: the config in effect (a
/// temporary file, loaded with `config.load`) has no bindings, a known resize step and the fill order
/// `columns`, and afterwards Piccolo is back on its default config (`withConfigDirectory` ends with
/// `config.reload`). Every `arrangeGrid` and every `moveDivider` passes the fixture's pid as `onlyPid`,
/// so the windows of the machine's owner are never arranged. The expected frames come from `TileLayout`
/// on the visible frame of the display the app reports (`Layout.screens()`), within the usual one
/// point; the halves written out in the tests are compared within two points, because a half of an odd
/// size is rounded to a whole point on each side.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the suite
/// it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Column-first grids")
    struct ColumnFirst {
        private static let step = LinkedRun.defaultStep
        private static let threeInTwoByTwo = GridSpec(count: 3, rows: 2, columns: 2)
        private static let tolerance = LinkedRun.frameTolerance

        /// The group `groups.list` reports for the display under test.
        private static func group(of run: LinkedRun) throws -> PiccoloClient.GroupInfo {
            let groups = try run.piccolo.groups()
            guard let group = groups.first(where: { $0.display == run.screen.index }) else {
                throw AcceptanceFailure("groups.list has no group for display \(run.screen.index): \(groups)")
            }
            return group
        }

        private static func expectFrame(
            _ measured: CGRect, is expected: CGRect, _ what: String, sourceLocation: SourceLocation = #_sourceLocation
        ) {
            #expect(
                framesMatch(measured, expected, tolerance: tolerance),
                "\(what) is measured at \(describe(measured)), expected \(describe(expected)) ±\(tolerance)",
                sourceLocation: sourceLocation)
        }

        // MARK: 1. Three windows

        @Test("columns 1. three windows in 2×2: the most recent in the top half of the left column, the second in its bottom half, the third the full height of the right column")
        func threeWindows() async throws {
            try await withLinkedResize(gridFillOrder: .columns) { run in
                let windows = try await run.open(["A", "B", "C"])

                // A is focused last, so it is the most recent window; B is the second, C the third.
                let (layout, frames) = try await run.arrange(windows, in: Self.threeInTwoByTwo)

                let visible = run.screen.visibleFrame
                let half = CGSize(width: visible.width / 2, height: visible.height / 2)
                Self.expectFrame(
                    frames[0], is: CGRect(origin: visible.origin, size: half),
                    "A, the most recent window, which belongs in the top half of the left column,")
                Self.expectFrame(
                    frames[1], is: CGRect(x: visible.minX, y: visible.minY + half.height, width: half.width, height: half.height),
                    "B, the second window, which belongs in the bottom half of the left column,")
                Self.expectFrame(
                    frames[2], is: CGRect(x: visible.minX + half.width, y: visible.minY, width: half.width, height: visible.height),
                    "C, the third window, which belongs in the full height of the right column,")

                // What Piccolo recorded: a column layout with two cells in the first column and one in the
                // second, in the windows' order.
                let group = try Self.group(of: run)
                #expect(
                    group.layout.orientation == .columns,
                    "groups.list reports \(group.layout), expected a layout with columns")
                #expect(
                    group.layout.columns.map { $0.heights.count } == [2, 1],
                    "groups.list reports the cells per column \(group.layout.columns.map { $0.heights.count }), expected [2, 1]")
                #expect(
                    group.windows.map(\.windowNumber) == windows.map(\.windowNumber),
                    "the group holds \(group.windows.map(\.windowNumber)), expected A, B, C = \(windows.map(\.windowNumber)) in cell order")
                #expect(layout.orientation == .columns)
            }
        }

        // MARK: 2. Moving the dividers

        @Test("columns 2. on that group, right from a left window grows both left windows and shrinks the right one; down from the top-left window changes only the left column")
        func movingDividers() async throws {
            let step = Self.step
            try await withLinkedResize(gridFillOrder: .columns) { run in
                let windows = try await run.open(["A", "B", "C"])
                let (_, arranged) = try await run.arrange(windows, in: Self.threeInTwoByTwo)
                let visible = run.screen.visibleFrame

                // Right from the top-left window: the divider between the columns moves right by the step.
                let right = try await run.pressExpectingMove(.right, from: windows[0])

                let widened = LinkedRun.twoColumns(divider: 0.5 + step, left: 2, right: 1)
                let afterRight = try await run.expectLayout(widened, windows: windows, reported: right)
                let wide = step * visible.width
                for index in 0..<2 {
                    Self.expectDelta(
                        afterRight[index].width - arranged[index].width, is: wide,
                        "the left window \(windows[index].id) grew by")
                    #expect(
                        approximatelyEqual(afterRight[index].height, arranged[index].height, tolerance: Self.tolerance),
                        "the left window \(windows[index].id) changed its height from \(arranged[index].height) to \(afterRight[index].height)")
                }
                Self.expectDelta(
                    arranged[2].width - afterRight[2].width, is: wide,
                    "the right window \(windows[2].id) shrank by")
                #expect(
                    approximatelyEqual(afterRight[2].height, arranged[2].height, tolerance: Self.tolerance),
                    "the right window changed its height from \(arranged[2].height) to \(afterRight[2].height)")

                // Down from the top-left window: the horizontal divider of the left column moves down; the
                // right column has no horizontal divider and keeps its window as it is.
                let down = try await run.pressExpectingMove(.down, from: windows[0], refocus: false)

                let lowered = TileLayout(columns: [
                    TileLayout.Column(width: 0.5 + step, heights: [0.5 + step, 0.5 - step]),
                    TileLayout.Column(width: 0.5 - step, heights: [1]),
                ])
                let afterDown = try await run.expectLayout(lowered, windows: windows, reported: down)
                let high = step * visible.height
                Self.expectDelta(
                    afterDown[0].height - afterRight[0].height, is: high,
                    "the top-left window \(windows[0].id) grew by")
                Self.expectDelta(
                    afterRight[1].height - afterDown[1].height, is: high,
                    "the bottom-left window \(windows[1].id) shrank by")
                for index in 0..<2 {
                    #expect(
                        approximatelyEqual(afterDown[index].minX, afterRight[index].minX, tolerance: Self.tolerance)
                            && approximatelyEqual(afterDown[index].width, afterRight[index].width, tolerance: Self.tolerance),
                        "the left window \(windows[index].id) moved sideways: \(describe(afterRight[index])) became \(describe(afterDown[index]))")
                }
                run.expectUnmoved([windows[2]], at: [afterRight[2]])
            }
        }

        // MARK: 3. From the right column

        @Test("columns 3. from the right window, left moves the divider between the columns, and up and down have no divider to move")
        func fromTheRightColumn() async throws {
            let step = Self.step
            try await withLinkedResize(gridFillOrder: .columns) { run in
                let windows = try await run.open(["A", "B", "C"])
                try await run.arrange(windows, in: Self.threeInTwoByTwo)

                let left = try await run.pressExpectingMove(.left, from: windows[2])

                let narrowed = LinkedRun.twoColumns(divider: 0.5 - step, left: 2, right: 1)
                let measured = try await run.expectLayout(narrowed, windows: windows, reported: left)

                for key in [Direction.up, .down] {
                    let nothing = try await run.pressExpectingNothing(
                        key, from: windows[2], reason: "cannotMove", refocus: false)
                    #expect(nothing.windowNumber == nil)
                }
                run.expectUnmoved(windows, at: measured)
            }
        }

        // MARK: 4. Two windows

        @Test("columns 4. two windows in 2×2: stacked top and bottom at full width, in one column")
        func twoWindows() async throws {
            let grid = GridSpec(count: 2, rows: 2, columns: 2)
            try await withLinkedResize(gridFillOrder: .columns) { run in
                let windows = try await run.open(["A", "B"])

                let (_, frames) = try await run.arrange(windows, in: grid)

                let visible = run.screen.visibleFrame
                let half = visible.height / 2
                Self.expectFrame(
                    frames[0], is: CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: half),
                    "A, the most recent window, which belongs on top at full width,")
                Self.expectFrame(
                    frames[1], is: CGRect(x: visible.minX, y: visible.minY + half, width: visible.width, height: half),
                    "B, the second window, which belongs below at full width,")

                let group = try Self.group(of: run)
                #expect(
                    group.layout.orientation == .columns && group.layout.columns.map { $0.heights.count } == [2],
                    "groups.list reports \(group.layout), expected one column with two cells")
            }
        }

        // MARK: Helpers

        /// Checks that a change in size is the expected number of points, within the tolerance.
        private static func expectDelta(
            _ actual: CGFloat, is expected: CGFloat, _ what: String,
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            #expect(
                approximatelyEqual(actual, expected, tolerance: tolerance),
                "\(what) \(actual) pt, expected \(expected) pt ±\(tolerance)", sourceLocation: sourceLocation)
        }
    }
}
