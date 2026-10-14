import CoreGraphics
import Testing

@testable import PiccoloCore

@Suite("Layout group")
struct LayoutGroupTests {
    private static let visible = LinkedResizeSupport.visible
    private static let windows = LinkedResizeSupport.windows(4)

    /// Four windows in a 2x2 grid, each at the frame the layout gives it.
    static func twoByTwo() -> LayoutGroup {
        let layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2)
        return LayoutGroup(
            layout: layout,
            windows: windows,
            visibleFrame: visible,
            frames: layout.frames(in: visible))
    }

    /// The windows of `group` at the frames they were last measured at.
    static func currentFrames(of group: LayoutGroup) -> [WindowID: CGRect] {
        Dictionary(uniqueKeysWithValues: zip(group.windows, group.frames))
    }

    // MARK: cell(of:)

    @Test("cell(of:) gives the row-major index of a window, and nil for a window outside the group")
    func cellOf() {
        let group = Self.twoByTwo()
        #expect(group.cell(of: WindowID(rawValue: 1)) == 0)
        #expect(group.cell(of: WindowID(rawValue: 2)) == 1)
        #expect(group.cell(of: WindowID(rawValue: 3)) == 2)
        #expect(group.cell(of: WindowID(rawValue: 4)) == 3)
        #expect(group.cell(of: WindowID(rawValue: 99)) == nil)
    }

    // MARK: targetFrames(for:)

    @Test("targetFrames(for:) frames a layout in the group's visible frame")
    func targetFramesUseVisibleFrame() {
        let group = Self.twoByTwo()
        let layout = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.25, 0.75])])
        #expect(group.targetFrames(for: layout) == [
            CGRect(x: 0, y: 0, width: 250, height: 500),
            CGRect(x: 250, y: 0, width: 750, height: 500),
        ])
    }

    // MARK: isIntact

    @Test("a group is intact when every window is at its recorded frame")
    func intactWhenUnchanged() {
        let group = Self.twoByTwo()
        #expect(group.isIntact(currentFrames: Self.currentFrames(of: group)))
    }

    @Test("a group is not intact when one of its windows is missing")
    func missingWindow() {
        let group = Self.twoByTwo()
        var current = Self.currentFrames(of: group)
        current[WindowID(rawValue: 3)] = nil
        #expect(!group.isIntact(currentFrames: current))
    }

    @Test("a group is not intact when a window has moved")
    func movedWindow() {
        let group = Self.twoByTwo()
        var current = Self.currentFrames(of: group)
        current[WindowID(rawValue: 2)] = current[WindowID(rawValue: 2)]!.offsetBy(dx: 10, dy: 0)
        #expect(!group.isIntact(currentFrames: current))
    }

    @Test("a window whose edges are all within the tolerance keeps the group intact")
    func withinTolerance() {
        let group = Self.twoByTwo()
        var current = Self.currentFrames(of: group)
        let recorded = group.frames[1]
        // Every edge is 2 points away, which is the default tolerance itself.
        current[WindowID(rawValue: 2)] = LinkedResizeSupport.movingEdges(
            of: recorded, left: 2, top: -2, right: 2, bottom: -2)
        #expect(group.isIntact(currentFrames: current))
    }

    @Test("one edge beyond the tolerance makes the group not intact, whichever edge it is")
    func edgeBeyondTolerance() {
        let group = Self.twoByTwo()
        let recorded = group.frames[3]
        let beyond: [(String, CGRect)] = [
            ("left", LinkedResizeSupport.movingEdges(of: recorded, left: 3)),
            ("top", LinkedResizeSupport.movingEdges(of: recorded, top: 3)),
            ("right", LinkedResizeSupport.movingEdges(of: recorded, right: -3)),
            ("bottom", LinkedResizeSupport.movingEdges(of: recorded, bottom: -3)),
        ]
        for (edge, frame) in beyond {
            var current = Self.currentFrames(of: group)
            current[WindowID(rawValue: 4)] = frame
            #expect(!group.isIntact(currentFrames: current), "\(edge) edge 3 points away")
        }
    }

    @Test("a custom tolerance is used instead of the default")
    func customTolerance() {
        let group = Self.twoByTwo()
        var current = Self.currentFrames(of: group)
        current[WindowID(rawValue: 1)] = group.frames[0].offsetBy(dx: 1, dy: 0)
        #expect(group.isIntact(currentFrames: current, tolerance: 1))
        #expect(!group.isIntact(currentFrames: current, tolerance: 0.5))
    }
}
