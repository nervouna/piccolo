import Foundation

/// What a binding does when its shortcut fires.
///
/// The file form is a flat object with a `type` key, for example
/// `{"type": "placeWindow", "frame": {...}}` or `{"type": "arrangeGrid", "count": 4, "rows": 2, "columns": 2}`.
public enum Action: Codable, Equatable, Sendable {
    /// Places the focused window at a frame.
    case placeWindow(FrameSpec)
    /// Moves the focused window to the next or previous display.
    case moveToDisplay(DisplayDirection)
    /// Arranges the most recently focused windows in a grid.
    case arrangeGrid(GridSpec)
    /// Moves the divider of a linked group by one `resizeStep`.
    case moveDivider(Direction)

    private enum CodingKeys: String, CodingKey {
        case type
        case frame
        case direction
        case count
        case rows
        case columns
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "placeWindow":
            self = .placeWindow(try container.decode(FrameSpec.self, forKey: .frame))
        case "moveToDisplay":
            self = .moveToDisplay(try container.decode(DisplayDirection.self, forKey: .direction))
        case "arrangeGrid":
            self = .arrangeGrid(
                GridSpec(
                    count: try container.decode(Int.self, forKey: .count),
                    rows: try container.decode(Int.self, forKey: .rows),
                    columns: try container.decode(Int.self, forKey: .columns)))
        case "moveDivider":
            self = .moveDivider(try container.decode(Direction.self, forKey: .direction))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "unknown action type \"\(type)\"")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .placeWindow(let frame):
            try container.encode("placeWindow", forKey: .type)
            try container.encode(frame, forKey: .frame)
        case .moveToDisplay(let direction):
            try container.encode("moveToDisplay", forKey: .type)
            try container.encode(direction, forKey: .direction)
        case .arrangeGrid(let grid):
            try container.encode("arrangeGrid", forKey: .type)
            try container.encode(grid.count, forKey: .count)
            try container.encode(grid.rows, forKey: .rows)
            try container.encode(grid.columns, forKey: .columns)
        case .moveDivider(let direction):
            try container.encode("moveDivider", forKey: .type)
            try container.encode(direction, forKey: .direction)
        }
    }
}

public enum DisplayDirection: String, Codable, CaseIterable, Equatable, Sendable {
    case next
    case previous
}

/// The side a divider moves toward.
public enum Direction: String, Codable, CaseIterable, Equatable, Sendable {
    case left
    case right
    case up
    case down
}

/// The `count` most recently focused windows, arranged in `rows` by `columns` cells.
public struct GridSpec: Codable, Equatable, Sendable {
    public var count: Int
    public var rows: Int
    public var columns: Int

    public init(count: Int, rows: Int, columns: Int) {
        self.count = count
        self.rows = rows
        self.columns = columns
    }
}
