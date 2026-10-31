import CoreGraphics
import Testing

@testable import PiccoloUI

/// The sizes of the Settings window's tabs and how a frame of one is fitted onto a screen. AppKit
/// space: the origin at the bottom left, y up.
@Suite("Settings window sizing")
struct SettingsWindowSizingTests {
    /// A screen's visible frame: 1440 × 800 with its bottom left at (0, 100).
    private let visible = CGRect(x: 0, y: 100, width: 1440, height: 800)

    @Test("the Shortcuts tab opens at 640 × 720 and can shrink to 560 × 480, the General tab is 640 wide")
    func sizes() {
        #expect(SettingsWindowSizing.shortcutsDefaultContentSize == CGSize(width: 640, height: 720))
        #expect(SettingsWindowSizing.shortcutsMinimumContentSize == CGSize(width: 560, height: 480))
        #expect(SettingsWindowSizing.generalContentWidth == 640)
    }

    @Test("a window that fits keeps its top-left corner")
    func keepsTopLeft() {
        let current = CGRect(x: 200, y: 300, width: 640, height: 500)  // top edge at 800
        let frame = SettingsWindowSizing.frame(
            replacing: current, size: CGSize(width: 700, height: 600), visibleFrame: visible)
        #expect(frame == CGRect(x: 200, y: 200, width: 700, height: 600))
        #expect(frame.maxY == current.maxY)
        #expect(frame.minX == current.minX)
    }

    @Test("a window is never taller or wider than the visible frame")
    func limitedToTheVisibleFrame() {
        let current = CGRect(x: 100, y: 150, width: 640, height: 700)
        let frame = SettingsWindowSizing.frame(
            replacing: current, size: CGSize(width: 2000, height: 1200), visibleFrame: visible)
        #expect(frame == visible)
    }

    @Test("a window that would end below the visible frame moves up, as far as needed and no further")
    func movesUp() {
        // The top edge is at 600: 700 pt high, the window would end at -100, below the visible bottom (100).
        let current = CGRect(x: 100, y: 300, width: 640, height: 300)
        let frame = SettingsWindowSizing.frame(
            replacing: current, size: CGSize(width: 640, height: 700), visibleFrame: visible)
        #expect(frame.minY == visible.minY, "the window ends at the bottom of the visible frame")
        #expect(frame.height == 700)
        #expect(frame.maxY == 800)
        #expect(frame.minX == 100)
    }

    @Test("a window that would end beyond the right edge moves left, as far as needed")
    func movesLeft() {
        let current = CGRect(x: 1000, y: 300, width: 400, height: 500)
        let frame = SettingsWindowSizing.frame(
            replacing: current, size: CGSize(width: 640, height: 500), visibleFrame: visible)
        #expect(frame.maxX == visible.maxX)
        #expect(frame.width == 640)
        #expect(frame.maxY == current.maxY)
    }

    @Test("a window above the visible frame comes down to its top")
    func comesDown() {
        let current = CGRect(x: 100, y: 800, width: 640, height: 300)  // top edge at 1100
        let frame = SettingsWindowSizing.frame(
            replacing: current, size: CGSize(width: 640, height: 300), visibleFrame: visible)
        #expect(frame.maxY == visible.maxY)
    }

    @Test("changing the size and changing it back gives the same frame, whatever tab is between")
    func roundTrip() {
        let start = CGRect(x: 120, y: 100, width: 640, height: 700)  // top edge at 800
        let general = SettingsWindowSizing.frame(
            replacing: start, size: CGSize(width: 640, height: 400), visibleFrame: visible)
        #expect(general.maxY == start.maxY)
        let back = SettingsWindowSizing.frame(
            replacing: general, size: start.size, visibleFrame: visible)
        #expect(back == start)
    }
}
