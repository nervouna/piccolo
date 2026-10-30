import AppKit
import Testing

@testable import PiccoloUI

@MainActor
@Suite("Notice panel")
struct NoticePanelTests {
    @Test("the panel never takes the focus and follows the panel rules of the highlight")
    func rules() {
        let window = NoticeWindow()
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
        #expect(window.ignoresMouseEvents)
        #expect(!window.hidesOnDeactivate)
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(window.level == .statusBar)
        #expect(window.collectionBehavior == NoticePanel.collectionBehavior)
        #expect(window.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]))
        #expect(!window.isVisible)
    }

    @Test("the view fits its text")
    func fitsText() {
        let view = NoticeView()
        view.set(text: "No window to act on", symbolName: "macwindow")
        let short = view.fittingSize
        view.set(text: "The grid does not fit this display, not at all", symbolName: "macwindow")
        #expect(view.fittingSize.width > short.width)
        #expect(short.height > 20)
    }
}
