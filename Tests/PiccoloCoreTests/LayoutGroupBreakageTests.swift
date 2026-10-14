import CoreGraphics
import Testing

@testable import PiccoloCore

/// `LayoutGroup.breakage(currentFrames:tolerance:)`: which window made a group stop holding.
@Suite("Layout group: breakage")
struct LayoutGroupBreakageTests {
    private static func id(_ number: UInt32) -> WindowID { WindowID(rawValue: number) }

    private static func current(of group: LayoutGroup) -> [WindowID: CGRect] {
        Dictionary(uniqueKeysWithValues: zip(group.windows, group.frames))
    }

    @Test("an intact group has no breakage")
    func intact() {
        let group = LayoutGroupTests.twoByTwo()
        #expect(group.breakage(currentFrames: Self.current(of: group)) == nil)
    }

    @Test("a window that is not among the current frames is missing")
    func missing() {
        let group = LayoutGroupTests.twoByTwo()
        var current = Self.current(of: group)
        current[Self.id(3)] = nil
        #expect(group.breakage(currentFrames: current) == .missing(Self.id(3)))
    }

    @Test("a window further than the tolerance from its recorded frame has moved")
    func moved() {
        let group = LayoutGroupTests.twoByTwo()
        var current = Self.current(of: group)
        current[Self.id(2)] = current[Self.id(2)]!.offsetBy(dx: 0, dy: 3)
        #expect(group.breakage(currentFrames: current) == .moved(Self.id(2)))
    }

    @Test("each of the four edges counts on its own")
    func eachEdge() {
        let group = LayoutGroupTests.twoByTwo()
        let recorded = group.frames[0]
        let changes: [(String, CGRect)] = [
            ("left", CGRect(x: recorded.minX + 3, y: recorded.minY, width: recorded.width - 3, height: recorded.height)),
            ("top", CGRect(x: recorded.minX, y: recorded.minY + 3, width: recorded.width, height: recorded.height - 3)),
            ("right", CGRect(x: recorded.minX, y: recorded.minY, width: recorded.width + 3, height: recorded.height)),
            ("bottom", CGRect(x: recorded.minX, y: recorded.minY, width: recorded.width, height: recorded.height + 3)),
        ]
        for (edge, frame) in changes {
            var current = Self.current(of: group)
            current[Self.id(1)] = frame
            #expect(group.breakage(currentFrames: current) == .moved(Self.id(1)), "the \(edge) edge")
        }
    }

    @Test("a difference of two points or less is not a breakage, three points is")
    func tolerance() {
        let group = LayoutGroupTests.twoByTwo()
        var current = Self.current(of: group)
        current[Self.id(4)] = current[Self.id(4)]!.offsetBy(dx: 2, dy: -2)
        #expect(group.breakage(currentFrames: current) == nil)

        current[Self.id(4)] = group.frames[3].offsetBy(dx: 2.5, dy: 0)
        #expect(group.breakage(currentFrames: current) == .moved(Self.id(4)))
    }

    @Test("the first window in cell order is the one reported, whatever the kind of breakage")
    func firstInCellOrder() {
        let group = LayoutGroupTests.twoByTwo()
        var current = Self.current(of: group)
        current[Self.id(4)] = nil
        current[Self.id(2)] = current[Self.id(2)]!.offsetBy(dx: 10, dy: 0)
        #expect(group.breakage(currentFrames: current) == .moved(Self.id(2)))

        current[Self.id(1)] = nil
        #expect(group.breakage(currentFrames: current) == .missing(Self.id(1)))
    }

    @Test("isIntact agrees with breakage")
    func isIntactAgrees() {
        let group = LayoutGroupTests.twoByTwo()
        var current = Self.current(of: group)
        #expect(group.isIntact(currentFrames: current))
        current[Self.id(1)] = nil
        #expect(!group.isIntact(currentFrames: current))
    }
}
