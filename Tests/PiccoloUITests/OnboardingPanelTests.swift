import AppKit
import SwiftUI
import Testing

@testable import PiccoloUI

@MainActor
@Suite("Onboarding panel")
struct OnboardingPanelTests {
    @Test("the panel never takes the focus and follows the panel rules")
    func rules() {
        let window = OnboardingWindow(contentViewController: NSViewController())
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
        #expect(!window.hidesOnDeactivate)
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(window.styleMask.contains(.closable))
        #expect(window.isFloatingPanel)
        #expect(window.level == .floating)
        #expect(window.collectionBehavior == OnboardingPanel.collectionBehavior)
        #expect(window.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary]))
        #expect(!window.isVisible)
    }

    @Test("the view is about 420 pt wide at every step")
    func width() {
        let store = FakeOnboardingStore()
        let model = OnboardingModel(store: store) { _, _ in }
        model.open(accessibilityGranted: true, config: OnboardingFlowTests.config([OnboardingFlowTests.leftHalf]))
        let host = OnboardingHost(openAccessibilitySettings: {}, openSettings: {})
        for _ in OnboardingStep.allCases {
            let view = NSHostingView(rootView: OnboardingView(model: model, host: host))
            #expect(view.fittingSize.width == 420)
            #expect(view.fittingSize.height > 80)
            model.skipStep()
        }
    }

    @Test("closing the window is Skip Guide")
    func closeIsSkipGuide() {
        let store = FakeOnboardingStore()
        let model = OnboardingModel(store: store) { _, _ in }
        let panel = OnboardingPanel(model: model, host: OnboardingHost(openAccessibilitySettings: {}, openSettings: {}))
        model.open(accessibilityGranted: true, config: OnboardingFlowTests.config([]))
        #expect(!panel.windowShouldClose(NSWindow()))
        #expect(!model.isOpen)
        #expect(store.isSeen)
    }
}
