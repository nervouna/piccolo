import Foundation

/// Why `ArrangePlanner.plan` refuses to arrange windows.
public enum ArrangePlannerError: Error, Equatable, Sendable, LocalizedError {
    /// `displayIndex` is not an index into the displays.
    case displayIndexOutOfRange
    /// The grid breaks a rule of the configuration model. The value says which one.
    case invalidGrid(ValidationError)
    /// A cell would be narrower or lower than `ArrangePlanner.minimumCellSide`. Nothing is arranged.
    case cellTooSmall

    public var errorDescription: String? {
        switch self {
        case .displayIndexOutOfRange:
            return "the display to arrange on does not exist"
        case .invalidGrid(let error):
            return "invalid grid: \(error)"
        case .cellTooSmall:
            return "the grid is too fine for the display: a cell would be smaller than \(Int(ArrangePlanner.minimumCellSide)) pt"
        }
    }
}
