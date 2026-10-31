import CoreGraphics

/// The sizes of the Settings window's tabs and how a window of one of them is fitted onto a screen.
///
/// Each tab has its own size. The Shortcuts tab opens at ``shortcutsDefaultContentSize``, can be
/// resized down to ``shortcutsMinimumContentSize`` and is remembered by the window controller. The
/// General tab is ``generalContentWidth`` wide and as tall as its content asks for. The window is
/// never taller than the visible frame of its screen: a tab that does not fit then scrolls.
///
/// Everything here is in AppKit space (the origin at the bottom left, y up) and in points.
enum SettingsWindowSizing {
    /// The content size the Shortcuts tab opens at, until the person resizes the window.
    static let shortcutsDefaultContentSize = CGSize(width: 640, height: 720)
    /// The smallest content size the Shortcuts tab can be resized to.
    static let shortcutsMinimumContentSize = CGSize(width: 560, height: 480)
    /// The content width of the General tab, which cannot be resized.
    static let generalContentWidth: CGFloat = 640
    /// The largest size a resizable tab can be resized to: no limit.
    static let unlimited = CGSize(width: 100_000, height: 100_000)

    /// The frame of a window of `size` that takes the place of `current`.
    ///
    /// The window keeps its top-left corner, which is what makes a tab change look like the window
    /// growing or shrinking downwards. It is limited to the visible frame: never wider or taller than it,
    /// and moved up or left only as far as needed to end inside it.
    static func frame(replacing current: CGRect, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        // A window that would end below the visible frame moves up, one that would end beyond its right
        // edge moves left; the top and left edges stay when the new size fits below and right of them.
        let top = min(max(current.maxY, visibleFrame.minY + height), visibleFrame.maxY)
        let left = max(min(current.minX, visibleFrame.maxX - width), visibleFrame.minX)
        return CGRect(x: left, y: top - height, width: width, height: height)
    }
}
