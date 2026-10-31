import Foundation

import PiccoloCore

extension ActionSettings {
    /// Settings with the values the executor tests were written for: no window gap, rows-first grids and
    /// the Fast animation (an executor without an animator ignores the animation). They are not the
    /// defaults of a new install, so a test says them instead of reading `ActionSettings.default`.
    static func pinned(
        resizeStep: Double = Config.defaultResizeStep, animation: WindowAnimation = .fast,
        gridFillOrder: GridFillOrder = .rows, gap: Int = 0
    ) -> ActionSettings {
        ActionSettings(resizeStep: resizeStep, animation: animation, gridFillOrder: gridFillOrder, gap: gap)
    }
}
