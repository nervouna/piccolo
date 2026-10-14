import CoreGraphics
import Testing

@testable import PiccoloCore

@Suite("FrameInterpolation: the curve")
struct EaseOutTests {
    @Test("the curve starts at 0 and ends at exactly 1")
    func endpoints() {
        #expect(FrameInterpolation.easeOut(0) == 0)
        #expect(FrameInterpolation.easeOut(1) == 1)
    }

    @Test("it is the ease-out cubic, 1 - (1 - t)^3", arguments: [0.1, 0.25, 0.5, 0.75, 0.9])
    func formula(t: Double) {
        let expected = 1 - (1 - t) * (1 - t) * (1 - t)
        #expect(abs(FrameInterpolation.easeOut(t) - expected) < 1e-12)
    }

    @Test("half the time covers seven eighths of the way")
    func midpoint() {
        #expect(abs(FrameInterpolation.easeOut(0.5) - 0.875) < 1e-12)
    }

    @Test("it never decreases, and it is above the straight line: fast at first, slow at the end")
    func shape() {
        var previous = 0.0
        var previousStep = Double.infinity
        for index in 1...100 {
            let t = Double(index) / 100
            let value = FrameInterpolation.easeOut(t)
            #expect(value >= previous, "the curve falls at t = \(t)")
            #expect(value >= t, "the curve is below the straight line at t = \(t)")
            let step = value - previous
            #expect(step <= previousStep + 1e-12, "the steps grow again at t = \(t): ease-out slows down")
            previous = value
            previousStep = step
        }
    }

    @Test("a progress outside 0...1 is held at the ends, and a progress that is no number counts as 0")
    func clamped() {
        #expect(FrameInterpolation.easeOut(-0.5) == 0)
        #expect(FrameInterpolation.easeOut(1.5) == 1)
        #expect(FrameInterpolation.easeOut(.nan) == 0)
        #expect(FrameInterpolation.easeOut(.infinity) == 1)
    }
}

@Suite("FrameInterpolation: frames")
struct FrameInterpolationTests {
    private let start = CGRect(x: 100, y: 80, width: 600, height: 400)
    private let target = CGRect(x: 800, y: 40, width: 300, height: 700)

    @Test("progress 0 is exactly the start, progress 1 exactly the target")
    func endsAreExact() {
        #expect(FrameInterpolation.frame(from: start, to: target, progress: 0) == start)
        #expect(FrameInterpolation.frame(from: start, to: target, progress: 1) == target)
    }

    @Test("the ends are exact also for frames that are not whole points")
    func fractionalEndsAreExact() {
        let from = CGRect(x: 10.3, y: 20.7, width: 300.2, height: 200.9)
        let to = CGRect(x: 99.7, y: -5.4, width: 410.6, height: 99.1)

        #expect(FrameInterpolation.frame(from: from, to: to, progress: 0) == from)
        #expect(FrameInterpolation.frame(from: from, to: to, progress: 1) == to)
    }

    @Test("a progress outside 0...1 gives the start or the target")
    func outsideTheRange() {
        #expect(FrameInterpolation.frame(from: start, to: target, progress: -1) == start)
        #expect(FrameInterpolation.frame(from: start, to: target, progress: 2) == target)
        #expect(FrameInterpolation.frame(from: start, to: target, progress: .nan) == start)
    }

    @Test("in between every edge is a whole point, even when the ends are not")
    func wholePoints() {
        let from = CGRect(x: 10.3, y: 20.7, width: 300.2, height: 200.9)
        let to = CGRect(x: 99.7, y: -5.4, width: 410.6, height: 99.1)

        for index in 1..<50 {
            let frame = FrameInterpolation.frame(from: from, to: to, progress: Double(index) / 50)
            for value in [frame.minX, frame.minY, frame.maxX, frame.maxY, frame.width, frame.height] {
                #expect(value == value.rounded(), "progress \(Double(index) / 50): \(frame)")
            }
        }
    }

    @Test("the frame follows the curve: at half the time, seven eighths of the way, edge by edge")
    func followsTheCurve() {
        let frame = FrameInterpolation.frame(from: start, to: target, progress: 0.5)

        // minX 100 -> 800 gives 712.5, which rounds up to 713; minY 80 -> 40 gives 45;
        // maxX 700 -> 1100 gives 1050; maxY 480 -> 740 gives 707.5, which rounds up to 708.
        #expect(frame == CGRect(x: 713, y: 45, width: 1050 - 713, height: 708 - 45))
    }

    @Test(
        "every edge moves one way only, from the start to the target, never past it",
        arguments: [
            (CGRect(x: 100, y: 80, width: 600, height: 400), CGRect(x: 800, y: 40, width: 300, height: 700)),
            (CGRect(x: 0, y: 0, width: 1200, height: 800), CGRect(x: 600, y: 400, width: 600, height: 400)),
            (CGRect(x: 600, y: 400, width: 600, height: 400), CGRect(x: 0, y: 0, width: 1200, height: 800)),
            (CGRect(x: -1200, y: 230, width: 1200, height: 770), CGRect(x: -600, y: 230, width: 600, height: 770)),
            (CGRect(x: 10, y: 10, width: 301, height: 201), CGRect(x: 11, y: 12, width: 303, height: 199)),
        ])
    func edgesAreMonotonic(start: CGRect, target: CGRect) {
        func edges(_ rect: CGRect) -> [CGFloat] { [rect.minX, rect.minY, rect.maxX, rect.maxY] }
        var previous = edges(start)
        for index in 1...200 {
            let progress = Double(index) / 200
            let current = edges(FrameInterpolation.frame(from: start, to: target, progress: progress))
            for edge in 0..<4 {
                let from = edges(start)[edge]
                let to = edges(target)[edge]
                let direction: CGFloat = to >= from ? 1 : -1
                #expect(
                    (current[edge] - previous[edge]) * direction >= 0,
                    "edge \(edge) turns back at progress \(progress)")
                #expect(
                    (to - current[edge]) * direction >= 0, "edge \(edge) passes the target at progress \(progress)")
            }
            previous = current
        }
    }

    @Test("the size never differs by more than a point from the size the curve gives")
    func sizeStaysCloseToTheCurve() {
        for index in 1..<100 {
            let t = Double(index) / 100
            let eased = CGFloat(FrameInterpolation.easeOut(t))
            let frame = FrameInterpolation.frame(from: start, to: target, progress: t)
            #expect(abs(frame.width - (start.width + (target.width - start.width) * eased)) <= 1.0001)
            #expect(abs(frame.height - (start.height + (target.height - start.height) * eased)) <= 1.0001)
        }
    }

    @Test("two windows that share an edge keep sharing it all the way, whatever the progress")
    func sharedEdgesStayShared() {
        // A | B, and the divider moves from x = 600 to x = 661.
        let a0 = CGRect(x: 0, y: 40, width: 600, height: 800)
        let a1 = CGRect(x: 0, y: 40, width: 661, height: 800)
        let b0 = CGRect(x: 600, y: 40, width: 600, height: 800)
        let b1 = CGRect(x: 661, y: 40, width: 539, height: 800)

        for index in 0...100 {
            let t = Double(index) / 100
            let a = FrameInterpolation.frame(from: a0, to: a1, progress: t)
            let b = FrameInterpolation.frame(from: b0, to: b1, progress: t)
            #expect(a.maxX == b.minX, "progress \(t): A ends at \(a.maxX), B starts at \(b.minX)")
            #expect(b.maxX == 1200 && a.minX == 0)
        }
    }

    @Test("a frame on a display at negative coordinates moves as the same frame at positive ones does")
    func translationInvariant() {
        func moved(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -2000, dy: -1000) }
        let from = CGRect(x: 10.3, y: 20.5, width: 300.5, height: 200.25)
        let to = CGRect(x: 99.5, y: 5.5, width: 410.5, height: 99.75)

        for index in 1..<40 {
            let t = Double(index) / 40
            let plain = FrameInterpolation.frame(from: from, to: to, progress: t)
            let shifted = FrameInterpolation.frame(from: moved(from), to: moved(to), progress: t)
            #expect(shifted == moved(plain), "progress \(t)")
        }
    }

    @Test("a frame that does not change stays where it is")
    func staysPut() {
        for index in 0...10 {
            #expect(FrameInterpolation.frame(from: start, to: start, progress: Double(index) / 10) == start)
        }
    }
}
