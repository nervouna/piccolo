import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// `moveDivider` through the executor, against fake windows on a 1200 by 800 visible frame. A 5% step
/// is 60 points across and 40 points down. The expected frames come from `TileLayout` on the dividers
/// the design agreed in #8 puts where, not from `DividerMove`.
@Suite("ActionExecutor: moveDivider")
struct DividerMoveExecutorTests {
    static let visible = DeskRig.primary.visibleFrame
    static let step = DeskRig.step
    static let third = 1.0 / 3
    static let twoThirds = 2.0 / 3

    /// The fractions between consecutive dividers, from 0 to 1.
    private static func fractions(_ dividers: [Double]) -> [Double] {
        zip([0.0] + dividers, dividers + [1.0]).map { $1 - $0 }
    }

    /// A single row with dividers at these positions (fractions of the width).
    private static func row(_ dividers: [Double]) -> TileLayout {
        TileLayout(rows: [TileLayout.Row(height: 1, widths: fractions(dividers))])
    }

    /// A single column with dividers at these positions (fractions of the height).
    private static func column(_ dividers: [Double]) -> TileLayout {
        TileLayout(rows: fractions(dividers).map { TileLayout.Row(height: $0, widths: [1]) })
    }

    private func expectFrames(
        _ desk: Desk, _ layout: TileLayout, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let expected = layout.frames(in: Self.visible)
        let actual = try desk.frames(expected.count)
        #expect(actual == expected, sourceLocation: sourceLocation)
    }

    // MARK: Nothing to do

    @Test("without a focused window nothing happens, and no window is looked at")
    func noFocusedWindow() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.focused = nil
        let requests = desk.catalogRequests.count
        let mark = desk.log.count

        let outcome = try desk.move(.right)

        #expect(outcome == .nothingToDo(.noFocusedWindow))
        #expect(desk.catalogRequests.count == requests)
        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups.count == 1)
    }

    @Test("a focused window that is in no group: nothing happens, which is a success")
    func noGroup() throws {
        let desk = Desk()
        desk.openWindows(3)
        let before = try desk.frames(3)
        let mark = desk.log.count

        for direction in Direction.allCases {
            #expect(try desk.move(direction) == .nothingToDo(.noGroup))
        }

        #expect(desk.catalogRequests.isEmpty)
        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frames(3) == before)
    }

    @Test("a focused window outside the display's group is not moved, and the group is left alone")
    func focusedWindowOutsideTheGroup() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.focused = 3
        let mark = desk.log.count
        let group = desk.executor.linkedGroups

        let outcome = try desk.move(.left)

        #expect(outcome == .nothingToDo(.noGroup))
        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups == group)
    }

    @Test("at the limit the divider does not move any further, and a further press does nothing")
    func limit() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)

        var presses = 0
        while presses < 20, case .moved = try desk.move(.right) { presses += 1 }

        // 50% to 10% in steps of 5%.
        #expect(presses == 8)
        let atLimit = Self.row([0.9])
        try expectFrames(desk, atLimit)
        let mark = desk.log.count
        let group = desk.executor.linkedGroups

        #expect(try desk.move(.right) == .nothingToDo(.cannotMove))
        #expect(try desk.move(.right) == .nothingToDo(.cannotMove))

        #expect(desk.calls(since: mark).isEmpty)
        try expectFrames(desk, atLimit)
        #expect(desk.executor.linkedGroups == group)
    }

    @Test("a single window has no divider to move")
    func singleWindow() throws {
        let desk = Desk()
        desk.openWindows(1)
        try desk.arrange(count: 1, rows: 1, columns: 1)
        let mark = desk.log.count

        for direction in Direction.allCases {
            #expect(try desk.move(direction) == .nothingToDo(.cannotMove))
        }
        #expect(desk.calls(since: mark).isEmpty)
    }

    // MARK: Dissolution

    @Test("a member that was moved dissolves the group: nothing happens, the outcome says which window, and the group is gone")
    func movedMemberDissolves() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        let moved = try desk.frame(of: 2)
        desk.window(2).fake.origin.x += 12
        let mark = desk.log.count

        let outcome = try desk.move(.right)

        #expect(outcome == .nothingToDo(.dissolved(.moved(DeskRig.id(2)))))
        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frame(of: 2) == moved.offsetBy(dx: 12, dy: 0))
        #expect(desk.executor.linkedGroups.isEmpty)
        // Once dissolved, the focused window is in no group.
        #expect(try desk.move(.right) == .nothingToDo(.noGroup))
    }

    @Test("a member that was resized dissolves the group")
    func resizedMemberDissolves() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.window(2).fake.size.height -= 30

        #expect(try desk.move(.left) == .nothingToDo(.dissolved(.moved(DeskRig.id(2)))))
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("a member that was closed dissolves the group")
    func closedMemberDissolves() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        desk.close(3)
        let mark = desk.log.count

        let outcome = try desk.move(.right)

        #expect(outcome == .nothingToDo(.dissolved(.missing(DeskRig.id(3)))))
        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("a drift of two points is read-back noise, not a reason to dissolve")
    func smallDriftKeepsTheGroup() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.window(2).fake.origin.x += 2

        _ = try desk.moved(.right)

        #expect(desk.executor.linkedGroups.count == 1)
    }

    @Test("the dissolution reasons say what happened")
    func reasons() {
        #expect(DividerMoveOutcome.Reason.dissolved(.moved(DeskRig.id(7))).message.contains("7"))
        #expect(DividerMoveOutcome.Reason.dissolved(.missing(DeskRig.id(7))).message.contains("no longer on screen"))
        #expect(DividerMoveOutcome.Reason.noGroup.message.contains("not in a group"))
        #expect(!DividerMoveOutcome.Reason.noFocusedWindow.message.isEmpty)
        #expect(!DividerMoveOutcome.Reason.cannotMove.message.isEmpty)
    }

    // MARK: Side by side: the design table of #8

    struct Case: Sendable, CustomTestStringConvertible {
        var focused: UInt32
        var direction: Direction
        /// The dividers after the move, as fractions of the width or the height.
        var dividers: [Double]
        var testDescription: String { "window \(focused) \(direction) → \(dividers)" }
    }

    @Test("A | B | C: every window, left and right, moves the divider the design table names", arguments: [
        // A: the left key moves the divider A|B left, the right key moves it right.
        Case(focused: 1, direction: .left, dividers: [third - step, twoThirds]),
        Case(focused: 1, direction: .right, dividers: [third + step, twoThirds]),
        // B: left moves A|B left (B grows), right moves B|C right (B grows).
        Case(focused: 2, direction: .left, dividers: [third - step, twoThirds]),
        Case(focused: 2, direction: .right, dividers: [third, twoThirds + step]),
        // C: left moves B|C left (C grows), right moves B|C right (C shrinks).
        Case(focused: 3, direction: .left, dividers: [third, twoThirds - step]),
        Case(focused: 3, direction: .right, dividers: [third, twoThirds + step]),
    ])
    func threeSideBySide(_ test: Case) throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        desk.focused = test.focused
        desk.startWatchingOverlaps()

        let moved = try desk.moved(test.direction)

        let expected = Self.row(test.dividers)
        try expectFrames(desk, expected)
        #expect(desk.overlaps.isEmpty, "\(desk.overlaps)")
        let cells = expected.frames(in: Self.visible)
        #expect(moved.windows.map(\.target) == cells)
        #expect(moved.windows.map(\.result) == cells.map { ArrangedWindow.Result.placed(achieved: $0) })
        #expect(moved.windows.map(\.window) == (1...3).map { DeskRig.id(UInt32($0)) })
        // The three windows tile the visible frame.
        let frames = try desk.frames(3)
        #expect(frames[0].minX == Self.visible.minX && frames[2].maxX == Self.visible.maxX)
        #expect(frames[0].maxX == frames[1].minX && frames[1].maxX == frames[2].minX)
        // The group follows what the windows achieved.
        let group = try #require(desk.executor.linkedGroups.first?.group)
        #expect(group.frames == cells)
        #expect(group.layout.rows[0].widths.count == 3)
    }

    @Test("two windows side by side: both windows, both keys, move the one divider", arguments: [
        Case(focused: 1, direction: .left, dividers: [0.5 - step]),
        Case(focused: 1, direction: .right, dividers: [0.5 + step]),
        Case(focused: 2, direction: .left, dividers: [0.5 - step]),
        Case(focused: 2, direction: .right, dividers: [0.5 + step]),
    ])
    func twoSideBySide(_ test: Case) throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.focused = test.focused
        desk.startWatchingOverlaps()

        _ = try desk.moved(test.direction)

        try expectFrames(desk, Self.row(test.dividers))
        #expect(desk.overlaps.isEmpty, "\(desk.overlaps)")
    }

    // MARK: Stacked

    @Test("two stacked: both windows, up and down, move the one divider", arguments: [
        Case(focused: 1, direction: .up, dividers: [0.5 - step]),
        Case(focused: 1, direction: .down, dividers: [0.5 + step]),
        Case(focused: 2, direction: .up, dividers: [0.5 - step]),
        Case(focused: 2, direction: .down, dividers: [0.5 + step]),
    ])
    func twoStacked(_ test: Case) throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 2, columns: 1)
        desk.focused = test.focused
        desk.startWatchingOverlaps()

        _ = try desk.moved(test.direction)

        try expectFrames(desk, Self.column(test.dividers))
        #expect(desk.overlaps.isEmpty, "\(desk.overlaps)")
    }

    @Test("three stacked: up and down from the top, the middle and the bottom window", arguments: [
        // The top window: up moves its bottom edge up, down moves it down.
        Case(focused: 1, direction: .up, dividers: [third - step, twoThirds]),
        Case(focused: 1, direction: .down, dividers: [third + step, twoThirds]),
        // The middle window: up moves its top edge, down moves its bottom edge.
        Case(focused: 2, direction: .up, dividers: [third - step, twoThirds]),
        Case(focused: 2, direction: .down, dividers: [third, twoThirds + step]),
        // The bottom window: both keys move the divider above it.
        Case(focused: 3, direction: .up, dividers: [third, twoThirds - step]),
        Case(focused: 3, direction: .down, dividers: [third, twoThirds + step]),
    ])
    func threeStacked(_ test: Case) throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 3, columns: 1)
        desk.focused = test.focused
        desk.startWatchingOverlaps()

        _ = try desk.moved(test.direction)

        try expectFrames(desk, Self.column(test.dividers))
        #expect(desk.overlaps.isEmpty, "\(desk.overlaps)")
    }

    // MARK: Grids

    @Test("2×2: the vertical divider moves in both rows, from any window")
    func twoByTwoVerticalDivider() throws {
        for focused: UInt32 in 1...4 {
            let desk = Desk()
            desk.openWindows(4)
            try desk.arrange(count: 4, rows: 2, columns: 2)
            desk.focused = focused
            desk.startWatchingOverlaps()

            _ = try desk.moved(.right)

            let expected = TileLayout(rows: [
                TileLayout.Row(height: 0.5, widths: [0.5 + Self.step, 0.5 - Self.step]),
                TileLayout.Row(height: 0.5, widths: [0.5 + Self.step, 0.5 - Self.step]),
            ])
            try expectFrames(desk, expected)
            #expect(desk.overlaps.isEmpty, "window \(focused): \(desk.overlaps)")
        }
    }

    @Test("2×2: the horizontal divider spans both columns")
    func twoByTwoHorizontalDivider() throws {
        let desk = Desk()
        desk.openWindows(4)
        try desk.arrange(count: 4, rows: 2, columns: 2)
        desk.focused = 4
        desk.startWatchingOverlaps()

        _ = try desk.moved(.up)

        let expected = TileLayout(rows: [
            TileLayout.Row(height: 0.5 - Self.step, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.5 + Self.step, widths: [0.5, 0.5]),
        ])
        try expectFrames(desk, expected)
        #expect(desk.overlaps.isEmpty, "\(desk.overlaps)")
    }

    @Test("three in 2×2: a vertical move from a top window does not touch the wide bottom window")
    func threeInTwoByTwo() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2)
        let bottom = try desk.frame(of: 3)
        let mark = desk.log.count

        _ = try desk.moved(.right)

        let expected = TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [0.5 + Self.step, 0.5 - Self.step]),
            TileLayout.Row(height: 0.5, widths: [1]),
        ])
        try expectFrames(desk, expected)
        #expect(try desk.frame(of: 3) == bottom)
        #expect(!desk.calls(since: mark).contains { $0.hasPrefix("3 ") }, "\(desk.calls(since: mark))")
    }

    @Test("three in 2×2: the wide bottom window moves the horizontal divider with up and down")
    func wideBottomWindow() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2)
        desk.focused = 3

        _ = try desk.moved(.up)
        let up = TileLayout(rows: [
            TileLayout.Row(height: 0.5 - Self.step, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.5 + Self.step, widths: [1]),
        ])
        try expectFrames(desk, up)

        // Left and right: the wide window has no divider of its own.
        let mark = desk.log.count
        #expect(try desk.move(.left) == .nothingToDo(.cannotMove))
        #expect(try desk.move(.right) == .nothingToDo(.cannotMove))
        #expect(desk.calls(since: mark).isEmpty)
    }

    // MARK: Apply order

    @Test("the windows that shrink are sent before the windows that grow, whichever way the divider goes")
    func shrinkingWindowsFirst() throws {
        // A | B | C with the focus on each window, and who shrinks and who grows for each key.
        let cases: [(focused: UInt32, direction: Direction, shrinks: UInt32, grows: UInt32)] = [
            (1, .left, 1, 2), (1, .right, 2, 1),
            (2, .left, 1, 2), (2, .right, 3, 2),
            (3, .left, 2, 3), (3, .right, 3, 2),
        ]
        for test in cases {
            let desk = Desk()
            desk.openWindows(3)
            try desk.arrange(count: 3, rows: 1, columns: 3)
            desk.focused = test.focused
            let mark = desk.log.count

            _ = try desk.moved(test.direction)

            let calls = desk.calls(since: mark)
            let shrinkCalls = calls.indices.filter { calls[$0].hasPrefix("\(test.shrinks) ") }
            let growCalls = calls.indices.filter { calls[$0].hasPrefix("\(test.grows) ") }
            let name = "window \(test.focused) \(test.direction)"
            #expect(!shrinkCalls.isEmpty && !growCalls.isEmpty, "\(name): \(calls)")
            #expect(
                (shrinkCalls.max() ?? 0) < (growCalls.min() ?? 0),
                "\(name): window \(test.shrinks) shrinks and window \(test.grows) grows, but the calls were \(calls)")
            // The window that is not involved is not touched at all.
            let bystander = 6 - test.shrinks - test.grows
            #expect(!calls.contains { $0.hasPrefix("\(bystander) ") }, "\(name): \(calls)")
        }
    }

    @Test("in a 2×2 grid both windows that shrink are sent before either window that grows")
    func gridOrder() throws {
        let desk = Desk()
        desk.openWindows(4)
        try desk.arrange(count: 4, rows: 2, columns: 2)
        let mark = desk.log.count

        _ = try desk.moved(.right)

        // Windows 2 and 4 are in the right column and shrink; windows 1 and 3 grow.
        let firstOperations = desk.calls(since: mark).map { $0.split(separator: " ")[0] }
        var seen: [Substring] = []
        for number in firstOperations where !seen.contains(number) { seen.append(number) }
        #expect(seen == ["2", "4", "1", "3"], "\(seen)")
    }

    @Test("no two windows overlap at any moment of a move, in any direction, from any window")
    func neverOverlapping() throws {
        let layouts: [(count: Int, rows: Int, columns: Int)] = [
            (2, 1, 2), (3, 1, 3), (2, 2, 1), (3, 3, 1), (4, 2, 2), (3, 2, 2), (6, 2, 3),
        ]
        for layout in layouts {
            for focused in 1...layout.count {
                for direction in Direction.allCases {
                    let desk = Desk()
                    desk.openWindows(layout.count)
                    try desk.arrange(count: layout.count, rows: layout.rows, columns: layout.columns)
                    desk.focused = UInt32(focused)
                    desk.startWatchingOverlaps()

                    // Twice, so that the second move starts from a recorded layout.
                    _ = try desk.move(direction)
                    _ = try desk.move(direction)

                    #expect(
                        desk.overlaps.isEmpty,
                        "\(layout.count) windows in \(layout.rows)×\(layout.columns), window \(focused) \(direction): \(desk.overlaps)"
                    )
                }
            }
        }
    }

    // MARK: Step

    @Test("the divider moves by the step the caller gives")
    func stepComesFromTheCaller() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)

        _ = try desk.moved(.right, step: 0.1)

        try expectFrames(desk, Self.row([0.6]))
    }

    @Test("the default step is the config's default of 5%")
    func defaultStep() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)

        let outcome = try desk.executor.run(.moveDivider(.right), settings: .pinned())

        guard case .dividerMove(.moved) = outcome else {
            Issue.record("expected the divider to move, got \(outcome)")
            return
        }
        try expectFrames(desk, Self.row([0.5 + Config.defaultResizeStep]))
    }

    // MARK: The group after a move

    @Test("the group is updated, so that the next move starts where the last one ended")
    func groupFollowsTheMoves() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)

        _ = try desk.moved(.right)
        _ = try desk.moved(.right)

        try expectFrames(desk, Self.row([0.5 + 2 * Self.step]))
        let group = try #require(desk.executor.linkedGroups.first?.group)
        #expect(group.frames == (try desk.frames(2)))
        #expect(abs(group.layout.rows[0].widths[0] - (0.5 + 2 * Self.step)) < 1e-9)

        // And back.
        _ = try desk.moved(.left)
        try expectFrames(desk, Self.row([0.5 + Self.step]))
    }

    @Test("the outcome lists every window in cell order, with what it was asked for and what it got")
    func outcomeListsEveryWindow() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        desk.focused = 1

        let moved = try desk.moved(.right)

        let expected = Self.row([Self.third + Self.step, Self.twoThirds]).frames(in: Self.visible)
        #expect(moved.display == 0)
        #expect(moved.windows.map(\.window) == [1, 2, 3].map(DeskRig.id))
        // Window 3 did not have to move: it is listed at the cell it already had.
        #expect(moved.windows.map(\.target) == expected)
        #expect(moved.windows.map(\.result) == expected.map { ArrangedWindow.Result.placed(achieved: $0) })
    }

    // MARK: A window that refuses

    @Test("a window that refuses its size: the divider stops where it ended up and the neighbour fills the rest")
    func refusalIsCompensated() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        // B is 600 wide. A move right asks for 540, B cannot be narrower than 560.
        desk.window(2).fake.minimumSize = CGSize(width: 560, height: 100)

        let moved = try desk.moved(.right)

        // B ended at x = 640 (shifted back into the display), so the divider is there, and A, which
        // was sent to 660 first, was sent back to 640.
        let divider = 640.0 / 1200
        let expected = Self.row([divider]).frames(in: Self.visible)
        #expect(try desk.frames(2) == expected)
        let a = try desk.frame(of: 1)
        let b = try desk.frame(of: 2)
        #expect(a.maxX == b.minX, "gap or overlap between \(a) and \(b)")
        #expect(a.minX == Self.visible.minX && b.maxX == Self.visible.maxX)

        // The outcome shows the refusal: B was asked for 540 and got 560. A's last frame is the one
        // it was sent back to.
        let askedB = Self.row([0.5 + Self.step]).frames(in: Self.visible)[1]
        #expect(moved.windows[1].target == askedB)
        #expect(moved.windows[1].result == .placed(achieved: expected[1]))
        #expect(moved.windows[0].target == expected[0])
        #expect(moved.windows[0].result == .placed(achieved: expected[0]))

        // The group recorded where the divider is, and holds.
        let group = try #require(desk.executor.linkedGroups.first?.group)
        #expect(abs(group.layout.rows[0].widths[0] - divider) < 1e-9)
        #expect(group.frames == expected)
    }

    @Test("after a refusal the group still holds: the next key works from the recorded divider")
    func afterARefusal() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.window(2).fake.minimumSize = CGSize(width: 560, height: 100)
        _ = try desk.moved(.right)

        // Left moves the divider from 640 to 580: B grows, which it accepts.
        _ = try desk.moved(.left)

        let a = try desk.frame(of: 1)
        let b = try desk.frame(of: 2)
        #expect(a.maxX == b.minX, "gap or overlap between \(a) and \(b)")
        #expect(abs(a.width - (640 - 60)) <= 1, "A is \(a.width) wide, the divider should have moved 60 points left of 640")
    }

    @Test("a refusing window in the middle: both neighbours follow it")
    func refusalInTheMiddle() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        // B is 400 wide; moving the A|B divider right asks for 340, and B stays at 380.
        desk.window(2).fake.minimumSize = CGSize(width: 380, height: 100)
        desk.focused = 1

        _ = try desk.moved(.right)

        let frames = try desk.frames(3)
        #expect(frames[0].maxX == frames[1].minX, "gap or overlap between \(frames[0]) and \(frames[1])")
        #expect(frames[1].maxX == frames[2].minX, "gap or overlap between \(frames[1]) and \(frames[2])")
        #expect(frames[1].width >= 380)
        #expect(frames[0].minX == Self.visible.minX && frames[2].maxX == Self.visible.maxX)
    }

    // MARK: A window that fails

    @Test("a window that cannot be changed ends the move, the windows after it are not touched, and the group is dissolved")
    func failingShrinkingWindow() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        // B shrinks first on a move to the right.
        desk.window(2).fake.failSizeWith = .accessibility(operation: "set AXSize", code: -25204)

        let moved = try desk.moved(.right)

        #expect(try desk.frames(2) == before, "A must not grow into B's space when B did not shrink")
        guard case .failed(let message) = moved.windows[1].result else {
            Issue.record("window 2 should be reported as failed: \(moved.windows[1])")
            return
        }
        #expect(message.contains("AXSize"))
        guard case .failed(let skipped) = moved.windows[0].result else {
            Issue.record("window 1 should be reported as not moved: \(moved.windows[0])")
            return
        }
        #expect(skipped.contains("not moved") && skipped.contains("2"))
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("a growing window that cannot be changed is reported, and the group is dissolved")
    func failingGrowingWindow() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.window(1).fake.failSizeWith = .accessibility(operation: "set AXSize", code: -25204)

        let moved = try desk.moved(.right)

        guard case .placed = moved.windows[1].result, case .failed = moved.windows[0].result else {
            Issue.record("window 2 should have moved and window 1 failed: \(moved.windows)")
            return
        }
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    // MARK: Errors and the process filter

    @Test("a catalog that cannot be read is an error, and the group stays")
    func catalogFails() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.catalogError = WindowError.notTrusted
        let mark = desk.log.count

        #expect(throws: WindowError.notTrusted) { try desk.move(.right) }

        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups.count == 1)
    }

    @Test("onlyPid is passed to the window list, and a group with a window of another process is dissolved, not moved")
    func onlyPidProtectsOtherProcesses() throws {
        let desk = Desk()
        desk.open(1, pid: 100)
        desk.open(2, pid: 200)
        desk.focused = 1
        desk.focusOrder = [1, 2]
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        let mark = desk.log.count

        let outcome = try desk.move(.right, onlyPid: 100)

        #expect(desk.catalogRequests.last == .some(100))
        #expect(outcome == .nothingToDo(.dissolved(.missing(DeskRig.id(2)))))
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

        _ = try desk.moved(.right)

        #expect(desk.catalogRequests.last == .some(nil))
        try expectFrames(desk, Self.row([0.5 + Self.step]))
    }
}
