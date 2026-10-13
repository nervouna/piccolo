import CoreGraphics
import Testing

@testable import PiccoloCore

@Suite("FrameFitting")
struct FrameFittingTests {
    private let visible = CGRect(x: -1000, y: 50, width: 1000, height: 700)

    @Test("a frame inside is returned unchanged")
    func inside() {
        let frame = CGRect(x: -900, y: 100, width: 400, height: 300)
        #expect(FrameFitting.shifted(frame, into: visible) == frame)
    }

    @Test("a frame that fills the visible frame is returned unchanged")
    func exactFit() {
        #expect(FrameFitting.shifted(visible, into: visible) == visible)
    }

    @Test("a frame sticking out on the right is shifted left by the overhang")
    func rightOverhang() {
        let frame = CGRect(x: -400, y: 100, width: 500, height: 300)
        #expect(FrameFitting.shifted(frame, into: visible) == CGRect(x: -500, y: 100, width: 500, height: 300))
    }

    @Test("a frame sticking out at the bottom is shifted up by the overhang")
    func bottomOverhang() {
        let frame = CGRect(x: -900, y: 600, width: 400, height: 300)
        #expect(FrameFitting.shifted(frame, into: visible) == CGRect(x: -900, y: 450, width: 400, height: 300))
    }

    @Test("a frame sticking out on both axes is shifted on both")
    func cornerOverhang() {
        let frame = CGRect(x: -100, y: 600, width: 400, height: 300)
        #expect(FrameFitting.shifted(frame, into: visible) == CGRect(x: -400, y: 450, width: 400, height: 300))
    }

    @Test("the size never changes")
    func sizeKept() {
        let frame = CGRect(x: 500, y: 500, width: 123, height: 456)
        #expect(FrameFitting.shifted(frame, into: visible).size == frame.size)
    }

    @Test("a frame wider and taller than the visible frame is aligned to its top-left corner")
    func largerThanVisible() {
        let frame = CGRect(x: -500, y: 300, width: 1200, height: 900)
        let shifted = FrameFitting.shifted(frame, into: visible)
        #expect(shifted.origin == visible.origin)
        #expect(shifted.size == frame.size)
    }

    @Test("only the oversized axis is aligned to the corner")
    func oneAxisLarger() {
        let frame = CGRect(x: -800, y: 300, width: 1200, height: 200)
        #expect(FrameFitting.shifted(frame, into: visible) == CGRect(x: -1000, y: 300, width: 1200, height: 200))
    }

    @Test("the result is never left of or above the top-left corner")
    func neverBeforeCorner() {
        let frame = CGRect(x: -1500, y: -200, width: 300, height: 300)
        let shifted = FrameFitting.shifted(frame, into: visible)
        #expect(shifted.minX >= visible.minX)
        #expect(shifted.minY >= visible.minY)
        #expect(shifted == CGRect(x: -1000, y: 50, width: 300, height: 300))
    }
}
