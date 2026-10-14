import CoreGraphics
import Testing

@testable import PiccoloCore

/// `LayoutGroup.recordAchieved(requested:achieved:)`: a window that refused its frame, or was
/// pushed back into its display, moves the divider to the edge where it actually ended up.
///
/// The expected layouts are worked out by hand from the frames in each test. The frames are in
/// points, and fractions are the points divided by the visible frame's size.
@Suite("Layout group: recording what was achieved")
struct LayoutGroupRecordTests {
    private static let visible = LinkedResizeSupport.visible
    private static let step = LinkedResizeSupport.step

    /// Two windows side by side, A | B, at 0.5 each, on the 1000 by 500 visible frame.
    static func sideBySide() -> LayoutGroup {
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2)
        return LayoutGroup(
            layout: layout,
            windows: LinkedResizeSupport.windows(2),
            visibleFrame: visible,
            frames: layout.frames(in: visible))
    }

    /// Two windows stacked, one row each, on the 1000 by 500 visible frame.
    static func stacked() -> LayoutGroup {
        let layout = TileLayout.grid(windowCount: 2, rows: 2, columns: 1)
        return LayoutGroup(
            layout: layout,
            windows: LinkedResizeSupport.windows(2),
            visibleFrame: visible,
            frames: layout.frames(in: visible))
    }

    // MARK: Nothing refused

    @Test("when every window reached its frame, the layout is the requested one and the frames are the achieved ones")
    func allReached() throws {
        var group = Self.sideBySide()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .right, step: Self.step))
        let achieved = requested.frames(in: Self.visible)

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, requested))
        #expect(group.frames == achieved)
        #expect(LinkedResizeSupport.isValid(group.layout))
    }

    @Test("a deviation of one point or less is not recorded")
    func withinOnePoint() throws {
        var group = Self.sideBySide()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .right, step: Self.step))
        // The window server may read a frame back one point off.
        let achieved = [
            CGRect(x: 0, y: 0, width: 551, height: 500),
            CGRect(x: 551, y: 0, width: 449, height: 500),
        ]

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, requested))
        #expect(group.frames == achieved)
    }

    // MARK: Side by side

    @Test("a right window that could not get narrower pulls the divider back to where it ended up")
    func rightWindowStoppedByMinimumWidth() throws {
        var group = Self.sideBySide()
        // The move asks for A 550 and B 450. B needs 500 points, so it is placed at 550, sticks
        // out of the display on the right, and is shifted back to x = 500.
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .right, step: Self.step))
        let achieved = [
            CGRect(x: 0, y: 0, width: 550, height: 500),
            CGRect(x: 500, y: 0, width: 500, height: 500),
        ]

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, TileLayout(rows: [
            TileLayout.Row(height: 1, widths: [0.5, 0.5]),
        ])))
        #expect(group.frames == achieved)
        #expect(LinkedResizeSupport.isValid(group.layout))
    }

    @Test("a left window that could not grow leaves a gap, and the divider stops at its right edge")
    func leftWindowStoppedByMaximumWidth() throws {
        var group = Self.sideBySide()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .right, step: Self.step))
        // A asked for 550 points and stopped at 500. B was placed at 550, so there is a gap.
        let achieved = [
            CGRect(x: 0, y: 0, width: 500, height: 500),
            CGRect(x: 550, y: 0, width: 450, height: 500),
        ]

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, TileLayout(rows: [
            TileLayout.Row(height: 1, widths: [0.5, 0.5]),
        ])))
        #expect(group.frames == achieved)
    }

    @Test("a middle window that could not reach its right edge moves that divider to its edge")
    func middleWindowStopped() throws {
        let visible = CGRect(x: 0, y: 0, width: 900, height: 300)
        let layout = TileLayout.grid(windowCount: 3, rows: 1, columns: 3)
        var group = LayoutGroup(
            layout: layout,
            windows: LinkedResizeSupport.windows(3),
            visibleFrame: visible,
            frames: layout.frames(in: visible))
        // Nothing moves, so the requested layout is the current one. B asked for 600 and stopped
        // at 540, so the divider between B and C moves to 0.6 and C fills the rest.
        let achieved = [
            CGRect(x: 0, y: 0, width: 300, height: 300),
            CGRect(x: 300, y: 0, width: 240, height: 300),
            CGRect(x: 600, y: 0, width: 300, height: 300),
        ]

        group.recordAchieved(requested: layout, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, TileLayout(rows: [
            TileLayout.Row(height: 1, widths: [1.0 / 3.0, 0.6 - 1.0 / 3.0, 0.4]),
        ])))
        #expect(LinkedResizeSupport.isValid(group.layout))
    }

    // MARK: Stacked and grids

    @Test("a top window that could not reach its bottom edge moves the divider to where it ended")
    func topWindowStoppedByMaximumHeight() throws {
        var group = Self.stacked()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .down, step: Self.step))
        // The top window asked for 275 points and stopped at 260. The bottom one fills from 260.
        let achieved = [
            CGRect(x: 0, y: 0, width: 1000, height: 260),
            CGRect(x: 0, y: 275, width: 1000, height: 225),
        ]

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, TileLayout(rows: [
            TileLayout.Row(height: 0.52, widths: [1]),
            TileLayout.Row(height: 0.48, widths: [1]),
        ])))
        #expect(group.frames == achieved)
    }

    @Test("a bottom window pushed up by the bottom edge of the display moves the divider back")
    func bottomWindowShiftedUp() throws {
        var group = Self.stacked()
        let requested = try #require(DividerMove.plan(
            layout: group.layout, focusedCell: 0, direction: .down, step: Self.step))
        // The bottom window asked for 225 points at y = 275 but needs 250. It sticks out at the
        // bottom and is shifted up to y = 250.
        let achieved = [
            CGRect(x: 0, y: 0, width: 1000, height: 275),
            CGRect(x: 0, y: 250, width: 1000, height: 250),
        ]

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, TileLayout(rows: [
            TileLayout.Row(height: 0.5, widths: [1]),
            TileLayout.Row(height: 0.5, widths: [1]),
        ])))
    }

    @Test("2x2: a window that could not reach its height moves the divider of the whole grid")
    func gridRowStopped() throws {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2)
        var group = LayoutGroup(
            layout: layout,
            windows: LinkedResizeSupport.windows(4),
            visibleFrame: Self.visible,
            frames: layout.frames(in: Self.visible))
        let requested = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .down, step: Self.step))
        // Only the top-left window stops, at 260 instead of 275. The other three are as asked.
        let achieved = [
            CGRect(x: 0, y: 0, width: 500, height: 260),
            CGRect(x: 500, y: 0, width: 500, height: 275),
            CGRect(x: 0, y: 275, width: 500, height: 225),
            CGRect(x: 500, y: 275, width: 500, height: 225),
        ]

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, TileLayout(rows: [
            TileLayout.Row(height: 0.52, widths: [0.5, 0.5]),
            TileLayout.Row(height: 0.48, widths: [0.5, 0.5]),
        ])))
        #expect(group.frames == achieved)
    }

    // MARK: Fallback

    @Test("a window that runs past the next divider keeps the requested fractions of its row")
    func overflowPastNextDividerKeepsRequested() throws {
        let visible = CGRect(x: 0, y: 0, width: 900, height: 300)
        let layout = TileLayout.grid(windowCount: 3, rows: 1, columns: 3)
        var group = LayoutGroup(
            layout: layout,
            windows: LinkedResizeSupport.windows(3),
            visibleFrame: visible,
            frames: layout.frames(in: visible))
        let requested = try #require(DividerMove.plan(
            layout: layout, focusedCell: 0, direction: .right, step: Self.step))
        // A needs 700 points, so its right edge would pass the divider between B and C. The
        // positions would then be out of order, so the row keeps the requested widths.
        let achieved = [
            CGRect(x: 0, y: 0, width: 700, height: 300),
            CGRect(x: 345, y: 0, width: 210, height: 300),
            CGRect(x: 555, y: 0, width: 345, height: 300),
        ]

        group.recordAchieved(requested: requested, achieved: achieved)

        #expect(LinkedResizeSupport.isClose(group.layout, requested))
        #expect(LinkedResizeSupport.isValid(group.layout))
        #expect(group.frames == achieved)
    }
}
