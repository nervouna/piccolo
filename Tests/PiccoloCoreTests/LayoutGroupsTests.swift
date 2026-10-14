import CoreGraphics
import Testing

@testable import PiccoloCore

/// `LayoutGroups`: one group per display, no window in two groups.
@Suite("Layout groups")
struct LayoutGroupsTests {
    private static let visible = LinkedResizeSupport.visible

    private static func id(_ number: UInt32) -> WindowID { WindowID(rawValue: number) }

    /// A side by side group of the windows with these numbers.
    private static func group(_ numbers: UInt32...) -> LayoutGroup {
        let layout = TileLayout.grid(windowCount: numbers.count, rows: 1, columns: numbers.count)
        return LayoutGroup(
            layout: layout, windows: numbers.map(id), visibleFrame: visible,
            frames: layout.frames(in: visible))
    }

    @Test("a new set of groups has none")
    func empty() {
        let groups = LayoutGroups()
        #expect(groups.entries.isEmpty)
        #expect(groups.entry(containing: Self.id(1)) == nil)
    }

    @Test("a recorded group is found by any of its windows, with its display")
    func findByWindow() {
        var groups = LayoutGroups()
        groups.record(Self.group(1, 2, 3), onDisplay: 1)

        for number: UInt32 in 1...3 {
            let entry = groups.entry(containing: Self.id(number))
            #expect(entry?.display == 1)
            #expect(entry?.group == Self.group(1, 2, 3))
        }
        #expect(groups.entry(containing: Self.id(4)) == nil)
    }

    @Test("recording on a display replaces the group it had")
    func replacesTheDisplaysGroup() {
        var groups = LayoutGroups()
        groups.record(Self.group(1, 2), onDisplay: 0)
        groups.record(Self.group(3, 4, 5), onDisplay: 0)

        #expect(groups.entries == [LayoutGroups.Entry(display: 0, group: Self.group(3, 4, 5))])
        #expect(groups.entry(containing: Self.id(1)) == nil)
    }

    @Test("groups on different displays live side by side, listed in display order")
    func oneGroupPerDisplay() {
        var groups = LayoutGroups()
        groups.record(Self.group(3, 4), onDisplay: 1)
        groups.record(Self.group(1, 2), onDisplay: 0)

        #expect(groups.entries.map(\.display) == [0, 1])
        #expect(groups.entry(containing: Self.id(1))?.display == 0)
        #expect(groups.entry(containing: Self.id(4))?.display == 1)
    }

    @Test("arranging a display again leaves the other displays' groups alone")
    func otherDisplaysAreKept() {
        var groups = LayoutGroups()
        groups.record(Self.group(1, 2), onDisplay: 0)
        groups.record(Self.group(3, 4), onDisplay: 1)
        groups.record(Self.group(5, 6), onDisplay: 0)

        #expect(groups.entries.map(\.display) == [0, 1])
        #expect(groups.entry(containing: Self.id(3))?.group == Self.group(3, 4))
    }

    @Test("a window placed again in a group of another display leaves its old group, which is dissolved")
    func aWindowBelongsToOneGroup() {
        var groups = LayoutGroups()
        groups.record(Self.group(1, 2), onDisplay: 0)
        groups.record(Self.group(2, 3), onDisplay: 1)

        #expect(groups.entries.map(\.display) == [1])
        #expect(groups.entry(containing: Self.id(1)) == nil)
        #expect(groups.entry(containing: Self.id(2))?.display == 1)
    }

    @Test("update replaces the group of a display that has one")
    func updateReplaces() {
        var groups = LayoutGroups()
        groups.record(Self.group(1, 2), onDisplay: 0)
        var moved = Self.group(1, 2)
        moved.recordAchieved(
            requested: TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.6, 0.4])]),
            achieved: [CGRect(x: 0, y: 0, width: 600, height: 500), CGRect(x: 600, y: 0, width: 400, height: 500)])

        groups.update(moved, onDisplay: 0)

        #expect(groups.entry(containing: Self.id(1))?.group == moved)
        #expect(moved != Self.group(1, 2))
    }

    @Test("update does not bring back a group that was dissolved")
    func updateAfterDissolve() {
        var groups = LayoutGroups()
        groups.record(Self.group(1, 2), onDisplay: 0)
        groups.dissolve(display: 0)

        groups.update(Self.group(1, 2), onDisplay: 0)

        #expect(groups.entries.isEmpty)
    }

    @Test("dissolve removes the display's group only, and ignores a display without one")
    func dissolve() {
        var groups = LayoutGroups()
        groups.record(Self.group(1, 2), onDisplay: 0)
        groups.record(Self.group(3, 4), onDisplay: 1)

        groups.dissolve(display: 0)
        groups.dissolve(display: 7)

        #expect(groups.entries.map(\.display) == [1])
        #expect(groups.entry(containing: Self.id(1)) == nil)
    }
}
