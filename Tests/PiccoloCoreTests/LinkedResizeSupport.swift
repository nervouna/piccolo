import CoreGraphics
import Testing

@testable import PiccoloCore

/// Fixtures shared by the linked resize test files.
enum LinkedResizeSupport {
    /// The step the examples move a divider by.
    static let step = 0.05

    /// A visible frame of 1000 by 500 points at the origin, so that fractions are easy to read.
    static let visible = CGRect(x: 0, y: 0, width: 1000, height: 500)

    /// Window IDs 1 through `count`, in row-major order.
    static func windows(_ count: Int) -> [WindowID] {
        (1...count).map { WindowID(rawValue: UInt32($0)) }
    }

    /// Whether two lists of fractions have the same length and agree within `tolerance`.
    static func isClose(_ actual: [Double], _ expected: [Double], tolerance: Double = 1e-9) -> Bool {
        actual.count == expected.count
            && zip(actual, expected).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// Whether two layouts have the same rows and cells per row, with fractions that agree
    /// within `tolerance`.
    static func isClose(
        _ actual: TileLayout, _ expected: TileLayout, tolerance: Double = 1e-9
    ) -> Bool {
        actual.rows.count == expected.rows.count
            && zip(actual.rows, expected.rows).allSatisfy { a, e in
                abs(a.height - e.height) <= tolerance
                    && isClose(a.widths, e.widths, tolerance: tolerance)
            }
    }

    /// Whether `layout` passes `TileLayout.validate()`.
    static func isValid(_ layout: TileLayout) -> Bool {
        (try? layout.validate()) != nil
    }

    /// `frame` with some of its edges moved by the given amounts, in points. Only the named
    /// edges move: `left` moves the left edge, and so on.
    static func movingEdges(
        of frame: CGRect,
        left: CGFloat = 0,
        top: CGFloat = 0,
        right: CGFloat = 0,
        bottom: CGFloat = 0
    ) -> CGRect {
        CGRect(
            x: frame.minX + left,
            y: frame.minY + top,
            width: frame.width - left + right,
            height: frame.height - top + bottom)
    }
}
