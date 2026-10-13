import Foundation

extension Preset {
    /// The frame of this preset as fractions of a visible frame, or `nil` for `.center`.
    ///
    /// `.center` keeps the window's size, so it has no fixed fraction. `FrameResolver` handles it.
    public var fractionalRect: FractionalRect? {
        // The same Double value for each third, so that adjacent presets share their edges exactly:
        // third + third is exactly twoThirds in binary floating point.
        let third = 1.0 / 3.0
        let twoThirds = 2.0 / 3.0
        switch self {
        case .leftHalf:
            return FractionalRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf:
            return FractionalRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf:
            return FractionalRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf:
            return FractionalRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft:
            return FractionalRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight:
            return FractionalRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft:
            return FractionalRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight:
            return FractionalRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird:
            return FractionalRect(x: 0, y: 0, width: third, height: 1)
        case .centerThird:
            return FractionalRect(x: third, y: 0, width: third, height: 1)
        case .rightThird:
            return FractionalRect(x: twoThirds, y: 0, width: third, height: 1)
        case .leftTwoThirds:
            return FractionalRect(x: 0, y: 0, width: twoThirds, height: 1)
        case .rightTwoThirds:
            return FractionalRect(x: third, y: 0, width: twoThirds, height: 1)
        case .maximize:
            return FractionalRect(x: 0, y: 0, width: 1, height: 1)
        case .center:
            return nil
        }
    }
}
