import CoreGraphics
import Foundation
import Testing

@testable import PiccoloCore

/// The spring of the spec, written out here from its formula rather than read from `EdgeBounce`: the
/// offset at elapsed time `s` is `A · e^(−s/τ) · sin(2πs/T) / m`, with `m` the same product at the first
/// peak `s*`, so that the peak is `A`.
private enum Spring {
    static let amplitude = 16.0
    static let period = 0.26
    static let decay = 0.07
    static let duration = 0.42

    static let omega = 2 * Double.pi / period
    /// The first peak: the first positive root of the derivative, tan(ω s) = ω τ.
    static let peakTime = atan(omega * decay) / omega
    static let peakValue = exp(-peakTime / decay) * sin(omega * peakTime)

    /// The spring at elapsed time `s`, before rounding.
    static func raw(_ s: Double) -> Double {
        amplitude * exp(-s / decay) * sin(omega * s) / peakValue
    }
}

@Suite("EdgeBounce: the constants and the offset")
struct EdgeBounceOffsetTests {
    @Test("the bounce is 16 pt deep and lasts 0.42 s")
    func constants() {
        #expect(EdgeBounce.amplitude == 16)
        #expect(EdgeBounce.duration == 0.42)
    }

    @Test("the offset is exactly 0 at the start and at the end")
    func endpoints() {
        #expect(EdgeBounce.offset(at: 0) == 0)
        #expect(EdgeBounce.offset(at: 1) == 0)
    }

    @Test("the first peak is 16 pt, at s* = 0.043 s, and no offset is deeper")
    func peak() {
        #expect(abs(Spring.peakTime - 0.043) < 0.0005)
        #expect(EdgeBounce.offset(at: Spring.peakTime / Spring.duration) == 16)
        let deepest = (0...420).map { EdgeBounce.offset(at: Double($0) / 420) }.max()
        #expect(deepest == 16)
    }

    @Test("the overshoot past the start is 2 pt deep around s = 0.17 s, and never deeper than 3 pt")
    func overshoot() {
        let around = (150...190).map { EdgeBounce.offset(at: Double($0) / 1000 / Spring.duration) }
        #expect((-3 ... -2).contains(around.min() ?? 0), "the deepest overshoot near 0.17 s is \(around.min() ?? 0)")
        #expect(EdgeBounce.offset(at: 0.17 / Spring.duration) < 0)
        let whole = (0...420).map { EdgeBounce.offset(at: Double($0) / 420) }
        #expect((whole.min() ?? 0) >= -3)
    }

    @Test(
        "the offset follows the damped spring, in whole points",
        arguments: [0.005, 0.02, 0.043, 0.07, 0.1, 0.13, 0.15, 0.17, 0.2, 0.25, 0.3, 0.35, 0.4])
    func formula(s: Double) {
        let raw = Spring.raw(s)
        let offset = EdgeBounce.offset(at: s / Spring.duration)
        let wanted = CGFloat((raw + 0.5).rounded(.down))
        #expect(offset == wanted, "s = \(s): \(raw) gave \(offset)")
        #expect(offset == offset.rounded(), "s = \(s): \(offset) is not a whole number")
    }

    @Test("sampled at 0, 0.02, 0.043, 0.1, 0.13, 0.17, 0.25, 0.35 and 0.42 s the offset is 0, 12, 16, 5, 0, -2, 0, 0 and 0 pt")
    func sampledTimes() {
        let table: [(seconds: Double, offset: CGFloat)] = [
            (0, 0), (0.02, 12), (0.043, 16), (0.1, 5), (0.13, 0), (0.17, -2), (0.25, 0), (0.35, 0), (0.42, 0),
        ]
        for (seconds, offset) in table {
            #expect(EdgeBounce.offset(at: seconds / EdgeBounce.duration) == offset, "s = \(seconds)")
        }
    }

    @Test("it leaves the start going out, is back at the start at 0.13 s, dips past it until 0.26 s and is at rest after")
    func shape() {
        for millisecond in 0...420 {
            let seconds = Double(millisecond) / 1000
            let offset = EdgeBounce.offset(at: seconds / EdgeBounce.duration)
            if seconds < 0.13 {
                #expect(offset >= 0, "s = \(seconds): \(offset) is on the far side of the start")
            } else if seconds < 0.26 {
                #expect(offset <= 0, "s = \(seconds): \(offset) is on the near side of the start")
            } else {
                #expect(offset == 0, "s = \(seconds): the bounce has not settled, \(offset)")
            }
        }
    }

    @Test("every offset is a whole number of points, between the overshoot and the peak")
    func wholePoints() {
        for index in 0...420 {
            let offset = EdgeBounce.offset(at: Double(index) / 420)
            #expect(offset == offset.rounded(), "t = \(Double(index) / 420): \(offset) is not a whole number")
            #expect((-3...16).contains(offset), "t = \(Double(index) / 420): \(offset)")
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

    /// The frame `seconds` into the bounce.
    private func frame(_ direction: Direction, atSeconds seconds: Double) -> CGRect {
        frame(direction, seconds / EdgeBounce.duration)
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
        "at 0, 0.043, 0.13, 0.17 and 0.42 s the frame is the start, 16 pt out, the start, 2 pt past it and the start again",
        arguments: Direction.allCases)
    func keyFrames(direction: Direction) {
        #expect(frame(direction, atSeconds: 0) == start)
        #expect(frame(direction, atSeconds: 0.043) == expected(direction, offset: 16))
        #expect(frame(direction, atSeconds: 0.13) == start)
        #expect(frame(direction, atSeconds: 0.17) == expected(direction, offset: -2))
        #expect(frame(direction, atSeconds: 0.42) == start)
    }

    @Test("left moves the whole frame towards smaller x, and its overshoot is to the right of the start")
    func left() {
        let peak = frame(.left, atSeconds: 0.043)
        #expect(peak.origin == CGPoint(x: 104, y: 90))
        #expect(peak.size == start.size)
        let overshoot = frame(.left, atSeconds: 0.17)
        #expect(overshoot.origin == CGPoint(x: 122, y: 90))
        #expect(overshoot.size == start.size)
    }

    @Test("right moves the whole frame towards larger x, and its overshoot is to the left of the start")
    func right() {
        let peak = frame(.right, atSeconds: 0.043)
        #expect(peak.origin == CGPoint(x: 136, y: 90))
        #expect(peak.size == start.size)
        let overshoot = frame(.right, atSeconds: 0.17)
        #expect(overshoot.origin == CGPoint(x: 118, y: 90))
        #expect(overshoot.size == start.size)
    }

    @Test("down moves the whole frame towards larger y, and its overshoot is above the start")
    func down() {
        let peak = frame(.down, atSeconds: 0.043)
        #expect(peak.origin == CGPoint(x: 120, y: 106))
        #expect(peak.size == start.size)
        let overshoot = frame(.down, atSeconds: 0.17)
        #expect(overshoot.origin == CGPoint(x: 120, y: 88))
        #expect(overshoot.size == start.size)
    }

    @Test(
        "up squashes: the origin and the top edge stay; the height shrinks by 16 pt at the peak and grows by 2 pt on the overshoot")
    func up() {
        let squashed = frame(.up, atSeconds: 0.043)
        #expect(squashed.origin == start.origin)
        #expect(squashed.minY == start.minY)
        #expect(squashed.width == start.width)
        #expect(squashed.height == start.height - 16)
        #expect(squashed.maxY == start.maxY - 16)

        let overshoot = frame(.up, atSeconds: 0.17)
        #expect(overshoot.origin == start.origin)
        #expect(overshoot.minY == start.minY)
        #expect(overshoot.width == start.width)
        #expect(overshoot.height == start.height + 2)
        #expect(overshoot.maxY == start.maxY + 2)
    }

    @Test(
        "the frames of the whole bounce are whole points, and only the side of the key changes",
        arguments: Direction.allCases)
    func wholePoints(direction: Direction) {
        for index in 0...420 {
            let t = Double(index) / 420
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
