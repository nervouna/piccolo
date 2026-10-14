import CoreGraphics

/// Plans which windows a grid arrangement moves, and the frame each one gets.
///
/// The planner is pure: the caller passes the windows on screen, the focus history and the
/// displays, and gets back a plan. Nothing is moved here.
public enum ArrangePlanner {
    /// The smallest width and height, in points, that a cell may have.
    public static let minimumCellSide: CGFloat = 100

    /// Plans the arrangement of the most recently focused windows on one display.
    ///
    /// 1. Eligible windows are the candidates that are standard, not minimized, not full screen,
    ///    and whose frame belongs to `displayIndex` (see `DisplayLayout.index(containing:in:)`).
    ///    Their order is kept.
    /// 2. The chosen windows are the `grid.count` most recently focused eligible windows, with
    ///    `FocusHistory.mostRecent(_:among:)` deciding the order. A window listed twice counts once.
    /// 3. With no chosen window, the result is `nil`.
    /// 4. The layout is `TileLayout.grid` for the number of chosen windows in `fillOrder`, framed in
    ///    the visible frame of the display.
    /// 5. The chosen windows take the cells in cell order: the most recently focused window takes
    ///    the top-left cell. With rows first the cells are numbered row by row (the layout is a row
    ///    layout); with columns first they are numbered column by column (a column layout), so that
    ///    the second window goes below the first when the grid has more than one row.
    ///
    /// The display index and the grid are checked first, even when there is nothing to arrange.
    ///
    /// - Throws: `ArrangePlannerError.displayIndexOutOfRange` when `displayIndex` is not an index
    ///   into `displays`; `.invalidGrid` when `grid` breaks a rule of `GridSpec`; `.cellTooSmall`
    ///   when a cell's width or height is below `minimumCellSide`.
    public static func plan(
        grid: GridSpec,
        fillOrder: GridFillOrder = .rows,
        displayIndex: Int,
        candidates: [WindowCandidate],
        history: FocusHistory,
        displays: [Display]
    ) throws(ArrangePlannerError) -> ArrangePlan? {
        guard displays.indices.contains(displayIndex) else {
            throw .displayIndexOutOfRange
        }
        do {
            try grid.validate()
        } catch {
            throw .invalidGrid(error)
        }

        let eligible = candidates.filter { candidate in
            candidate.isStandard
                && !candidate.isMinimized
                && !candidate.isFullScreen
                && DisplayLayout.index(containing: candidate.frame, in: displays) == displayIndex
        }
        let chosen = history.mostRecent(grid.count, among: eligible.map(\.id))
        guard !chosen.isEmpty else {
            return nil
        }

        let layout = TileLayout.grid(
            windowCount: chosen.count, rows: grid.rows, columns: grid.columns, fillOrder: fillOrder)
        let frames = layout.frames(in: displays[displayIndex].visibleFrame)
        // Written as `>=`, so that a NaN width or height fails the check as well.
        guard frames.allSatisfy({ $0.width >= minimumCellSide && $0.height >= minimumCellSide }) else {
            throw .cellTooSmall
        }

        let assignments = zip(chosen, frames).map { window, frame in
            ArrangePlan.Assignment(window: window, frame: frame)
        }
        return ArrangePlan(displayIndex: displayIndex, layout: layout, assignments: assignments)
    }
}
