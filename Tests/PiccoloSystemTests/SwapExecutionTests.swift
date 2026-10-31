import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// `swapWindow` through the executor, against fake windows on a 1200 by 800 visible frame at (0, 40).
/// The expected frames come from `TileLayout`, not from the code under test.
@Suite("ActionExecutor: swapWindow")
struct SwapExecutionTests {
    static let visible = DeskRig.primary.visibleFrame

    private func id(_ number: UInt32) -> WindowID { DeskRig.id(number) }

    private static func fractions(_ dividers: [Double]) -> [Double] {
        zip([0.0] + dividers, dividers + [1.0]).map { $1 - $0 }
    }

    /// A single row with dividers at these positions (fractions of the width).
    private static func row(_ dividers: [Double]) -> TileLayout {
        TileLayout(rows: [TileLayout.Row(height: 1, widths: fractions(dividers))])
    }

    private func cells(_ layout: TileLayout, gap: Int = 0) -> [CGRect] {
        layout.frames(in: Self.visible, gap: gap)
    }

    private func expectSameLayout(
        _ actual: TileLayout, _ expected: TileLayout, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        func close(_ a: [Double], _ b: [Double]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
        }
        #expect(actual.orientation == expected.orientation, sourceLocation: sourceLocation)
        let matches: Bool
        switch expected.orientation {
        case .rows:
            matches =
                actual.rows.count == expected.rows.count
                && zip(actual.rows, expected.rows).allSatisfy { a, e in
                    abs(a.height - e.height) < 1e-9 && close(a.widths, e.widths)
                }
        case .columns:
            matches =
                actual.columns.count == expected.columns.count
                && zip(actual.columns, expected.columns).allSatisfy { a, e in
                    abs(a.width - e.width) < 1e-9 && close(a.heights, e.heights)
                }
        }
        #expect(matches, "the layout is \(actual), expected \(expected)", sourceLocation: sourceLocation)
    }

    private func group(_ desk: Desk) throws -> LayoutGroup {
        try #require(desk.executor.linkedGroups.first?.group)
    }

    // MARK: Trading cells

    @Test("1 × 2: swap left from the right window exchanges the frames and the order, and keeps the layout")
    func oneByTwo() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        let layout = try group(desk).layout
        desk.focused = 2

        let result = try desk.swapped(.left)

        #expect(try desk.frame(of: 2) == before[0])
        #expect(try desk.frame(of: 1) == before[1])
        let after = try group(desk)
        #expect(after.windows == [id(2), id(1)])
        #expect(after.frames == before)
        expectSameLayout(after.layout, layout)
        #expect(desk.executor.linkedGroups.count == 1)
        #expect(result.display == 0)
        #expect(result.windows.map(\.window) == [id(2), id(1)])
        #expect(result.windows.map(\.target) == before)
        #expect(result.windows.map(\.result) == before.map { ArrangedWindow.Result.placed(achieved: $0) })
    }

    @Test("1 × 2: swap right from the same window, now on the left, brings them back")
    func thereAndBack() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        desk.focused = 2

        try desk.swapped(.left)
        try desk.swapped(.right)

        #expect(try desk.frames(2) == before)
        #expect(try group(desk).windows == [id(1), id(2)])
    }

    @Test("after a divider move to 60 / 40 the windows trade the 60% and the 40% cells")
    func afterADividerMove() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        _ = try desk.moved(.right, step: 0.1)
        let wide = try desk.frame(of: 1)
        let narrow = try desk.frame(of: 2)
        #expect(wide.width == 720 && narrow.width == 480)

        try desk.swapped(.right)

        #expect(try desk.frame(of: 1) == narrow, "window 1 takes the narrow cell")
        #expect(try desk.frame(of: 2) == wide, "window 2 takes the wide cell")
        let after = try group(desk)
        #expect(after.windows == [id(2), id(1)])
        expectSameLayout(after.layout, Self.row([0.6]))

        // The group stays linked: a divider move still works, from the window that moved.
        _ = try desk.moved(.right)
        // Window 1 is in the right cell now, so the move takes the divider on its left: the window in
        // the left cell, window 2, grows.
        #expect(try [desk.frame(of: 2), desk.frame(of: 1)] == cells(Self.row([0.65])))
        #expect(try group(desk).windows == [id(2), id(1)])
    }

    @Test("2 × 2: swap down from the top-left window trades with the bottom-left one, and the other two are not touched")
    func twoByTwo() throws {
        let desk = Desk()
        desk.openWindows(4)
        try desk.arrange(count: 4, rows: 2, columns: 2)
        let before = try desk.frames(4)
        let mark = desk.log.count

        let result = try desk.swapped(.down)

        #expect(try desk.frame(of: 1) == before[2])
        #expect(try desk.frame(of: 3) == before[0])
        #expect(try desk.frame(of: 2) == before[1])
        #expect(try desk.frame(of: 4) == before[3])
        let calls = desk.calls(since: mark)
        #expect(!calls.contains { $0.hasPrefix("2 ") || $0.hasPrefix("4 ") }, "\(calls)")
        #expect(try group(desk).windows == [id(3), id(2), id(1), id(4)])
        #expect(result.windows.map(\.window) == [id(3), id(2), id(1), id(4)])
        // The windows that did not move are listed at the cell they already had.
        #expect(result.windows.map(\.target) == before)
    }

    @Test("2 × 2: every direction from the bottom-right window")
    func twoByTwoDirections() throws {
        let cases: [(Direction, UInt32)] = [(.left, 3), (.up, 2)]
        for (direction, partner) in cases {
            let desk = Desk()
            desk.openWindows(4)
            try desk.arrange(count: 4, rows: 2, columns: 2)
            let before = try desk.frames(4)
            desk.focused = 4

            try desk.swapped(direction)

            #expect(try desk.frame(of: 4) == before[Int(partner) - 1], "\(direction)")
            #expect(try desk.frame(of: partner) == before[3], "\(direction)")
        }
    }

    @Test("three in 2 × 2, rows first: up from the wide bottom window trades with the top-left one")
    func wideBottomWindow() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2)
        let before = try desk.frames(3)
        desk.focused = 3
        let mark = desk.log.count

        try desk.swapped(.up)

        #expect(try desk.frame(of: 3) == before[0])
        #expect(try desk.frame(of: 1) == before[2])
        #expect(!desk.calls(since: mark).contains { $0.hasPrefix("2 ") })
        #expect(try group(desk).windows == [id(3), id(2), id(1)])
    }

    @Test("three in 2 × 2, columns first: right from the bottom-left window trades with the tall right one")
    func columnFirst() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)
        let before = try desk.frames(3)
        let layout = try group(desk).layout
        desk.focused = 2

        try desk.swapped(.right)

        #expect(try desk.frame(of: 2) == before[2])
        #expect(try desk.frame(of: 3) == before[1])
        let after = try group(desk)
        #expect(after.windows == [id(1), id(3), id(2)])
        #expect(after.layout.orientation == .columns)
        expectSameLayout(after.layout, layout)
    }

    @Test("repeated presses carry the focused window across the group, and the focus does not change")
    func carriedAcross() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        let before = try desk.frames(3)
        desk.focused = 1
        let order = desk.order
        let focusOrder = desk.focusOrder

        try desk.swapped(.right)
        try desk.swapped(.right)

        #expect(try desk.frame(of: 1) == before[2])
        #expect(try desk.frame(of: 2) == before[0])
        #expect(try desk.frame(of: 3) == before[1])
        #expect(try group(desk).windows == [id(2), id(3), id(1)])
        #expect(try desk.swap(.right) == .nothingToDo(.noNeighbour(bounced: false)))
        #expect(desk.focused == 1)
        #expect(desk.order == order, "no window was raised")
        #expect(desk.focusOrder == focusOrder)
    }

    @Test("with a window gap, the swapped windows are at the gapped cells")
    func gap() throws {
        let desk = Desk()
        desk.openWindows(2)
        let settings = ActionSettings(gap: 12)
        _ = try desk.executor.run(.arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), settings: settings)
        desk.focused = 2
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2)
        let gapped = cells(layout, gap: 12)
        #expect(try desk.frames(2) == gapped)

        try desk.swapped(.left, settings: settings)

        #expect(try desk.frame(of: 2) == gapped[0])
        #expect(try desk.frame(of: 1) == gapped[1])
        #expect(gapped[1].minX - gapped[0].maxX == 12)
        #expect(try group(desk).windows == [id(2), id(1)])
        // And the group still moves with the gap.
        try desk.swapped(.right, settings: settings)
        #expect(try desk.frames(2) == gapped)
    }

    @Test("a group arranged with one gap swaps with the gap in effect when the key is pressed")
    func gapChangesBetween() throws {
        let desk = Desk()
        desk.openWindows(2)
        _ = try desk.executor.run(
            .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), settings: ActionSettings(gap: 12))
        desk.focused = 2

        try desk.swapped(.left, settings: ActionSettings(gap: 20))

        let wanted = cells(TileLayout.grid(windowCount: 2, rows: 1, columns: 2), gap: 20)
        #expect(try desk.frame(of: 2) == wanted[0])
        #expect(try desk.frame(of: 1) == wanted[1])
    }

    @Test("the swap does not read the resize step")
    func resizeStepIsIrrelevant() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.focused = 2

        let outcome = try desk.swap(.left, settings: ActionSettings(resizeStep: 0))

        guard case .swapped = outcome else {
            Issue.record("expected the windows to swap, got \(outcome)")
            return
        }
    }

    // MARK: Apply order

    @Test("the window that shrinks is sent before the window that grows")
    func shrinkingFirst() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        _ = try desk.moved(.right, step: 0.1)  // window 1: 720 wide, window 2: 480 wide
        let mark = desk.log.count

        // Window 1 goes to the 480 point cell, window 2 to the 720 point cell.
        try desk.swapped(.right)

        let calls = desk.calls(since: mark)
        let shrinkCalls = calls.indices.filter { calls[$0].hasPrefix("1 ") }
        let growCalls = calls.indices.filter { calls[$0].hasPrefix("2 ") }
        #expect(!shrinkCalls.isEmpty && !growCalls.isEmpty, "\(calls)")
        #expect((shrinkCalls.max() ?? 0) < (growCalls.min() ?? 0), "\(calls)")
    }

    // MARK: Nothing to do

    @Test("with no neighbour on that side nothing happens: no window is touched and the group is as it was")
    func noNeighbour() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        let groups = desk.executor.linkedGroups
        let records = desk.executor.windowRecords.map(\.record)
        let mark = desk.log.count

        desk.focused = 1
        #expect(try desk.swap(.left) == .nothingToDo(.noNeighbour(bounced: false)))
        #expect(try desk.swap(.up) == .nothingToDo(.noNeighbour(bounced: false)))
        #expect(try desk.swap(.down) == .nothingToDo(.noNeighbour(bounced: false)))
        desk.focused = 2
        #expect(try desk.swap(.right) == .nothingToDo(.noNeighbour(bounced: false)))

        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frames(2) == before)
        #expect(desk.executor.linkedGroups == groups)
        #expect(desk.executor.windowRecords.map(\.record) == records)
    }

    @Test("a single window in a group has no neighbour")
    func singleWindowGroup() throws {
        let desk = Desk()
        desk.openWindows(1)
        try desk.arrange(count: 1, rows: 1, columns: 1)
        for direction in Direction.allCases {
            #expect(try desk.swap(direction) == .nothingToDo(.noNeighbour(bounced: false)))
        }
    }

    @Test("without a focused window nothing happens, and no window is looked at")
    func noFocusedWindow() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.focused = nil
        let requests = desk.catalogRequests.count
        let mark = desk.log.count

        #expect(try desk.swap(.right) == .nothingToDo(.noFocusedWindow))

        #expect(desk.catalogRequests.count == requests)
        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups.count == 1)
    }

    @Test("a focused window that is in no group: nothing happens, and no window is looked at")
    func noGroup() throws {
        let desk = Desk()
        desk.openWindows(3)
        let before = try desk.frames(3)
        let mark = desk.log.count

        for direction in Direction.allCases {
            #expect(try desk.swap(direction) == .nothingToDo(.noGroup))
        }

        #expect(desk.catalogRequests.isEmpty)
        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frames(3) == before)
    }

    @Test("a focused window outside the display's group is not swapped, and the group is left alone")
    func focusedWindowOutsideTheGroup() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.focused = 3
        let groups = desk.executor.linkedGroups
        let mark = desk.log.count

        #expect(try desk.swap(.left) == .nothingToDo(.noGroup))

        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups == groups)
    }

    // MARK: Dissolution

    @Test("a member that was moved dissolves the group: nothing happens, the outcome says which window")
    func movedMemberDissolves() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        desk.window(3).fake.origin.x += 12
        let moved = try desk.frame(of: 3)
        let mark = desk.log.count
        desk.focused = 2

        let outcome = try desk.swap(.left)

        #expect(outcome == .nothingToDo(.dissolved(.moved(id(3)))))
        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frame(of: 3) == moved)
        #expect(desk.executor.linkedGroups.isEmpty)
        #expect(try desk.swap(.left) == .nothingToDo(.noGroup))
    }

    @Test("the window that was moved by more than two points dissolves the group even when it is the focused one")
    func focusedWindowMoved() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.window(1).fake.origin.x += 3

        #expect(try desk.swap(.right) == .nothingToDo(.dissolved(.moved(id(1)))))
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("a member that was closed dissolves the group")
    func closedMemberDissolves() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        desk.close(3)
        let mark = desk.log.count

        #expect(try desk.swap(.right) == .nothingToDo(.dissolved(.missing(id(3)))))

        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("a drift of two points is read-back noise, not a reason to dissolve")
    func smallDriftKeepsTheGroup() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.window(2).fake.origin.x += 2

        try desk.swapped(.right)

        #expect(desk.executor.linkedGroups.count == 1)
    }

    @Test("onlyPid is passed to the window list, and a group with a window of another process is dissolved, not swapped")
    func onlyPidProtectsOtherProcesses() throws {
        let desk = Desk()
        desk.open(1, pid: 100)
        desk.open(2, pid: 200)
        desk.focused = 1
        desk.focusOrder = [1, 2]
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        let mark = desk.log.count

        let outcome = try desk.swap(.right, onlyPid: 100)

        #expect(desk.catalogRequests.last == .some(100))
        #expect(outcome == .nothingToDo(.dissolved(.missing(id(2)))))
        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frames(2) == before)
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("without onlyPid the whole desk is read, as for a shortcut")
    func noProcessFilter() throws {
        let desk = Desk()
        desk.open(1, pid: 100)
        desk.open(2, pid: 200)
        desk.focused = 1
        desk.focusOrder = [1, 2]
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)

        try desk.swapped(.right)

        #expect(desk.catalogRequests.last == .some(nil))
        #expect(try desk.frame(of: 1) == before[1])
    }

    @Test("a catalog that cannot be read is an error, and the group stays")
    func catalogFails() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.catalogError = WindowError.notTrusted
        let mark = desk.log.count

        #expect(throws: WindowError.notTrusted) { try desk.swap(.right) }

        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups.count == 1)
    }

    // MARK: A window that refuses

    @Test("a window whose minimum is wider than its new cell ends at its minimum, the divider is recorded there and the other window fills the rest")
    func refusalIsCompensated() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        _ = try desk.moved(.right, step: 0.1)  // window 1: 720 wide, window 2: 480 wide
        // Window 1 goes to the 480 point cell on the right and cannot be narrower than 560.
        desk.window(1).fake.minimumSize = CGSize(width: 560, height: 100)

        let result = try desk.swapped(.right)

        // Window 1 ended at x = 640 (shifted back into the display), so the divider is there, and
        // window 2, which was sent to the 720 point cell first, was sent back to 640.
        let divider = 640.0 / 1200
        let expected = cells(Self.row([divider]))
        #expect(try desk.frame(of: 2) == expected[0])
        #expect(try desk.frame(of: 1) == expected[1])
        let a = try desk.frame(of: 2)
        let b = try desk.frame(of: 1)
        #expect(a.maxX == b.minX, "gap or overlap between \(a) and \(b)")
        #expect(a.minX == Self.visible.minX && b.maxX == Self.visible.maxX)

        // The outcome lists the windows in their new order: window 1 was asked for the narrow cell
        // and got 560, window 2 was sent back.
        let askedNarrow = cells(Self.row([0.6]))[1]
        #expect(result.windows.map(\.window) == [id(2), id(1)])
        #expect(result.windows[1].target == askedNarrow)
        #expect(result.windows[1].result == .placed(achieved: expected[1]))
        #expect(result.windows[0].target == expected[0])
        #expect(result.windows[0].result == .placed(achieved: expected[0]))

        // The group recorded where the divider is, and holds.
        let after = try group(desk)
        #expect(abs(after.layout.rows[0].widths[0] - divider) < 1e-9)
        #expect(after.windows == [id(2), id(1)])
        #expect(after.frames == expected)
        // And it still holds: the next swap goes through.
        try desk.swapped(.left)
        #expect(try group(desk).windows == [id(1), id(2)])
    }

    // MARK: A window that fails

    @Test("a window that cannot be changed ends the swap, the other window is not touched, and the group is dissolved")
    func failingFirstWindow() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        desk.focused = 2
        // Both windows keep their size, so they go in cell order, and window 2 is sent to cell 0 first.
        desk.window(2).fake.failSizeWith = .accessibility(operation: "set AXSize", code: -25204)

        let result = try desk.swapped(.left)

        #expect(try desk.frames(2) == before, "window 1 must not move into window 2's cell")
        guard case .failed(let message) = result.windows[0].result else {
            Issue.record("window 2 should be reported as failed: \(result.windows[0])")
            return
        }
        #expect(message.contains("AXSize"))
        guard case .failed(let skipped) = result.windows[1].result else {
            Issue.record("window 1 should be reported as not moved: \(result.windows[1])")
            return
        }
        #expect(skipped.contains("not moved") && skipped.contains("2"))
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("a second window that cannot be changed is reported, the first one stays where it went, and the group is dissolved")
    func failingSecondWindow() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        desk.focused = 2
        desk.window(1).fake.failSizeWith = .accessibility(operation: "set AXSize", code: -25204)

        let result = try desk.swapped(.left)

        #expect(try desk.frame(of: 2) == before[0])
        guard case .placed = result.windows[0].result, case .failed = result.windows[1].result else {
            Issue.record("window 2 should have moved and window 1 failed: \(result.windows)")
            return
        }
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    // MARK: Records

    @Test("both windows are noted: the origin stays, the last achieved frame is the new cell, and the others are left alone")
    func recordsOfBothWindows() throws {
        let desk = Desk()
        desk.openWindows(3)
        let original = try desk.frames(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        let arranged = Dictionary(
            uniqueKeysWithValues: desk.executor.windowRecords.map { ($0.window, $0.record) })
        desk.focused = 1

        try desk.swapped(.right)

        let after = Dictionary(
            uniqueKeysWithValues: desk.executor.windowRecords.map { ($0.window, $0.record) })
        for number in [UInt32(1), 2] {
            let window = id(number)
            #expect(after[window]?.origin == original[Int(number) - 1], "window \(number) keeps its origin")
            #expect(after[window]?.lastAchieved == (try desk.frame(of: number)))
            #expect(after[window]?.lastAchieved != arranged[window]?.lastAchieved, "window \(number) changed")
        }
        #expect(after[id(3)] == arranged[id(3)], "the third window is not involved")
    }

    @Test("a window that failed is not noted, the one that moved is")
    func failedWindowIsNotNoted() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let arranged = Dictionary(
            uniqueKeysWithValues: desk.executor.windowRecords.map { ($0.window, $0.record) })
        desk.focused = 2
        desk.window(1).fake.failSizeWith = .accessibility(operation: "set AXSize", code: -25204)

        try desk.swapped(.left)

        let after = Dictionary(
            uniqueKeysWithValues: desk.executor.windowRecords.map { ($0.window, $0.record) })
        #expect(after[id(1)] == arranged[id(1)])
        #expect(after[id(2)]?.lastAchieved == (try desk.frame(of: 2)))
    }

    @Test("a swap that finds nothing to do notes nothing")
    func nothingNoted() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let records = desk.executor.windowRecords.map(\.record)

        _ = try desk.swap(.left)

        #expect(desk.executor.windowRecords.map(\.record) == records)
    }

    // MARK: The reasons

    @Test("the reasons say what happened")
    func reasons() {
        #expect(SwapOutcome.Reason.dissolved(.moved(DeskRig.id(7))).message.contains("7"))
        #expect(SwapOutcome.Reason.dissolved(.missing(DeskRig.id(7))).message.contains("no longer on screen"))
        #expect(SwapOutcome.Reason.noGroup.message.contains("not in a group"))
        #expect(!SwapOutcome.Reason.noFocusedWindow.message.isEmpty)
        #expect(SwapOutcome.Reason.noNeighbour(bounced: false).message.contains("neighbour"))
    }
}

// MARK: - With an animator

@Suite("ActionExecutor with an animator: swapWindow")
struct AnimatedSwapTests {
    private func makeDesk(clock: FakeClock?) throws -> Desk {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        desk.focused = 1
        if let clock { desk.executor.animator = WindowAnimator(clock) }
        return desk
    }

    @Test("the two windows glide together, and the windows end where they do without animation")
    func sameResult() throws {
        let clock = FakeClock()
        let animated = try makeDesk(clock: clock)
        let plain = try makeDesk(clock: nil)
        let markAnimated = animated.log.count
        let markPlain = plain.log.count

        let outcome = try animated.executor.run(.swapWindow(.right), settings: ActionSettings(animation: .slow))
        let reference = try plain.executor.run(.swapWindow(.right), settings: ActionSettings(animation: .off))

        #expect(outcome == reference)
        #expect(try animated.frames(3) == plain.frames(3))
        #expect(animated.executor.linkedGroups.map(\.group.frames) == plain.executor.linkedGroups.map(\.group.frames))
        // One glide of 0.4 s for both windows.
        #expect(abs(clock.elapsed - 0.4) < 1e-9)
        let plainCalls = plain.calls(since: markPlain)
        let animatedCalls = animated.calls(since: markAnimated)
        #expect(Array(animatedCalls.suffix(plainCalls.count)) == plainCalls)
        #expect(animatedCalls.count > plainCalls.count + 12)
        // The third window is not part of the swap, so it receives no call at all.
        #expect(!animatedCalls.contains { $0.hasPrefix("3 ") }, "\(animatedCalls)")
    }

    @Test("off with an animator makes no intermediate call at all")
    func off() throws {
        let clock = FakeClock()
        let animated = try makeDesk(clock: clock)
        let plain = try makeDesk(clock: nil)
        let markAnimated = animated.log.count
        let markPlain = plain.log.count

        _ = try animated.executor.run(.swapWindow(.right), settings: ActionSettings(animation: .off))
        _ = try plain.executor.run(.swapWindow(.right), settings: ActionSettings(animation: .off))

        #expect(animated.calls(since: markAnimated) == plain.calls(since: markPlain))
        #expect(clock.sleeps.isEmpty)
    }

    @Test("with no neighbour there is nothing to glide: the focused window only bounces, in 0.42 s whatever the speed")
    func noNeighbour() throws {
        let clock = FakeClock()
        let desk = try makeDesk(clock: clock)
        let mark = desk.log.count

        let outcome = try desk.executor.run(.swapWindow(.left), settings: ActionSettings(animation: .slow))

        #expect(outcome == .swap(.nothingToDo(.noNeighbour(bounced: true))))
        #expect(desk.calls(since: mark).allSatisfy { $0 == "1 position" }, "\(desk.calls(since: mark))")
        #expect(abs(clock.elapsed - 0.42) < 1e-9)
    }
}
