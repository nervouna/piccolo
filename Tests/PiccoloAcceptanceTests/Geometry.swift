import CoreGraphics
import Foundation

/// How far (in points) two frames may differ and still count as the same. Window
/// servers and apps round to whole points here and there.
let frameTolerance: CGFloat = 1

func approximatelyEqual(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = frameTolerance) -> Bool {
    abs(a - b) <= tolerance
}

func sizesMatch(_ a: CGSize, _ b: CGSize, tolerance: CGFloat = frameTolerance) -> Bool {
    approximatelyEqual(a.width, b.width, tolerance: tolerance)
        && approximatelyEqual(a.height, b.height, tolerance: tolerance)
}

func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = frameTolerance) -> Bool {
    approximatelyEqual(a.minX, b.minX, tolerance: tolerance)
        && approximatelyEqual(a.minY, b.minY, tolerance: tolerance)
        && sizesMatch(a.size, b.size, tolerance: tolerance)
}

/// Whether `value` is a multiple of `step`, within the tolerance.
func isMultiple(_ value: CGFloat, of step: CGFloat, tolerance: CGFloat = frameTolerance) -> Bool {
    let remainder = value.truncatingRemainder(dividingBy: step)
    return remainder <= tolerance || step - remainder <= tolerance
}

/// `(x, y) w×h`, the form every failure message uses for a frame.
func describe(_ rect: CGRect) -> String {
    "(\(number(rect.minX)), \(number(rect.minY))) \(describe(rect.size))"
}

func describe(_ size: CGSize) -> String {
    "\(number(size.width))×\(number(size.height))"
}

private func number(_ value: CGFloat) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
}
