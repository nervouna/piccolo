import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

extension Desk {
    /// Arranges the most recently focused windows with the given fill order in the settings.
    @discardableResult
    func arrange(
        count: Int, rows: Int, columns: Int, fillOrder: GridFillOrder, onlyPid: pid_t? = nil
    ) throws -> ArrangeOutcome {
        let outcome = try executor.run(
            .arrangeGrid(GridSpec(count: count, rows: rows, columns: columns)), onlyPid: onlyPid,
            settings: ActionSettings.pinned(gridFillOrder: fillOrder))
        guard case .arranged(let arranged) = outcome else {
            throw DeskFailure("expected an arrangement, got \(outcome)")
        }
        return arranged
    }
}

/// `arrangeGrid` with `gridFillOrder` set to columns first, and `moveDivider` on the group it records,
/// against fake windows on a 1200 by 800 visible frame at (0, 40). A 5% step is 60 points across and
/// 40 points down.
@Suite("ActionExecutor: column-first grids")
struct ArrangeColumnFirstTests {
    private static let visible = DeskRig.primary.visibleFrame
    private static let step = DeskRig.step

    private static func column(_ width: Double, _ heights: [Double]) -> TileLayout.Column {
        TileLayout.Column(width: width, heights: heights)
    }

    private func expectFrames(
        _ desk: Desk, _ layout: TileLayout, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let expected = layout.frames(in: Self.visible)
        #expect(try desk.frames(expected.count) == expected, sourceLocation: sourceLocation)
    }

    // MARK: Arranging

    @Test("three windows in 2×2: the two most recent stacked on the left, the third at full height on the right")
    func threeInTwoByTwo() throws {
        let desk = Desk()
        desk.openWindows(3)

        let outcome = try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)

        #expect(outcome.windows.map(\.window) == [1, 2, 3].map(DeskRig.id))
        #expect(try desk.frames(3) == [
            CGRect(x: 0, y: 40, width: 600, height: 400),
            CGRect(x: 0, y: 440, width: 600, height: 400),
            CGRect(x: 600, y: 40, width: 600, height: 800),
        ])
    }

    @Test("two windows in 2×2 are stacked top and bottom at full width")
    func twoInTwoByTwo() throws {
        let desk = Desk()
        desk.openWindows(2)

        try desk.arrange(count: 2, rows: 2, columns: 2, fillOrder: .columns)

        #expect(try desk.frames(2) == [
            CGRect(x: 0, y: 40, width: 1200, height: 400),
            CGRect(x: 0, y: 440, width: 1200, height: 400),
        ])
    }

    @Test("rows first, set explicitly, is what it always was, and columns first is the default")
    func rowsFirstIsUnchanged() throws {
        let rowsFirst = [
            CGRect(x: 0, y: 40, width: 600, height: 400),
            CGRect(x: 600, y: 40, width: 600, height: 400),
            CGRect(x: 0, y: 440, width: 1200, height: 400),
        ]
        let explicit = Desk()
        explicit.openWindows(3)
        try explicit.arrange(count: 3, rows: 2, columns: 2, fillOrder: .rows)
        #expect(try explicit.frames(3) == rowsFirst)
        #expect(explicit.executor.linkedGroups.first?.group.layout.orientation == .rows)

        // Without a fill order in the settings (and no gap, to compare the frames), the grid fills columns first.
        let defaulted = Desk()
        defaulted.openWindows(3)
        _ = try defaulted.executor.run(
            .arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2)), settings: ActionSettings(gap: 0))
        #expect(
            try defaulted.frames(3) == [
                CGRect(x: 0, y: 40, width: 600, height: 400),
                CGRect(x: 0, y: 440, width: 600, height: 400),
                CGRect(x: 600, y: 40, width: 600, height: 800),
            ])
        #expect(defaulted.executor.linkedGroups.first?.group.layout.orientation == .columns)
    }

    @Test("the group records the column layout, the windows in column-major cell order and the frames")
    func recordsAColumnGroup() throws {
        let desk = Desk()
        desk.openWindows(3)

        let outcome = try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)

        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns)
        let entry = try #require(desk.executor.linkedGroups.first)
        #expect(desk.executor.linkedGroups.count == 1)
        #expect(entry.display == outcome.displayIndex)
        #expect(entry.group.layout == layout)
        #expect(entry.group.layout.orientation == .columns)
        #expect(entry.group.layout.columns.map { $0.heights.count } == [2, 1])
        #expect(entry.group.windows == [1, 2, 3].map(DeskRig.id))
        #expect(entry.group.visibleFrame == Self.visible)
        #expect(entry.group.frames == layout.frames(in: Self.visible))
        #expect(entry.group.frames == (try desk.frames(3)))
    }

    @Test("arranging again with the other fill order replaces the group")
    func otherFillOrderReplacesTheGroup() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)

        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .rows)

        let group = try #require(desk.executor.linkedGroups.first?.group)
        #expect(desk.executor.linkedGroups.count == 1)
        #expect(group.layout == TileLayout.grid(windowCount: 3, rows: 2, columns: 2))
        #expect(group.layout.orientation == .rows)
    }

    // MARK: Moving a divider

    @Test("right from a left window: both left windows grow by the step and the right window shrinks")
    func rightFromTheLeftColumn() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)
        let step = Self.step

        for focused: UInt32 in [1, 2] {
            desk.focused = focused
            let moved = try desk.moved(.right)

            let expected = TileLayout(columns: [
                Self.column(0.5 + step, [0.5, 0.5]),
                Self.column(0.5 - step, [1]),
            ])
            try expectFrames(desk, expected)
            #expect(moved.windows.map(\.window) == [1, 2, 3].map(DeskRig.id))
            #expect(moved.windows.map(\.target) == expected.frames(in: Self.visible))

            // And back, for the next window.
            _ = try desk.moved(.left)
            try expectFrames(desk, TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns))
        }
    }

    @Test("left from the right window moves the same divider")
    func leftFromTheRightColumn() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)
        desk.focused = 3

        _ = try desk.moved(.left)

        try expectFrames(desk, TileLayout(columns: [
            Self.column(0.5 - Self.step, [0.5, 0.5]),
            Self.column(0.5 + Self.step, [1]),
        ]))
    }

    @Test("down from the top-left window: only the windows of the left column change")
    func downFromTheTopLeft() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)
        let rightBefore = try desk.frame(of: 3)
        let mark = desk.log.count

        let moved = try desk.moved(.down)

        try expectFrames(desk, TileLayout(columns: [
            Self.column(0.5, [0.5 + Self.step, 0.5 - Self.step]),
            Self.column(0.5, [1]),
        ]))
        #expect(try desk.frame(of: 3) == rightBefore)
        #expect(!desk.calls(since: mark).contains { $0.hasPrefix("3 ") }, "\(desk.calls(since: mark))")
        #expect(moved.windows.map(\.window) == [1, 2, 3].map(DeskRig.id))
    }

    @Test("a horizontal divider of a left window leaves the lone right window without a divider to move")
    func rightWindowHasNoHorizontalDivider() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)
        desk.focused = 3
        let mark = desk.log.count

        #expect(try desk.move(.up) == .nothingToDo(.cannotMove))
        #expect(try desk.move(.down) == .nothingToDo(.cannotMove))
        #expect(desk.calls(since: mark).isEmpty)
    }

    @Test("in 2×2 the horizontal divider moves in both columns, and the group follows the moves")
    func fullGridDown() throws {
        let desk = Desk()
        desk.openWindows(4)
        try desk.arrange(count: 4, rows: 2, columns: 2, fillOrder: .columns)

        _ = try desk.moved(.down)
        _ = try desk.moved(.down)

        let expected = TileLayout(columns: [
            Self.column(0.5, [0.5 + 2 * Self.step, 0.5 - 2 * Self.step]),
            Self.column(0.5, [0.5 + 2 * Self.step, 0.5 - 2 * Self.step]),
        ])
        try expectFrames(desk, expected)
        let group = try #require(desk.executor.linkedGroups.first?.group)
        #expect(group.layout.orientation == .columns)
        #expect(group.frames == (try desk.frames(4)))
        #expect(abs(group.layout.columns[1].heights[0] - (0.5 + 2 * Self.step)) < 1e-9)
    }

    @Test("no two windows overlap at any moment of a move on a column group, in any direction, from any window")
    func neverOverlapping() throws {
        let layouts: [(count: Int, rows: Int, columns: Int)] = [
            (2, 2, 1), (3, 3, 1), (2, 1, 2), (3, 1, 3), (4, 2, 2), (3, 2, 2), (5, 2, 3), (6, 2, 3),
        ]
        for layout in layouts {
            for focused in 1...layout.count {
                for direction in Direction.allCases {
                    let desk = Desk()
                    desk.openWindows(layout.count)
                    try desk.arrange(
                        count: layout.count, rows: layout.rows, columns: layout.columns, fillOrder: .columns)
                    desk.focused = UInt32(focused)
                    desk.startWatchingOverlaps()

                    // Twice, so that the second move starts from a recorded layout.
                    _ = try desk.move(direction)
                    _ = try desk.move(direction)

                    #expect(
                        desk.overlaps.isEmpty,
                        "\(layout.count) windows in \(layout.rows)×\(layout.columns) columns first, window \(focused) \(direction): \(desk.overlaps)"
                    )
                }
            }
        }
    }

    // MARK: A window that refuses

    @Test("a window that refuses its height: the divider stops where it ended up and the neighbour fills the rest")
    func refusalIsCompensated() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 2, columns: 1, fillOrder: .columns)
        // B is 400 high. A move down asks for 360, B cannot be lower than 380.
        desk.window(2).fake.minimumSize = CGSize(width: 100, height: 380)

        let moved = try desk.moved(.down)

        // B ended at y = 460 (shifted back into the display), so the divider is there, and A, which was
        // sent to 440 first, was sent back to 420.
        let divider = 420.0 / 800
        let expected = TileLayout(columns: [Self.column(1, [divider, 1 - divider])]).frames(in: Self.visible)
        #expect(try desk.frames(2) == expected)
        let a = try desk.frame(of: 1)
        let b = try desk.frame(of: 2)
        #expect(a.maxY == b.minY, "gap or overlap between \(a) and \(b)")

        let askedB = TileLayout(columns: [Self.column(1, [0.5 + Self.step, 0.5 - Self.step])])
            .frames(in: Self.visible)[1]
        #expect(moved.windows[1].target == askedB)
        #expect(moved.windows[1].result == .placed(achieved: expected[1]))
        #expect(moved.windows[0].result == .placed(achieved: expected[0]))

        let group = try #require(desk.executor.linkedGroups.first?.group)
        #expect(group.layout.orientation == .columns)
        #expect(abs(group.layout.columns[0].heights[0] - divider) < 1e-9)
        #expect(group.frames == expected)
    }

    @Test("a window that refuses its width moves the divider between columns, and both windows of the other column follow")
    func refusalBetweenColumns() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)
        // The right window is 600 wide. A move right asks for 540, it cannot be narrower than 560.
        desk.window(3).fake.minimumSize = CGSize(width: 560, height: 100)

        _ = try desk.moved(.right)

        // It ended at x = 640 (shifted back into the display), so the divider is there for both left windows.
        let divider = 640.0 / 1200
        try expectFrames(desk, TileLayout(columns: [
            Self.column(divider, [0.5, 0.5]),
            Self.column(1 - divider, [1]),
        ]))
        let group = try #require(desk.executor.linkedGroups.first?.group)
        #expect(abs(group.layout.columns[0].width - divider) < 1e-9)
        #expect(group.frames == (try desk.frames(3)))
    }

    // MARK: Dissolution

    @Test("a member that was moved dissolves a column group as well")
    func movedMemberDissolves() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 2, columns: 2, fillOrder: .columns)
        desk.window(2).fake.origin.x += 12
        let mark = desk.log.count

        let outcome = try desk.move(.right)

        #expect(outcome == .nothingToDo(.dissolved(.moved(DeskRig.id(2)))))
        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups.isEmpty)
    }
}
