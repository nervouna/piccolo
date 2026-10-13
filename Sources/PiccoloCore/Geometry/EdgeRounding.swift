import CoreGraphics

/// The one rounding rule for edges and origins in the canonical space.
///
/// A value rounds half up: `(value + 0.5).rounded(.down)`. Unlike rounding ties away from zero,
/// this does not depend on the sign of the value. Shifting the input by a whole number shifts the
/// output by the same number, so a frame on a display at negative coordinates is the frame on a
/// display at positive coordinates, moved.
enum EdgeRounding {
    /// `value` rounded to a whole number, with a half rounded up (towards positive infinity).
    static func round(_ value: CGFloat) -> CGFloat {
        (value + 0.5).rounded(.down)
    }
}
