import CoreGraphics
import Testing

@testable import PiccoloCore

@Suite("EdgeRounding")
struct EdgeRoundingTests {
    @Test(
        "a value rounds to the nearest whole number, and a half rounds up",
        arguments: [
            (CGFloat(0.5), CGFloat(1)),
            (CGFloat(1.5), CGFloat(2)),
            (CGFloat(-0.5), CGFloat(0)),
            (CGFloat(-1.5), CGFloat(-1)),
            (CGFloat(-864.5), CGFloat(-864)),
            (CGFloat(2.4), CGFloat(2)),
            (CGFloat(-2.6), CGFloat(-3)),
        ])
    func roundsHalfUp(input: CGFloat, expected: CGFloat) {
        #expect(EdgeRounding.round(input) == expected)
    }

    @Test("a whole number is unchanged", arguments: [-1728, -1, 0, 1, 1440] as [CGFloat])
    func wholeNumbersUnchanged(value: CGFloat) {
        #expect(EdgeRounding.round(value) == value)
    }

    @Test(
        "shifting the input by a whole number shifts the output by the same number",
        arguments: [-864.5, -2.6, -0.5, 0.5, 2.4, 863.5] as [CGFloat],
        [-1728, 355, 1440, -3001] as [CGFloat])
    func shiftsWithInput(value: CGFloat, shift: CGFloat) {
        #expect(EdgeRounding.round(value + shift) == EdgeRounding.round(value) + shift)
    }
}
