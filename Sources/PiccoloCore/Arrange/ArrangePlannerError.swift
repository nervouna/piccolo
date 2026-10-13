/// Why `ArrangePlanner.plan` refuses to arrange windows.
public enum ArrangePlannerError: Error, Equatable, Sendable {
    /// `displayIndex` is not an index into the displays.
    case displayIndexOutOfRange
    /// The grid breaks a rule of the configuration model. The value says which one.
    case invalidGrid(ValidationError)
    /// A cell would be narrower or lower than `ArrangePlanner.minimumCellSide`. Nothing is arranged.
    case cellTooSmall
}
