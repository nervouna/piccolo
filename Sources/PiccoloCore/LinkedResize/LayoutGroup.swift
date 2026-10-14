import CoreGraphics

/// A group of windows that Piccolo arranged, with the layout they were arranged in.
///
/// `windows` holds one window per cell, in cell order, so `windows[i]` sits in cell `i` of
/// `layout`: row-major for a row layout, column-major for a column layout (the one a column-first
/// arrangement records). `frames` holds the frame each window was last measured at, in the same order.
/// Everything a group does works on either orientation; a column group does it through the transpose
/// of its layout (see ``TileLayout/transposed``).
public struct LayoutGroup: Equatable, Sendable {
    /// The layout the windows were last recorded in.
    public private(set) var layout: TileLayout
    /// The windows, one per cell, in cell order.
    public let windows: [WindowID]
    /// The visible frame the layout is framed in.
    public let visibleFrame: CGRect
    /// The frame of each window as last measured, in the same order as `windows`.
    public private(set) var frames: [CGRect]

    /// - Precondition: `windows` and `frames` each have one entry per cell of `layout`.
    public init(layout: TileLayout, windows: [WindowID], visibleFrame: CGRect, frames: [CGRect]) {
        precondition(windows.count == layout.windowCount, "there must be one window per cell")
        precondition(frames.count == windows.count, "there must be one frame per window")
        self.layout = layout
        self.windows = windows
        self.visibleFrame = visibleFrame
        self.frames = frames
    }

    /// The index of the cell `window` is in, or `nil` when the group does not hold it.
    public func cell(of window: WindowID) -> Int? {
        windows.firstIndex(of: window)
    }

    /// Why a group no longer holds: the first window, in cell order, that is not where the
    /// group recorded it.
    public enum Breakage: Equatable, Sendable {
        /// The window is not in the frames that were read: it was closed, minimized or left the
        /// screen.
        case missing(WindowID)
        /// The window is there, but at least one of its edges is more than the tolerance from the
        /// recorded frame.
        case moved(WindowID)
    }

    /// Whether every window of the group is in `currentFrames`, and each of its four edges is
    /// within `tolerance` points of the frame recorded for it.
    public func isIntact(currentFrames: [WindowID: CGRect], tolerance: CGFloat = 2) -> Bool {
        breakage(currentFrames: currentFrames, tolerance: tolerance) == nil
    }

    /// The first window that is not where the group recorded it, or `nil` when the group is
    /// intact (see ``isIntact(currentFrames:tolerance:)``).
    public func breakage(currentFrames: [WindowID: CGRect], tolerance: CGFloat = 2) -> Breakage? {
        for (window, recorded) in zip(windows, frames) {
            guard let current = currentFrames[window] else { return .missing(window) }
            let isInPlace = abs(current.minX - recorded.minX) <= tolerance
                && abs(current.minY - recorded.minY) <= tolerance
                && abs(current.maxX - recorded.maxX) <= tolerance
                && abs(current.maxY - recorded.maxY) <= tolerance
            if !isInPlace { return .moved(window) }
        }
        return nil
    }

    /// The frames `layout` gives its cells in this group's visible frame, in cell order.
    public func targetFrames(for layout: TileLayout) -> [CGRect] {
        layout.frames(in: visibleFrame)
    }

    /// A window that is further than this many points from its requested edge has refused its
    /// frame or been shifted back into its display. Smaller differences are read-back noise.
    private static let reachTolerance: CGFloat = 1

    /// Replaces `layout` and `frames` with what the windows achieved after `requested` was applied.
    ///
    /// `requested` is the layout that was applied, usually the result of `DividerMove.plan`, and it
    /// must have the orientation of `layout` and the same cells per row (per column, for a column
    /// layout). `achieved` is the frame each window was read back at, one per window in cell order.
    /// `frames` becomes `achieved`.
    ///
    /// Each divider is recorded where its windows actually ended up, so that a window that refused
    /// its frame moves the divider to its real edge, and the neighbour fills the rest:
    ///
    /// 1. A vertical divider has two candidates: the achieved right edge of the cell on its left,
    ///    and the achieved left edge of the cell on its right. A horizontal divider has the achieved
    ///    bottom edge of every cell in the row above and the achieved top edge of every cell in the
    ///    row below.
    /// 2. A candidate that is more than 1 point from the edge it was asked for counts as a
    ///    deviation. The deviation furthest from its requested edge decides the divider, and the
    ///    divider takes that achieved edge as a fraction of the visible frame. On a tie, the left or
    ///    upper candidate wins.
    /// 3. When no candidate deviates, the divider keeps its requested fraction exactly.
    /// 4. The fractions of a row's widths, and of the heights, must give only positive cells. When
    ///    they do not (a window ran past its neighbour's divider), the widths of that row, or the
    ///    heights of the whole layout, keep their requested fractions instead. The layout stays valid
    ///    and the next move is planned from it, while `frames` still shows what the windows did.
    ///
    /// A column layout is recorded the same way with x and y swapped: its achieved frames and its
    /// visible frame are transposed, the transposed row layout is recorded, and the result is
    /// transposed back. Nothing else changes, the tie rule included: the left or upper candidate
    /// wins.
    ///
    /// Example: two windows side by side on a 1000 point frame, with A asked for 550 points and B
    /// for 450. If B needs 500 points, it is shifted back to x = 500, and the divider is recorded at
    /// 0.5. If A stopped at 500 instead, leaving a gap, the divider is recorded at 0.5 as well.
    ///
    /// - Precondition: `requested` has the orientation of `layout` and the same cells per row
    ///   (column), and `achieved` has one frame per window.
    public mutating func recordAchieved(requested: TileLayout, achieved: [CGRect]) {
        precondition(
            requested.orientation == layout.orientation
                && requested.cellsPerLine == layout.cellsPerLine,
            "the requested layout must have the orientation and the cells per row (column) of the group's layout")
        precondition(achieved.count == windows.count, "there must be one achieved frame per window")

        switch layout.orientation {
        case .rows:
            layout = Self.recorded(requested: requested, visibleFrame: visibleFrame, achieved: achieved)
        case .columns:
            layout = Self.recorded(
                requested: requested.transposed, visibleFrame: visibleFrame.transposed,
                achieved: achieved.map(\.transposed)
            ).transposed
        }
        frames = achieved
    }

    /// The layout `recordAchieved(requested:achieved:)` records for a row layout.
    private static func recorded(
        requested: TileLayout, visibleFrame: CGRect, achieved: [CGRect]
    ) -> TileLayout {
        let asked = requested.frames(in: visibleFrame)
        let counts = requested.cellsPerLine
        // The row-major index of the first cell of each row.
        var firstCells: [Int] = []
        var next = 0
        for count in counts {
            firstCells.append(next)
            next += count
        }

        // Vertical dividers, row by row. Divider k of a row lies between its cells k and k + 1.
        var widthsByRow: [[Double]] = []
        for (row, rowLayout) in requested.rows.enumerated() {
            let requestedPositions = DividerPositions.interior(rowLayout.widths)
            var positions = requestedPositions
            for k in positions.indices {
                let left = firstCells[row] + k
                let right = left + 1
                positions[k] = recordedPosition(
                    requested: requestedPositions[k],
                    edges: [
                        (achieved: achieved[left].maxX, requested: asked[left].maxX),
                        (achieved: achieved[right].minX, requested: asked[right].minX),
                    ],
                    origin: visibleFrame.minX,
                    extent: visibleFrame.width)
            }
            if !DividerPositions.hasPositiveFractions(positions) {
                positions = requestedPositions
            }
            widthsByRow.append(DividerPositions.fractions(positions))
        }

        // Horizontal dividers. Every cell of the row above and of the row below is a candidate,
        // because a row can hold cells that reached their edge and cells that did not.
        let requestedHeightPositions = DividerPositions.interior(requested.rows.map(\.height))
        var heightPositions = requestedHeightPositions
        for divider in heightPositions.indices {
            var edges: [(achieved: CGFloat, requested: CGFloat)] = []
            for cell in firstCells[divider]..<firstCells[divider] + counts[divider] {
                edges.append((achieved: achieved[cell].maxY, requested: asked[cell].maxY))
            }
            let below = firstCells[divider + 1]
            for cell in below..<below + counts[divider + 1] {
                edges.append((achieved: achieved[cell].minY, requested: asked[cell].minY))
            }
            heightPositions[divider] = recordedPosition(
                requested: requestedHeightPositions[divider],
                edges: edges,
                origin: visibleFrame.minY,
                extent: visibleFrame.height)
        }
        if !DividerPositions.hasPositiveFractions(heightPositions) {
            heightPositions = requestedHeightPositions
        }

        let heights = DividerPositions.fractions(heightPositions)
        return TileLayout(rows: zip(heights, widthsByRow).map { height, widths in
            TileLayout.Row(height: height, widths: widths)
        })
    }

    /// The fraction a divider is recorded at, from the candidate edges on its two sides.
    ///
    /// The requested fraction when no candidate is more than `reachTolerance` from its requested
    /// edge. Otherwise the achieved edge of the candidate furthest from its requested edge, as a
    /// fraction of the axis that starts at `origin` and is `extent` long.
    private static func recordedPosition(
        requested: Double,
        edges: [(achieved: CGFloat, requested: CGFloat)],
        origin: CGFloat,
        extent: CGFloat
    ) -> Double {
        var furthest: (achieved: CGFloat, requested: CGFloat)?
        for edge in edges where abs(edge.achieved - edge.requested) > reachTolerance {
            if let current = furthest,
               abs(current.achieved - current.requested) >= abs(edge.achieved - edge.requested) {
                continue
            }
            furthest = edge
        }
        guard let furthest else { return requested }
        return Double((furthest.achieved - origin) / extent)
    }
}
