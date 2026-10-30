import CoreGraphics
import Testing

@testable import PiccoloCore

/// The four geometric directions of `moveToDisplay`: which display a direction leads to, and that
/// nothing is found when no display lies that way. Every display here is its own visible frame,
/// in canonical space (y points down).
@Suite("DisplayLayout.neighbor(of:_:in:) for left, right, up and down")
struct DisplayDirectionTests {
    private static func display(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Display {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return Display(frame: frame, visibleFrame: frame)
    }

    @Test("two displays side by side: right and left lead to each other, up and down lead nowhere")
    func sideBySide() {
        let displays = [
            Self.display(0, 0, 1440, 900),  // 0: primary
            Self.display(1440, 0, 1920, 1080),  // 1: to the right
        ]
        #expect(DisplayLayout.neighbor(of: 0, .right, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 1, .left, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 0, .left, in: displays) == 0, "no display to the left: stays put")
        #expect(DisplayLayout.neighbor(of: 1, .right, in: displays) == 1, "no display to the right: stays put")
        #expect(DisplayLayout.neighbor(of: 0, .up, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 0, .down, in: displays) == 0)
    }

    @Test("two displays stacked: up and down lead to each other, left and right lead nowhere")
    func stacked() {
        let displays = [
            Self.display(0, 0, 1440, 900),  // 0: primary
            Self.display(0, -1080, 1920, 1080),  // 1: above it, y is negative
        ]
        #expect(DisplayLayout.neighbor(of: 0, .up, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 1, .down, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 1, .up, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 0, .down, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 0, .left, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 0, .right, in: displays) == 0)
    }

    @Test("three displays in a row: the one next to the source wins, not the one further away")
    func threeInARow() {
        let displays = [
            Self.display(1440, 0, 1920, 1080),  // 0: far right
            Self.display(-1000, 0, 1000, 900),  // 1: far left
            Self.display(0, 0, 1440, 900),  // 2: the middle one
        ]
        #expect(DisplayLayout.neighbor(of: 1, .right, in: displays) == 2, "the middle one, not the far right one")
        #expect(DisplayLayout.neighbor(of: 2, .right, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 2, .left, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 0, .left, in: displays) == 2, "the nearest one to the left, not the far left one")
    }

    @Test("an L shape: a display above the left one of two is not a candidate to the left of the primary")
    func lShape() {
        let displays = [
            Self.display(0, 0, 1440, 900),  // 0: primary
            Self.display(-1000, 0, 1000, 800),  // 1: to its left, overlapping its height
            Self.display(-1000, -800, 1000, 800),  // 2: above display 1, no vertical overlap with the primary
        ]
        #expect(DisplayLayout.neighbor(of: 0, .left, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 2, .down, in: displays) == 1)
        #expect(DisplayLayout.neighbor(of: 1, .up, in: displays) == 2)
        // Display 2 is above the primary but shares no x with it: no overlap, so the nearest one wins.
        #expect(DisplayLayout.neighbor(of: 0, .up, in: displays) == 2)
    }

    @Test("displays of different heights: the one with the largest vertical overlap wins")
    func partialOverlap() {
        let displays = [
            Self.display(0, 0, 1440, 900),  // 0: primary, y 0..900
            Self.display(1440, 800, 1000, 1000),  // 1: right, y 800..1800, overlap 100
            Self.display(1440, -300, 1920, 1500),  // 2: right, y -300..1200, overlap 900
        ]
        #expect(DisplayLayout.neighbor(of: 0, .right, in: displays) == 2)
        #expect(DisplayLayout.neighbor(of: 1, .left, in: displays) == 0)
    }

    @Test("a display that overlaps the source horizontally is not a candidate to its right")
    func overlapIsNotAdjacency() {
        let displays = [
            Self.display(0, 0, 1440, 900),  // 0: primary
            Self.display(500, 0, 1000, 900),  // 1: overlaps the primary's right part
        ]
        #expect(DisplayLayout.neighbor(of: 0, .right, in: displays) == 0)
        #expect(DisplayLayout.neighbor(of: 1, .left, in: displays) == 1)
    }

    @Test("an edge within one point counts as adjacent")
    func tolerance() {
        let displays = [
            Self.display(0, 0, 1440, 900),  // 0: primary
            Self.display(-999, 0, 1000, 900),  // 1: right edge at x = 1, one point into the primary
        ]
        #expect(DisplayLayout.neighbor(of: 0, .left, in: displays) == 1)
    }

    @Test("with no overlapping display, the nearest by the distance between the centres wins")
    func nearestWithoutOverlap() {
        let displays = [
            Self.display(0, 0, 1440, 900),  // 0: primary, centre (720, 450)
            Self.display(1440, 1000, 800, 200),  // 1: to the right, no overlap, centre (1840, 1100)
            Self.display(1440, -1500, 800, 200),  // 2: to the right, no overlap, centre (1840, -1400)
        ]
        #expect(DisplayLayout.neighbor(of: 0, .right, in: displays) == 1)
    }

    @Test("a tie between overlapping displays goes to the smaller horizontal gap, then to the lower index")
    func tieBreaks() {
        let gapTie = [
            Self.display(0, 0, 1440, 900),  // 0: source
            Self.display(1440, 0, 500, 900),  // 1: gap 0, overlap 900
            Self.display(1500, 0, 500, 900),  // 2: gap 60, overlap 900
        ]
        #expect(DisplayLayout.neighbor(of: 0, .right, in: gapTie) == 1)

        let indexTie = [
            Self.display(0, 0, 1440, 900),  // 0: source
            Self.display(1440, 0, 500, 900),  // 1: gap 0
            Self.display(1440, 0, 500, 900),  // 2: identical to 1
        ]
        #expect(DisplayLayout.neighbor(of: 0, .right, in: indexTie) == 1)
    }

    @Test("a single display has no neighbour in any direction", arguments: DisplayDirection.allCases)
    func single(direction: DisplayDirection) {
        let displays = [Self.display(0, 0, 1440, 900)]
        #expect(DisplayLayout.neighbor(of: 0, direction, in: displays) == 0)
    }

    @Test("the four directions follow next and previous in the cases of DisplayDirection")
    func cases() {
        #expect(DisplayDirection.allCases == [.next, .previous, .left, .right, .up, .down])
        #expect(DisplayDirection.allCases.map(\.rawValue) == ["next", "previous", "left", "right", "up", "down"])
    }
}
