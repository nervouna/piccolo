import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// `arrangeGrid` and the groups it records, against fake windows.
@Suite("ActionExecutor: arrangeGrid records a group")
struct ArrangeGroupTests {
    private static let visible = DeskRig.primary.visibleFrame

    @Test("an arrangement records the layout, the windows in cell order, the visible frame and the achieved frames")
    func recordsTheGroup() throws {
        let desk = Desk()
        desk.openWindows(4)

        let outcome = try desk.arrange(count: 4, rows: 2, columns: 2)

        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2)
        let entries = desk.executor.linkedGroups
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.display == outcome.displayIndex)
        #expect(entry.group.layout == layout)
        #expect(entry.group.windows == outcome.windows.map(\.window))
        #expect(entry.group.windows == (1...4).map { DeskRig.id(UInt32($0)) })
        #expect(entry.group.visibleFrame == Self.visible)
        #expect(entry.group.frames == layout.frames(in: Self.visible))
        #expect(entry.group.frames == (try desk.frames(4)))
    }

    @Test("a window that refused its cell is recorded where it ended up")
    func recordsAchievedFrames() throws {
        let desk = Desk()
        desk.openWindows(4)
        // Cell 1 (window 2) is 600 by 400; this window needs 700 by 450.
        desk.window(2).fake.minimumSize = CGSize(width: 700, height: 450)

        let outcome = try desk.arrange(count: 4, rows: 2, columns: 2)

        let group = try #require(desk.executor.linkedGroups.first?.group)
        let cells = TileLayout.grid(windowCount: 4, rows: 2, columns: 2).frames(in: Self.visible)
        #expect(group.layout == TileLayout.grid(windowCount: 4, rows: 2, columns: 2))
        #expect(group.frames[1] != cells[1])
        #expect(group.frames[1].size == CGSize(width: 700, height: 450))
        #expect(
            outcome.windows.map(\.result)
                == group.frames.map { ArrangedWindow.Result.placed(achieved: $0) })
    }

    @Test("an arrangement in which a window failed records no group")
    func failedWindowRecordsNothing() throws {
        let desk = Desk()
        desk.openWindows(4)
        desk.window(3).fake.failSizeWith = .accessibility(operation: "set AXSize", code: -25204)

        let outcome = try desk.arrange(count: 4, rows: 2, columns: 2)

        #expect(outcome.windows.contains { if case .failed = $0.result { true } else { false } })
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("with nothing to arrange there is no group")
    func nothingToArrange() throws {
        let desk = Desk()

        let outcome = try desk.executor.run(.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)), settings: .pinned())

        #expect(outcome == .nothingToDo)
        #expect(desk.executor.linkedGroups.isEmpty)
    }

    @Test("arranging again on a display replaces its group")
    func arrangingAgainReplaces() throws {
        let desk = Desk()
        desk.openWindows(4)
        try desk.arrange(count: 4, rows: 2, columns: 2)

        try desk.arrange(count: 2, rows: 1, columns: 2)

        let entries = desk.executor.linkedGroups
        #expect(entries.count == 1)
        #expect(entries.first?.group.windows == [DeskRig.id(1), DeskRig.id(2)])
        #expect(entries.first?.group.layout == TileLayout.grid(windowCount: 2, rows: 1, columns: 2))
        #expect(desk.store.entry(containing: DeskRig.id(3)) == nil)
    }

    @Test("each display has its own group, and arranging one leaves the other's")
    func onePerDisplay() throws {
        let desk = Desk(displays: [DeskRig.primary, DeskRig.secondary])
        desk.open(1)
        desk.open(2)
        desk.open(3, on: 1)
        desk.open(4, on: 1)

        desk.focused = 1
        desk.focusOrder = [1, 2, 3, 4]
        try desk.arrange(count: 4, rows: 1, columns: 4)
        desk.focused = 3
        desk.focusOrder = [3, 4, 1, 2]
        try desk.arrange(count: 4, rows: 1, columns: 4)

        #expect(desk.executor.linkedGroups.map(\.display) == [0, 1])
        #expect(desk.executor.linkedGroups[0].group.windows == [1, 2].map(DeskRig.id))
        #expect(desk.executor.linkedGroups[1].group.windows == [3, 4].map(DeskRig.id))
        let secondGroup = desk.executor.linkedGroups[1].group

        // Arranging the first display again keeps the second one's group as it was.
        desk.focused = 1
        desk.focusOrder = [1, 2, 3, 4]
        try desk.arrange(count: 1, rows: 1, columns: 1)

        #expect(desk.executor.linkedGroups.map(\.display) == [0, 1])
        #expect(desk.executor.linkedGroups[0].group.windows == [DeskRig.id(1)])
        #expect(desk.executor.linkedGroups[1].group == secondGroup)
    }
}
