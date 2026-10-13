import CoreGraphics
import Testing

@testable import PiccoloCore

/// Fixtures and tiling checks shared by the `TileLayout` test files.
enum TileLayoutSupport {
    /// A grid to build, with the cells per row that the issue gives for it.
    struct GridExample: Sendable, CustomTestStringConvertible {
        let windowCount: Int
        let rows: Int
        let columns: Int
        let cellsPerRow: [Int]

        var layout: TileLayout {
            TileLayout.grid(windowCount: windowCount, rows: rows, columns: columns)
        }

        var testDescription: String {
            "\(windowCount) in \(rows)x\(columns)"
        }
    }

    static let gridExamples: [GridExample] = [
        GridExample(windowCount: 4, rows: 2, columns: 2, cellsPerRow: [2, 2]),
        GridExample(windowCount: 3, rows: 2, columns: 2, cellsPerRow: [2, 1]),
        GridExample(windowCount: 2, rows: 2, columns: 2, cellsPerRow: [2]),
        GridExample(windowCount: 1, rows: 2, columns: 2, cellsPerRow: [1]),
        GridExample(windowCount: 5, rows: 2, columns: 3, cellsPerRow: [3, 2]),
        GridExample(windowCount: 3, rows: 1, columns: 3, cellsPerRow: [3]),
        GridExample(windowCount: 3, rows: 3, columns: 1, cellsPerRow: [1, 1, 1]),
        GridExample(windowCount: 6, rows: 2, columns: 2, cellsPerRow: [2, 2]),
        // Unused rows: the used rows share the full height.
        GridExample(windowCount: 4, rows: 3, columns: 3, cellsPerRow: [3, 1]),
        GridExample(windowCount: 7, rows: 3, columns: 3, cellsPerRow: [3, 3, 1]),
    ]

    /// The primary display's visible frame, below the menu bar.
    static let primaryVisible = CGRect(x: 0, y: 25, width: 1440, height: 875)

    /// A negative-origin, odd-sized visible frame. Several boundaries land on `.5`,
    /// which exercises the ties-away-from-zero rule.
    static let oddVisible = CGRect(x: -1728, y: 355, width: 1727, height: 1085)

    static let visibleFrames = [primaryVisible, oddVisible]

    /// A layout with unequal fractions, built by hand.
    static let handBuilt = TileLayout(rows: [
        TileLayout.Row(height: 0.3, widths: [0.25, 0.75]),
        TileLayout.Row(height: 0.7, widths: [1]),
    ])

    /// A layout to tile one visible frame.
    struct Scene: Sendable, CustomTestStringConvertible {
        let name: String
        let layout: TileLayout
        let visible: CGRect

        var testDescription: String {
            "\(name) on \(visible)"
        }
    }

    /// Every grid example and the hand-built layout, on both visible frames.
    static let scenes: [Scene] = visibleFrames.flatMap { visible in
        var scenes = gridExamples.map { example in
            Scene(name: example.testDescription, layout: example.layout, visible: visible)
        }
        scenes.append(Scene(name: "hand-built layout", layout: handBuilt, visible: visible))
        return scenes
    }

    // MARK: Tiling checks

    /// Every check that `frames` tile `visible` exactly, with `cellsPerRow` cells in each row.
    /// Returns one message per violation. An empty result means the tiling is exact.
    static func tilingViolations(
        _ frames: [CGRect], cellsPerRow: [Int], visible: CGRect
    ) -> [String] {
        wholeNumberViolations(frames)
            + rowMajorViolations(frames, cellsPerRow: cellsPerRow)
            + overlapViolations(frames)
            + coverageViolations(frames, visible: visible)
            + areaViolations(frames, visible: visible)
            + sharedEdgeViolations(frames, visible: visible)
    }

    /// Every edge is a whole number of points.
    static func wholeNumberViolations(_ frames: [CGRect]) -> [String] {
        frames.indices.compactMap { index in
            let rect = frames[index]
            let edges = [rect.minX, rect.minY, rect.maxX, rect.maxY]
            return edges.allSatisfy { $0 == $0.rounded() }
                ? nil
                : "cell \(index) has fractional edges: \(rect)"
        }
    }

    /// Frames are grouped into rows of `cellsPerRow[row]` cells, in order. Each row is level,
    /// its cells share edges from left to right, and each row starts where the previous one
    /// ends. Together with the non-empty check, this is row-major order.
    static func rowMajorViolations(_ frames: [CGRect], cellsPerRow: [Int]) -> [String] {
        let expectedCount = cellsPerRow.reduce(0, +)
        guard frames.count == expectedCount else {
            return ["expected \(expectedCount) cells, got \(frames.count)"]
        }
        var problems: [String] = []
        var start = 0
        var previousBottom: CGFloat?
        for (row, count) in cellsPerRow.enumerated() {
            let cells = Array(frames[start..<start + count])
            start += count
            guard let first = cells.first else {
                problems.append("row \(row) has no cells")
                continue
            }
            if let previousBottom, first.minY != previousBottom {
                problems.append("row \(row) starts at y \(first.minY), not at \(previousBottom)")
            }
            for cell in cells where cell.minY != first.minY || cell.maxY != first.maxY {
                problems.append("row \(row) is not level: \(cell)")
            }
            for (left, right) in zip(cells, cells.dropFirst()) where left.maxX != right.minX {
                problems.append("cells in row \(row) do not share an edge: \(left), \(right)")
            }
            for cell in cells where cell.width <= 0 || cell.height <= 0 {
                problems.append("empty cell: \(cell)")
            }
            previousBottom = first.maxY
        }
        return problems
    }

    /// No two cells overlap by any positive area.
    static func overlapViolations(_ frames: [CGRect]) -> [String] {
        var problems: [String] = []
        for i in frames.indices {
            for j in frames.indices where j > i && overlapArea(frames[i], frames[j]) > 0 {
                problems.append("cells \(i) and \(j) overlap: \(frames[i]), \(frames[j])")
            }
        }
        return problems
    }

    static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let width = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let height = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }

    /// The union of the cells is `visible`, with no gaps and no overlaps.
    ///
    /// The plane is cut at every cell edge and every edge of `visible`. Each resulting
    /// elementary rectangle must be covered once if it lies inside `visible`, and not at all
    /// otherwise. Every frame edge is a cut, so this is exact for any rectangles.
    static func coverageViolations(_ frames: [CGRect], visible: CGRect) -> [String] {
        let xs = Array(Set(frames.flatMap { [$0.minX, $0.maxX] } + [visible.minX, visible.maxX])).sorted()
        let ys = Array(Set(frames.flatMap { [$0.minY, $0.maxY] } + [visible.minY, visible.maxY])).sorted()
        var problems: [String] = []
        for (x0, x1) in zip(xs, xs.dropFirst()) {
            for (y0, y1) in zip(ys, ys.dropFirst()) {
                let midX = (x0 + x1) / 2
                let midY = (y0 + y1) / 2
                let covering = frames.filter {
                    $0.minX < midX && midX < $0.maxX && $0.minY < midY && midY < $0.maxY
                }.count
                let insideVisible = visible.minX < midX && midX < visible.maxX
                    && visible.minY < midY && midY < visible.maxY
                let expected = insideVisible ? 1 : 0
                if covering != expected {
                    problems.append(
                        "region x \(x0)...\(x1), y \(y0)...\(y1) is covered \(covering) times, expected \(expected)")
                }
            }
        }
        return problems
    }

    /// The cells' total area equals the visible frame's area.
    static func areaViolations(_ frames: [CGRect], visible: CGRect) -> [String] {
        let total = frames.reduce(0) { $0 + $1.width * $1.height }
        let expected = visible.width * visible.height
        return total == expected
            ? []
            : ["cells cover area \(total), visible frame has area \(expected)"]
    }

    /// Every edge that is not on the boundary of `visible` is shared exactly with a neighbour:
    /// another cell has its opposite edge at the same coordinate, overlapping along it.
    static func sharedEdgeViolations(_ frames: [CGRect], visible: CGRect) -> [String] {
        func overlapsVertically(_ a: CGRect, _ b: CGRect) -> Bool {
            a.minY < b.maxY && b.minY < a.maxY
        }
        func overlapsHorizontally(_ a: CGRect, _ b: CGRect) -> Bool {
            a.minX < b.maxX && b.minX < a.maxX
        }
        var problems: [String] = []
        for (index, cell) in frames.enumerated() {
            let others = frames.indices.filter { $0 != index }.map { frames[$0] }
            let sides: [(name: String, interior: Bool, shared: Bool)] = [
                ("right", cell.maxX < visible.maxX,
                 others.contains { $0.minX == cell.maxX && overlapsVertically(cell, $0) }),
                ("left", cell.minX > visible.minX,
                 others.contains { $0.maxX == cell.minX && overlapsVertically(cell, $0) }),
                ("bottom", cell.maxY < visible.maxY,
                 others.contains { $0.minY == cell.maxY && overlapsHorizontally(cell, $0) }),
                ("top", cell.minY > visible.minY,
                 others.contains { $0.maxY == cell.minY && overlapsHorizontally(cell, $0) }),
            ]
            for side in sides where side.interior && !side.shared {
                problems.append("\(side.name) edge of cell \(index) is not shared: \(cell)")
            }
        }
        return problems
    }
}
