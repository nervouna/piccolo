import CoreGraphics

extension LayoutGroup {
    /// One window that has to be sent to a new frame.
    public struct Step: Equatable, Sendable {
        /// The index of the window's cell (see ``LayoutGroup``): row-major for a row layout,
        /// column-major for a column layout.
        public var cell: Int
        public var window: WindowID
        /// The frame to send the window to.
        public var target: CGRect

        public init(cell: Int, window: WindowID, target: CGRect) {
            self.cell = cell
            self.window = window
            self.target = target
        }
    }

    /// Two edges closer than this are the same edge. Targets are whole points, so a real change
    /// is at least one point.
    private static let sameEdgeTolerance: CGFloat = 0.5

    /// The windows to send to new frames, in the order to send them.
    ///
    /// A window is a step when its cell changed (`targets[i]` differs from `previous[i]`) and it is
    /// not already at `targets[i]` (`current[i]`), comparing the four edges within half a point.
    /// The others are left alone.
    ///
    /// The order keeps windows from overlapping while the move is under way: the windows that do
    /// not grow come first (they shrink, or only move), then the windows that grow, each group in
    /// cell order. A window grows when its target is wider or higher than its current frame.
    /// When the divider travels, the window it leaves room for only grows into space that the
    /// shrinking window has given up by then.
    ///
    /// - Parameters:
    ///   - previous: the frame of every cell before the move, in cell order.
    ///   - targets: the frame of every cell after the move.
    ///   - current: the frame every window has now.
    /// - Precondition: each list has one frame per window of the group.
    public func steps(from previous: [CGRect], to targets: [CGRect], current: [CGRect]) -> [Step] {
        precondition(
            previous.count == windows.count && targets.count == windows.count
                && current.count == windows.count,
            "there must be one frame per window")

        let tolerance = Self.sameEdgeTolerance
        var shrinking: [Step] = []
        var growing: [Step] = []
        for cell in windows.indices {
            let target = targets[cell]
            guard !Self.isSameFrame(target, previous[cell], tolerance: tolerance),
                !Self.isSameFrame(target, current[cell], tolerance: tolerance)
            else { continue }
            let step = Step(cell: cell, window: windows[cell], target: target)
            if target.width > current[cell].width + tolerance
                || target.height > current[cell].height + tolerance
            {
                growing.append(step)
            } else {
                shrinking.append(step)
            }
        }
        return shrinking + growing
    }

    private static func isSameFrame(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }
}
