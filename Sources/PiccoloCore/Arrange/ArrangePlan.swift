import CoreGraphics

/// The result of planning a grid arrangement: which windows move, and where.
public struct ArrangePlan: Equatable, Sendable {
    /// The display the windows are arranged on, as an index into the displays given to the planner.
    public var displayIndex: Int
    /// The grid the frames come from. Its `windowCount` equals the number of assignments.
    public var layout: TileLayout
    /// One entry per arranged window, most recently focused first. The first entry takes the
    /// first cell in row-major order, the top-left one.
    public var assignments: [Assignment]

    public init(displayIndex: Int, layout: TileLayout, assignments: [Assignment]) {
        self.displayIndex = displayIndex
        self.layout = layout
        self.assignments = assignments
    }

    /// A window and the frame it is moved to, in the canonical space.
    public struct Assignment: Equatable, Sendable {
        public var window: WindowID
        public var frame: CGRect

        public init(window: WindowID, frame: CGRect) {
            self.window = window
            self.frame = frame
        }
    }
}
