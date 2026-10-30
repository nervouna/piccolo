import AppKit
import PiccoloCore
import PiccoloSystem
import PiccoloUI

/// Shows the failure notice (see `FailureNotice`) when a shortcut cannot act, and remembers the last
/// one for the debug channel.
///
/// Only the hotkey path shows a notice (`ConfigController.run`). `action.run` on the control channel
/// and the destination preview's planning never do.
@MainActor
final class NoticeController {
    static let shared = NoticeController()

    /// A notice that was shown.
    struct Shown {
        var notice: FailureNotice
        var text: String
        /// The panel's frame in canonical coordinates.
        var frame: CGRect
    }

    private let panel = NoticePanel()
    private(set) var last: Shown?

    var isVisible: Bool { panel.isVisible }

    /// Shows `notice` in the middle of the display that holds `windowFrame` (canonical coordinates),
    /// or of the display with the mouse when there is no such window.
    func show(_ notice: FailureNotice, windowFrame: CGRect?) {
        let screens = Screens.current()
        guard !screens.isEmpty else { return }
        let displays = Screens.displays(from: screens)
        let index: Int
        if let windowFrame, let found = DisplayLayout.index(containing: windowFrame, in: displays) {
            index = found
        } else {
            index = Self.indexOfDisplayWithMouse(in: screens)
        }
        let text = FailureNoticeText.text(for: notice)
        panel.show(
            text: text, symbolName: FailureNoticeText.symbolName(for: notice),
            centeredIn: screens[index].visibleFrame)
        if let frame = panel.canonicalFrame {
            last = Shown(notice: notice, text: text, frame: frame)
        }
    }

    private static func indexOfDisplayWithMouse(in screens: [ScreenInfo]) -> Int {
        guard let primary = screens.first else { return 0 }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
        return screens.firstIndex { $0.frame.contains(point) } ?? 0
    }
}
