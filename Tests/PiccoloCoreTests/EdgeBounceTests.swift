import CoreGraphics
import Foundation
import Testing

@testable import PiccoloCore

@Suite("EdgeBounce: the constants and the offset")
struct EdgeBounceOffsetTests {
    @Test("the bounce is 16 pt deep and lasts 0.2 s")
    func constants() {
        #expect(EdgeBounce.amplitude == 16)
        #expect(EdgeBounce.duration == 0.2)
    }

    @Test("the offset is 0 at the start and at the end, and the whole amplitude at the middle")
    func endpoints() {
        #expect(EdgeBounce.offset(at: 0) == 0)
        #expect(EdgeBounce.offset(at: 0.5) == 16)
        #expect(EdgeBounce.offset(at: 1) == 0)
    }

    @Test(
        "up to the middle it follows A × easeOut(2t), after it A × (1 − easeIn(2t − 1)), in whole points",
        arguments: [0.05, 0.1, 0.2, 0.25, 0.3, 0.4, 0.45, 0.55, 0.6, 0.7, 0.75, 0.8, 0.9, 0.95])
    func formula(t: Double) {
        let amplitude = 16.0
        let raw: Double
        if t <= 0.5 {
            let u = 2 * t
            raw = amplitude * (1 - (1 - u) * (1 - u) * (1 - u))
        } else {
            let u = 2 * t - 1
            raw = amplitude * (1 - u * u * u)
        }
        let offset = EdgeBounce.offset(at: t)
        let wanted = CGFloat((raw + 0.5).rounded(.down))
        #expect(offset == wanted, "t = \(t): \(raw) gave \(offset)")
        #expect(offset == offset.rounded(), "t = \(t): \(offset) is not a whole number")
    }

    @Test("a quarter and three quarters of the way are 14 pt out")
    func quarters() {
        #expect(EdgeBounce.offset(at: 0.25) == 14)
        #expect(EdgeBounce.offset(at: 0.75) == 14)
    }

    @Test("it rises to the middle and falls after it, never leaving 0...16")
    func shape() {
        var previous: CGFloat = 0
        for index in 1...50 {
            let offset = EdgeBounce.offset(at: Double(index) / 100)
            #expect(offset >= previous, "the offset falls before the middle at t = \(Double(index) / 100)")
            #expect((0...16).contains(offset))
            previous = offset
        }
        for index in 51...100 {
            let offset = EdgeBounce.offset(at: Double(index) / 100)
            #expect(offset <= previous, "the offset rises after the middle at t = \(Double(index) / 100)")
            #expect((0...16).contains(offset))
            previous = offset
        }
    }

    @Test("a progress outside 0...1 is held at the ends, and one that is no number counts as 0")
    func clamped() {
        #expect(EdgeBounce.offset(at: -0.3) == 0)
        #expect(EdgeBounce.offset(at: 1.7) == 0)
        #expect(EdgeBounce.offset(at: .nan) == 0)
        #expect(EdgeBounce.offset(at: .infinity) == 0)
        #expect(EdgeBounce.offset(at: -.infinity) == 0)
    }
}

@Suite("EdgeBounce: the frames")
struct EdgeBounceFrameTests {
    /// A frame whose origin is not (0, 0), so that a mix-up of absolute and relative values shows.
    private let start = CGRect(x: 120, y: 90, width: 600, height: 400)

    private func frame(_ direction: Direction, _ t: Double) -> CGRect {
        EdgeBounce.frame(from: start, towards: direction, progress: t)
    }

    /// The frame `start` has with the offset applied to the side of `direction`.
    private func expected(_ direction: Direction, offset d: CGFloat) -> CGRect {
        switch direction {
        case .left: CGRect(x: start.minX - d, y: start.minY, width: start.width, height: start.height)
        case .right: CGRect(x: start.minX + d, y: start.minY, width: start.width, height: start.height)
        case .down: CGRect(x: start.minX, y: start.minY + d, width: start.width, height: start.height)
        case .up: CGRect(x: start.minX, y: start.minY, width: start.width, height: start.height - d)
        }
    }

    @Test(
        "at t = 0, 0.25, 0.5, 0.75 and 1 the frame is the start, 14, 16, 14 pt out, and the start again",
        arguments: Direction.allCases)
    func keyFrames(direction: Direction) {
        #expect(frame(direction, 0) == start)
        #expect(frame(direction, 0.25) == expected(direction, offset: 14))
        #expect(frame(direction, 0.5) == expected(direction, offset: 16))
        #expect(frame(direction, 0.75) == expected(direction, offset: 14))
        #expect(frame(direction, 1) == start)
    }

    @Test("left moves the whole frame towards smaller x, and the size stays")
    func left() {
        let moved = frame(.left, 0.5)
        #expect(moved.origin == CGPoint(x: 104, y: 90))
        #expect(moved.size == start.size)
    }

    @Test("right moves the whole frame towards larger x, and the size stays")
    func right() {
        let moved = frame(.right, 0.5)
        #expect(moved.origin == CGPoint(x: 136, y: 90))
        #expect(moved.size == start.size)
    }

    @Test("down moves the whole frame towards larger y, and the size stays")
    func down() {
        let moved = frame(.down, 0.5)
        #expect(moved.origin == CGPoint(x: 120, y: 106))
        #expect(moved.size == start.size)
    }

    @Test("up squashes: the origin and the top edge stay, the bottom edge moves up and the height shrinks")
    func up() {
        let squashed = frame(.up, 0.5)
        #expect(squashed.origin == start.origin)
        #expect(squashed.minY == start.minY)
        #expect(squashed.width == start.width)
        #expect(squashed.height == start.height - 16)
        #expect(squashed.maxY == start.maxY - 16)
    }

    @Test("the frames between the key frames are whole points, and only the side of the key changes", arguments: Direction.allCases)
    func wholePoints(direction: Direction) {
        for index in 0...100 {
            let t = Double(index) / 100
            let moved = frame(direction, t)
            let d = EdgeBounce.offset(at: t)
            #expect(moved == expected(direction, offset: d), "t = \(t)")
            #expect(moved.origin.x == moved.origin.x.rounded() && moved.origin.y == moved.origin.y.rounded())
            #expect(moved.width == moved.width.rounded() && moved.height == moved.height.rounded())
        }
    }

    @Test("the start and the end are exactly the start frame, whatever its edges are", arguments: Direction.allCases)
    func exactEnds(direction: Direction) {
        let odd = CGRect(x: -37.25, y: 12.5, width: 333.75, height: 201.5)
        #expect(EdgeBounce.frame(from: odd, towards: direction, progress: 0) == odd)
        #expect(EdgeBounce.frame(from: odd, towards: direction, progress: 1) == odd)
        #expect(EdgeBounce.frame(from: odd, towards: direction, progress: -1) == odd)
        #expect(EdgeBounce.frame(from: odd, towards: direction, progress: 2) == odd)
        #expect(EdgeBounce.frame(from: odd, towards: direction, progress: .nan) == odd)
    }

    @Test("a frame on a display at negative coordinates bounces the same way, moved", arguments: Direction.allCases)
    func negativeCoordinates(direction: Direction) {
        let shifted = start.offsetBy(dx: -2000, dy: -300)
        for t in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1] {
            let there = EdgeBounce.frame(from: shifted, towards: direction, progress: t)
            let here = frame(direction, t)
            #expect(there == here.offsetBy(dx: -2000, dy: -300), "t = \(t)")
        }
    }
}
