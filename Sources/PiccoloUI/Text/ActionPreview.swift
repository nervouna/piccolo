import CoreGraphics
import PiccoloCore

/// What the keymap's glyphs draw: the windows an action would produce, as rectangles
/// in the unit square (0 to 1 in both directions, origin at the top-left like the screen coordinates).
public enum ActionPreview {
    /// The rectangles for `action`, or `nil` when the action has no picture (a display move, a
    /// divider move or a swap places nothing on its own).
    ///
    /// - A preset is its frame. `center` keeps the window's own size, which is not known here, so
    ///   it is drawn as a centered half-size window.
    /// - A custom frame is the frame.
    /// - A grid is its cells in `fillOrder`, in the order the windows fill them: row by row (the
    ///   default) or column by column. With fewer windows than cells the short last row (column)
    ///   stretches over the full width (height), as the arrangement does.
    public static func rects(for action: Action, fillOrder: GridFillOrder = .rows) -> [CGRect]? {
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
            return cells(
                of: TileLayout.grid(
                    windowCount: grid.count, rows: grid.rows, columns: grid.columns, fillOrder: fillOrder))
        case .moveToDisplay, .moveDivider, .swapWindow, .restoreWindow:
            return nil
        }
    }

    /// The cells of a layout as fractions, without rounding to whole points, in the order of their numbers.
    private static func cells(of layout: TileLayout) -> [CGRect] {
        var rects: [CGRect] = []
        switch layout.orientation {
        case .rows:
            var top = 0.0
            for row in layout.rows {
                var left = 0.0
                for width in row.widths {
                    rects.append(CGRect(x: left, y: top, width: width, height: row.height))
                    left += width
                }
                top += row.height
            }
        case .columns:
            var left = 0.0
            for column in layout.columns {
                var top = 0.0
                for height in column.heights {
                    rects.append(CGRect(x: left, y: top, width: column.width, height: height))
                    top += height
                }
                left += column.width
            }
        }
        return rects
    }
}

extension CGRect {
    fileprivate init(_ rect: FractionalRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
