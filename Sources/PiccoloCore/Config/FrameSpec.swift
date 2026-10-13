import Foundation

/// Where a window goes: a built-in preset or a custom rectangle.
///
/// The file form is `{"preset": "leftHalf"}` or `{"custom": {"x": …, "y": …, "width": …, "height": …}}`.
public enum FrameSpec: Codable, Equatable, Sendable {
    case preset(Preset)
    case custom(FractionalRect)

    private enum CodingKeys: String, CodingKey {
        case preset
        case custom
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try container.decodeIfPresent(Preset.self, forKey: .preset)
        let custom = try container.decodeIfPresent(FractionalRect.self, forKey: .custom)
        switch (preset, custom) {
        case (let preset?, nil):
            self = .preset(preset)
        case (nil, let custom?):
            self = .custom(custom)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "a frame needs exactly one of \"preset\" or \"custom\""))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preset(let preset):
            try container.encode(preset, forKey: .preset)
        case .custom(let rect):
            try container.encode(rect, forKey: .custom)
        }
    }
}

/// A built-in frame. Resolving it to pixels is the window layer's job.
public enum Preset: String, Codable, CaseIterable, Equatable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    case maximize
    case center
}

/// A rectangle as fractions of a screen's visible frame, with the origin at the top-left.
public struct FractionalRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
