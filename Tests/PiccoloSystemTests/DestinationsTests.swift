import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// `ActionExecutor.destinations(for:onlyPid:settings:)`: where an action would send windows, planned
/// without sending any. Every test checks the two things that make it read-only: no window received a
/// call (the desk's log), and the recorded groups are what they were.
@Suite("ActionExecutor: destinations")
struct DestinationsTests {
    private let visible = DeskRig.primary.visibleFrame

    private func id(_ number: UInt32) -> WindowID { DeskRig.id(number) }

    /// The frames of `layout` on the primary display.
    private func cells(_ layout: TileLayout) -> [CGRect] {
        layout.frames(in: visible)
    }

    // MARK: Single-window actions

    @Test("placeWindow answers the resolved frame, without a window, and moves nothing")
    func placeWindow() throws {
        let desk = Desk()
        desk.openWindows(1)
        let before = try desk.frames(1)
        let mark = desk.log.count

        let destinations = try desk.executor.destinations(for: .placeWindow(.preset(.leftHalf)))

        let expected = FrameResolver.frame(
            for: .preset(.leftHalf), visibleFrame: visible, currentFrame: before[0])
        #expect(destinations == [Destination(frame: expected, window: nil)])
        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frames(1) == before)
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("placeWindow answers the same frame the real run sends the window to", arguments: Preset.allCases)
    func placeWindowMatchesTheRun(preset: Preset) throws {
        let desk = Desk()
        desk.openWindows(1)

        let destinations = try desk.executor.destinations(for: .placeWindow(.preset(preset)))
        let outcome = try desk.executor.run(.placeWindow(.preset(preset)))

        guard case .placed(let target, _) = outcome else {
            Issue.record("the run answered \(outcome)")
            return
        }
        #expect(destinations.map(\.frame) == [target])
    }

    @Test("moveToDisplay answers the frame on the other display, and nothing to do with one display")
    func moveToDisplay() throws {
        let two = Desk(displays: [DeskRig.primary, DeskRig.secondary])
        two.openWindows(1)
        let start = try two.frame(of: 1)
        let mark = two.log.count

        let destinations = try two.executor.destinations(for: .moveToDisplay(.next))

        let expected = DisplayLayout.frame(moving: start, from: DeskRig.primary, to: DeskRig.secondary)
        #expect(destinations == [Destination(frame: expected, window: nil)])
        #expect(two.calls(since: mark).isEmpty)
        #expect(try two.frame(of: 1) == start)

        let one = Desk()
        one.openWindows(1)
        #expect(try one.executor.destinations(for: .moveToDisplay(.next)).isEmpty)
    }

    @Test("planning errors are thrown, and nothing moves: no focused window, a custom frame off the screen")
    func planningErrors() throws {
        let desk = Desk()
        desk.openWindows(1)
        let mark = desk.log.count

        desk.focused = nil
        #expect(throws: WindowError.noFocusedWindow) {
            try desk.executor.destinations(for: .placeWindow(.preset(.leftHalf)))
        }

        desk.focused = 1
        let offScreen = FrameSpec.custom(FractionalRect(x: 0.8, y: 0, width: 0.5, height: 1))
        #expect(throws: ActionPlanningError.self) {
            try desk.executor.destinations(for: .placeWindow(offScreen))
        }
        #expect(desk.calls(since: mark).isEmpty)
    }

    // MARK: arrangeGrid

    @Test("arrangeGrid answers the cell of every window of the arrangement, the most recent window first, and moves nothing")
    func arrangeGrid() throws {
        let desk = Desk()
        desk.openWindows(3)
        let before = try desk.frames(3)
        let mark = desk.log.count
        let grid = GridSpec(count: 3, rows: 2, columns: 2)

        let destinations = try desk.executor.destinations(for: .arrangeGrid(grid))

        let expected = cells(TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .rows))
        #expect(destinations.map(\.frame) == expected)
        #expect(destinations.map(\.window) == [id(1), id(2), id(3)])
        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frames(3) == before)
        #expect(desk.executor.linkedGroups.isEmpty, "a plan must not record a group")
    }

    @Test("arrangeGrid follows the grid fill order of the settings")
    func arrangeGridFillOrder() throws {
        let desk = Desk()
        desk.openWindows(3)
        let grid = GridSpec(count: 3, rows: 2, columns: 2)

        let columns = try desk.executor.destinations(
            for: .arrangeGrid(grid), settings: ActionSettings(gridFillOrder: .columns))

        let expected = cells(TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns))
        #expect(columns.map(\.frame) == expected)
        #expect(columns.map(\.window) == [id(1), id(2), id(3)])
        #expect(columns.map(\.frame) != cells(TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .rows)))
    }

    @Test("the cells of the plan are the targets the real arrangement sends the windows to")
    func arrangeGridMatchesTheRun() throws {
        let planner = Desk()
        planner.openWindows(4)
        let runner = Desk()
        runner.openWindows(4)
        let grid = GridSpec(count: 4, rows: 2, columns: 2)

        let destinations = try planner.executor.destinations(for: .arrangeGrid(grid))
        let arranged = try runner.arrange(count: 4, rows: 2, columns: 2)

        #expect(destinations.map(\.frame) == arranged.windows.map(\.target))
        #expect(destinations.map(\.window) == arranged.windows.map(\.window))
    }

    @Test("arrangeGrid with onlyPid asks the catalog for that process only")
    func arrangeGridOnlyPid() throws {
        let desk = Desk()
        desk.open(1, pid: 100)
        desk.open(2, pid: 200)
        desk.focused = 1
        desk.focusOrder = [1, 2]

        let destinations = try desk.executor.destinations(
            for: .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), onlyPid: 100)

        #expect(destinations.map(\.window) == [id(1)])
        #expect(desk.catalogRequests == [100])
    }

    @Test("arrangeGrid with no window to arrange answers nothing")
    func arrangeGridNothing() throws {
        let desk = Desk()
        #expect(try desk.executor.destinations(for: .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2))).isEmpty)
    }

    @Test("arrangeGrid with a grid that cannot be arranged throws, as the run does")
    func arrangeGridInvalid() throws {
        let desk = Desk()
        desk.openWindows(2)
        #expect(throws: ArrangePlannerError.self) {
            try desk.executor.destinations(for: .arrangeGrid(GridSpec(count: 9, rows: 1, columns: 1)))
        }
    }

    @Test("planning an arrangement leaves the group of an earlier one as it was")
    func arrangeGridKeepsGroups() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let groups = desk.executor.linkedGroups
        let mark = desk.log.count

        _ = try desk.executor.destinations(for: .arrangeGrid(GridSpec(count: 2, rows: 2, columns: 1)))

        #expect(desk.executor.linkedGroups == groups)
        #expect(desk.calls(since: mark).isEmpty)
    }

    // MARK: moveDivider

    @Test("moveDivider answers the frames of the group's windows after the move, in cell order, and moves nothing")
    func moveDivider() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let before = try desk.frames(2)
        let groups = desk.executor.linkedGroups
        let mark = desk.log.count

        let destinations = try desk.executor.destinations(
            for: .moveDivider(.right), settings: ActionSettings(resizeStep: DeskRig.step))

        let expected = cells(
            TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.5 + DeskRig.step, 0.5 - DeskRig.step])]))
        #expect(destinations.map(\.frame) == expected)
        #expect(destinations.map(\.window) == [id(1), id(2)])
        #expect(desk.calls(since: mark).isEmpty)
        #expect(try desk.frames(2) == before)
        #expect(desk.executor.linkedGroups == groups, "a plan must not change the group")
    }

    @Test("the plan of a divider move is what the real move then does")
    func moveDividerMatchesTheRun() throws {
        let desk = Desk()
        desk.openWindows(4)
        try desk.arrange(count: 4, rows: 2, columns: 2)

        let destinations = try desk.executor.destinations(
            for: .moveDivider(.down), settings: ActionSettings(resizeStep: DeskRig.step))
        let moved = try desk.moved(.down)

        #expect(destinations.map(\.frame) == moved.windows.map(\.target))
        #expect(destinations.map(\.window) == moved.windows.map(\.window))
    }

    @Test("moveDivider with no group, or no focused window, answers nothing")
    func moveDividerNoGroup() throws {
        let desk = Desk()
        desk.openWindows(2)
        #expect(try desk.executor.destinations(for: .moveDivider(.right)).isEmpty)

        try desk.arrange(count: 2, rows: 1, columns: 2)
        desk.focused = nil
        #expect(try desk.executor.destinations(for: .moveDivider(.right)).isEmpty)
    }

    @Test("moveDivider with a divider that cannot move that way answers nothing")
    func moveDividerCannotMove() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let mark = desk.log.count

        // A single row has no horizontal divider.
        #expect(try desk.executor.destinations(for: .moveDivider(.up)).isEmpty)
        #expect(desk.calls(since: mark).isEmpty)
        #expect(desk.executor.linkedGroups.count == 1)
    }

    @Test("moveDivider with a broken group answers nothing and does not dissolve it; the real run does")
    func moveDividerBrokenGroup() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        desk.window(2).fake.origin.x += 12
        let groups = desk.executor.linkedGroups
        let mark = desk.log.count

        #expect(try desk.executor.destinations(for: .moveDivider(.right)).isEmpty)

        #expect(desk.executor.linkedGroups == groups, "the plan must leave the broken group for the real run")
        #expect(desk.calls(since: mark).isEmpty)

        #expect(try desk.move(.right) == .nothingToDo(.dissolved(.moved(id(2)))))
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("moveDivider with a closed member answers nothing and keeps the group")
    func moveDividerMissingMember() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        desk.close(3)
        let groups = desk.executor.linkedGroups

        #expect(try desk.executor.destinations(for: .moveDivider(.left)).isEmpty)
        #expect(desk.executor.linkedGroups == groups)
    }

    @Test("moveDivider with onlyPid and a member of another process answers nothing and keeps the group")
    func moveDividerOnlyPid() throws {
        let desk = Desk()
        desk.open(1, pid: 100)
        desk.open(2, pid: 200)
        desk.focused = 1
        desk.focusOrder = [1, 2]
        try desk.arrange(count: 2, rows: 1, columns: 2)
        let groups = desk.executor.linkedGroups

        #expect(try desk.executor.destinations(for: .moveDivider(.right), onlyPid: 100).isEmpty)
        #expect(desk.executor.linkedGroups == groups)
    }

    @Test("moveDivider with a resize step that is not a positive number throws, as the run does")
    func moveDividerInvalidStep() throws {
        let desk = Desk()
        desk.openWindows(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)
        #expect(throws: ActionExecutionError.invalidResizeStep(0)) {
            try desk.executor.destinations(for: .moveDivider(.right), settings: ActionSettings(resizeStep: 0))
        }
    }
}
