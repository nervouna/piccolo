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

    /// The display that `direction` leads to from `index`.
    ///
    /// `next` and `previous` step through the displays ordered by `frame.minX`, then `frame.minY`,
    /// then index, and wrap around at both ends. With one display, the result is `index` itself.
    ///
    /// `left`, `right`, `up` and `down` pick a display that lies entirely that way: for `left`, one
    /// whose `maxX` is at most the source's `minX` plus 1 (and the same rule turned around for the
    /// others, with y pointing down). Among those, the ones whose extent along the other axis
    /// overlaps the source's are preferred, the largest overlap first; with none overlapping, the
    /// nearest by the distance between the frames' centres. Ties go to the smaller gap between the
    /// frames, then to the lower index. Nothing wraps around: when no display lies that way, the
    /// result is `index` itself, which callers read as nothing to do.
    ///
    /// - Precondition: `index` is an index into `displays`.
    public static func neighbor(of index: Int, _ direction: DisplayDirection, in displays: [Display]) -> Int {
        precondition(displays.indices.contains(index), "display index \(index) is out of range")
        switch direction {
        case .next, .previous:
            return stepped(from: index, direction == .next ? 1 : -1, in: displays)
        case .left, .right, .up, .down:
            return geometric(from: index, direction, in: displays) ?? index
        }
    }

    /// The display one step further in the layout order, wrapping around.
    private static func stepped(from index: Int, _ step: Int, in displays: [Display]) -> Int {
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
        return order[((position + step) % order.count + order.count) % order.count]
    }

    /// The display that lies entirely in `direction` from `index`, or `nil` when there is none.
    private static func geometric(from index: Int, _ direction: DisplayDirection, in displays: [Display]) -> Int? {
        let source = displays[index].frame

        /// A display in the direction, with its gap to the source and its overlap along the other axis.
        struct Candidate {
            let index: Int
            let gap: CGFloat
            let overlap: CGFloat
            let centreDistance: CGFloat
        }

        var candidates: [Candidate] = []
        for (other, display) in displays.enumerated() where other != index {
            let frame = display.frame
            let gap: CGFloat
            let overlap: CGFloat
            switch direction {
            case .left:
                guard frame.maxX <= source.minX + 1 else { continue }
                gap = source.minX - frame.maxX
                overlap = min(frame.maxY, source.maxY) - max(frame.minY, source.minY)
            case .right:
                guard frame.minX >= source.maxX - 1 else { continue }
                gap = frame.minX - source.maxX
                overlap = min(frame.maxY, source.maxY) - max(frame.minY, source.minY)
            case .up:
                guard frame.maxY <= source.minY + 1 else { continue }
                gap = source.minY - frame.maxY
                overlap = min(frame.maxX, source.maxX) - max(frame.minX, source.minX)
            case .down:
                guard frame.minY >= source.maxY - 1 else { continue }
                gap = frame.minY - source.maxY
                overlap = min(frame.maxX, source.maxX) - max(frame.minX, source.minX)
            case .next, .previous:
                return nil
            }
            let dx = frame.midX - source.midX
            let dy = frame.midY - source.midY
            candidates.append(
                Candidate(index: other, gap: gap, overlap: overlap, centreDistance: dx * dx + dy * dy))
        }

        let overlapping = candidates.filter { $0.overlap > 0 }
        if !overlapping.isEmpty {
            return overlapping.min { lhs, rhs in
                if lhs.overlap != rhs.overlap { return lhs.overlap > rhs.overlap }
                if lhs.gap != rhs.gap { return lhs.gap < rhs.gap }
                return lhs.index < rhs.index
            }?.index
        }
        return candidates.min { lhs, rhs in
            if lhs.centreDistance != rhs.centreDistance { return lhs.centreDistance < rhs.centreDistance }
            if lhs.gap != rhs.gap { return lhs.gap < rhs.gap }
            return lhs.index < rhs.index
        }?.index
    }

    /// The frame a window takes after moving from one display to another.
    ///
    /// The window keeps its place relative to `source.visibleFrame` and its size as a fraction of it.
    /// Those fractions are applied to `target.visibleFrame`. The size is capped to the target's
    /// visible size, the origin is shifted so the frame lies inside the target's visible frame, and
    /// the edges are rounded with `EdgeRounding.round`, as in `FrameResolver`.
    ///
    /// With a `gap` (``WindowGap``) both visible frames are taken in by `gap` on every side before
    /// the fractions are measured and applied, so that a gapped half on one display is a gapped half
    /// on the other.
    ///
    /// - Precondition: `source.visibleFrame` has a positive width and height.
    public static func frame(
        moving window: CGRect, from source: Display, to target: Display, gap: Int = 0
    ) -> CGRect {
        precondition(
            source.visibleFrame.width > 0 && source.visibleFrame.height > 0,
            "the source visible frame must have a positive size")
        let from = WindowGap.inset(source.visibleFrame, by: gap)
        let to = WindowGap.inset(target.visibleFrame, by: gap)

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
