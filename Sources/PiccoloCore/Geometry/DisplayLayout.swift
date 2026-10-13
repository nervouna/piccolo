import CoreGraphics

/// Operations on a list of displays, in the canonical space.
public enum DisplayLayout {
    /// The index of the display a window is on.
    ///
    /// The display whose `frame` overlaps the window most wins; an exact tie goes to the lower index.
    /// A window that overlaps no display (an edge touch counts as no overlap) goes to the display
    /// whose frame centre is nearest to the window's centre; ties go to the lower index.
    ///
    /// - Returns: `nil` only when `displays` is empty.
    public static func index(containing window: CGRect, in displays: [Display]) -> Int? {
        guard !displays.isEmpty else { return nil }

        var best: (index: Int, area: CGFloat)?
        for (index, display) in displays.enumerated() {
            let area = overlapArea(window, display.frame)
            if area > 0, area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        if let best {
            return best.index
        }

        let windowCenter = CGPoint(x: window.midX, y: window.midY)
        var nearest = 0
        var nearestDistance = CGFloat.infinity
        for (index, display) in displays.enumerated() {
            let dx = display.frame.midX - windowCenter.x
            let dy = display.frame.midY - windowCenter.y
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearest = index
                nearestDistance = distance
            }
        }
        return nearest
    }

    /// The display that `direction` leads to from `index`, wrapping around at both ends.
    ///
    /// Displays are ordered by `frame.minX`, then `frame.minY`, then index. With one display,
    /// the result is `index` itself.
    ///
    /// - Precondition: `index` is an index into `displays`.
    public static func neighbor(of index: Int, _ direction: DisplayDirection, in displays: [Display]) -> Int {
        precondition(displays.indices.contains(index), "display index \(index) is out of range")
        let order = displays.indices.sorted { lhs, rhs in
            let left = displays[lhs].frame
            let right = displays[rhs].frame
            if left.minX != right.minX { return left.minX < right.minX }
            if left.minY != right.minY { return left.minY < right.minY }
            return lhs < rhs
        }
        guard let position = order.firstIndex(of: index) else {
            preconditionFailure("display index \(index) is missing from its own ordering")
        }
        let step = direction == .next ? 1 : order.count - 1
        return order[(position + step) % order.count]
    }

    /// The frame a window takes after moving from one display to another.
    ///
    /// The window keeps its place relative to `source.visibleFrame` and its size as a fraction of it.
    /// Those fractions are applied to `target.visibleFrame`. The size is capped to the target's
    /// visible size, the origin is shifted so the frame lies inside the target's visible frame, and
    /// the edges are rounded with the rule in `FrameResolver`.
    ///
    /// - Precondition: `source.visibleFrame` has a positive width and height.
    public static func frame(moving window: CGRect, from source: Display, to target: Display) -> CGRect {
        let from = source.visibleFrame
        precondition(from.width > 0 && from.height > 0, "the source visible frame must have a positive size")
        let to = target.visibleFrame

        let fx = (window.minX - from.minX) / from.width
        let fy = (window.minY - from.minY) / from.height
        let width = min(window.width / from.width * to.width, to.width)
        let height = min(window.height / from.height * to.height, to.height)

        let x = clamp(to.minX + fx * to.width, from: to.minX, to: to.maxX - width)
        let y = clamp(to.minY + fy * to.height, from: to.minY, to: to.maxY - height)
        return FrameResolver.roundEdges(minX: x, maxX: x + width, minY: y, maxY: y + height)
    }

    /// The area of the overlap of two rects. Zero when they do not overlap or only touch.
    private static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let overlap = lhs.intersection(rhs)
        guard !overlap.isNull else { return 0 }
        return overlap.width * overlap.height
    }

    private static func clamp(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
