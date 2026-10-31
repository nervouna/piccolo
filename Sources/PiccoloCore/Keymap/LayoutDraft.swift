import CoreGraphics
import Foundation

/// The rules of the sheet that creates and edits a custom area or a grid: how a fraction snaps, what a drag on the
/// picture of the screen makes of the area, and what the cell picker of a grid sets. Pure, so that the sheet only
/// has to show the answers.
///
/// Points are fractions of the picture of the screen (0 to 1 in both directions, origin at the top-left, like
/// ``FractionalRect``). A point outside the picture counts as the nearest point on its edge.
public enum LayoutDraft {
    // MARK: A new layout

    /// The custom area a new row starts with: 25%, 25%, 50% by 50%.
    public static let newArea = FractionalRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    /// The grid a new row starts with: 4 windows in 2 rows by 2 columns.
    public static let newGrid = GridSpec(count: 4, rows: 2, columns: 2)

    // MARK: Snapping

    /// The smallest width and height of an area drawn with the mouse.
    public static let minimumSide = 0.05

    /// A value within this of a third or two thirds snaps to it.
    private static let thirdReach = 0.02

    /// Slack for rounding noise when a side is compared with ``minimumSide`` or tidied.
    private static let noise = 1e-9

    /// `value` (limited to 0...1) snapped: to the nearest third when it is within 0.02 of 1/3 or 2/3, otherwise to
    /// the nearest 0.05. With `free` (⌥ held) to the nearest 0.01, thirds or not.
    ///
    /// The thirds are the `Double` values the presets use (`1.0 / 3.0` and `2.0 / 3.0`), and the other steps are
    /// the nearest `Double` to the decimal, so that a snapped value is equal to the same number typed.
    public static func snap(_ value: Double, free: Bool = false) -> Double {
        let value = min(max(value, 0), 1)
        if free {
            return (value * 100).rounded() / 100
        }
        for third in [1.0 / 3.0, 2.0 / 3.0] where abs(value - third) <= thirdReach {
            return third
        }
        return (value * 20).rounded() / 20
    }

    // MARK: Dragging on the picture

    /// The area after a drag on the picture of the screen, or `nil` when the drag changes nothing.
    ///
    /// - A drag that starts outside `area` draws a new one from the snapped start point to the snapped current
    ///   point, in whichever direction. It is ignored (`nil`) while its width or height is under
    ///   ``minimumSide``, so that a click draws nothing.
    /// - A drag that starts inside `area` (its edge counts, an area with no size has no inside) moves it by the
    ///   distance dragged, keeping its size: the new left and top are snapped, then limited so that the area stays
    ///   inside the screen.
    ///
    /// - Parameters:
    ///   - start: Where the drag began.
    ///   - current: Where the pointer is now.
    ///   - area: The area when the drag began (not the one the drag has made since).
    ///   - free: Snap to 0.01 and not to thirds and 0.05 (⌥ held).
    public static func areaAfterDrag(
        from start: CGPoint, to current: CGPoint, startingWith area: FractionalRect, free: Bool = false
    ) -> FractionalRect? {
        let start = clamped(start)
        let current = clamped(current)
        if contains(area, start) {
            return moved(area, byDragging: CGVector(dx: current.x - start.x, dy: current.y - start.y), free: free)
        }
        let first = CGPoint(x: snap(start.x, free: free), y: snap(start.y, free: free))
        let second = CGPoint(x: snap(current.x, free: free), y: snap(current.y, free: free))
        let width = tidy(abs(second.x - first.x))
        let height = tidy(abs(second.y - first.y))
        guard width >= minimumSide - noise, height >= minimumSide - noise else { return nil }
        return FractionalRect(x: min(first.x, second.x), y: min(first.y, second.y), width: width, height: height)
    }

    private static func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }

    private static func contains(_ area: FractionalRect, _ point: CGPoint) -> Bool {
        area.width > 0 && area.height > 0
            && point.x >= area.x && point.x <= area.x + area.width
            && point.y >= area.y && point.y <= area.y + area.height
    }

    private static func moved(_ area: FractionalRect, byDragging distance: CGVector, free: Bool) -> FractionalRect {
        FractionalRect(
            x: inside(snap(area.x + distance.dx, free: free), size: area.width),
            y: inside(snap(area.y + distance.dy, free: free), size: area.height),
            width: area.width, height: area.height)
    }

    /// `origin` limited so that a side of `size` starting there ends inside 0...1.
    private static func inside(_ origin: Double, size: Double) -> Double {
        min(max(origin, 0), max(0, 1 - size))
    }

    /// A difference of two snapped values with the noise of the subtraction taken off when it is a whole number of
    /// hundredths (0.35 - 0.30 is 0.04999999999999999), so that the side is the number a person would type. A
    /// difference that involves a third is left as it is.
    private static func tidy(_ difference: Double) -> Double {
        let hundredths = (difference * 100).rounded() / 100
        return abs(difference - hundredths) < noise ? hundredths : difference
    }

    // MARK: The grid picker

    /// The grid that picking a cell of the picker makes: `row` and `column` count from 0, so rows and columns are
    /// one more, and the windows fill every cell.
    public static func grid(pickingRow row: Int, column: Int) -> GridSpec {
        GridSpec(count: (row + 1) * (column + 1), rows: row + 1, columns: column + 1)
    }

    /// The numbers of windows a grid of `rows` by `columns` can have: 1 up to the number of cells. A grid with no
    /// cells has just 1.
    public static func windowRange(rows: Int, columns: Int) -> ClosedRange<Int> {
        guard rows >= 1, columns >= 1 else { return 1...1 }
        let (cells, overflow) = rows.multipliedReportingOverflow(by: columns)
        return 1...(overflow ? Int.max : cells)
    }

    /// `grid` with its windows changed by `delta`, kept within ``windowRange(rows:columns:)``.
    public static func grid(_ grid: GridSpec, windowsBy delta: Int) -> GridSpec {
        let range = windowRange(rows: grid.rows, columns: grid.columns)
        let (sum, overflow) = grid.count.addingReportingOverflow(delta)
        let count = overflow ? (delta < 0 ? range.lowerBound : range.upperBound) : sum
        var stepped = grid
        stepped.count = min(max(count, range.lowerBound), range.upperBound)
        return stepped
    }
}
