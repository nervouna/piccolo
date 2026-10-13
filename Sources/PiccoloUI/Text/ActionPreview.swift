import CoreGraphics
import PiccoloCore

/// What the editor's preview draws: the windows an action would produce, as rectangles in the
/// unit square (0 to 1 in both directions, origin at the top-left like the screen coordinates).
public enum ActionPreview {
    /// The rectangles for `action`, or `nil` when the action has no picture (a display move or a
    /// divider move places nothing on its own).
    ///
    /// - A preset is its frame. `center` keeps the window's own size, which is not known here, so
    ///   it is drawn as a centered half-size window.
    /// - A custom frame is the frame.
    /// - A grid is its cells, row by row.
    public static func rects(for action: Action) -> [CGRect]? {
        switch action {
        case .placeWindow(.preset(let preset)):
            guard let rect = preset.fractionalRect else {
                return [CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)]
            }
            return [CGRect(rect)]
        case .placeWindow(.custom(let rect)):
            return [CGRect(rect)]
        case .arrangeGrid(let grid):
            guard grid.count >= 1, grid.rows >= 1, grid.columns >= 1 else { return nil }
            return cells(of: TileLayout.grid(windowCount: grid.count, rows: grid.rows, columns: grid.columns))
        case .moveToDisplay, .moveDivider:
            return nil
        }
    }

    /// The cells of a layout as fractions, without rounding to whole points.
    private static func cells(of layout: TileLayout) -> [CGRect] {
        var rects: [CGRect] = []
        var top = 0.0
        for row in layout.rows {
            var left = 0.0
            for width in row.widths {
                rects.append(CGRect(x: left, y: top, width: width, height: row.height))
                left += width
            }
            top += row.height
        }
        return rects
    }
}

extension CGRect {
    fileprivate init(_ rect: FractionalRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
