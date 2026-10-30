import AppKit
import PiccoloCore
import SwiftUI

/// The window of the onboarding guide: a floating, non-activating panel hosting ``OnboardingView``.
///
/// The panel follows the panel rules of the destination preview's highlight and the failure notice
/// (`HighlightPanels`, `NoticePanel`): it must never activate Piccolo, because the shortcuts the guide
/// asks for act on the focused window of the application the user works in, and an application that
/// has been the active application stops firing simulated hotkeys (see `CLAUDE.md`). It is therefore a
/// non-activating panel that cannot become key or main (no control needs typing), so a click on one
/// of its buttons works while the other application stays frontmost. It does not hide when Piccolo is
/// not the active application, is ordered front with `orderFrontRegardless()` and never with
/// `makeKeyAndOrderFront(_:)`. Level ``level`` (`.floating`), collection behaviour
/// ``collectionBehavior``. It has a close button, which does what Skip Guide does.
@MainActor
public final class OnboardingPanel: NSObject, NSWindowDelegate {
    /// The window level of the panel.
    public static let level = NSWindow.Level.floating

    /// The collection behaviour of the panel.
    public static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    /// The space between the panel and the edges of the display's visible frame, in points.
    static let margin: CGFloat = 16

    private let model: OnboardingModel
    private let host: OnboardingHost
    private var window: OnboardingWindow?

    public init(model: OnboardingModel, host: OnboardingHost) {
        self.model = model
        self.host = host
        super.init()
    }

    /// Whether the panel is on screen.
    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// The frame of the panel in canonical coordinates, as long as it is visible; `nil` otherwise.
    public var canonicalFrame: CGRect? {
        guard isVisible, let window, let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return ScreenSpace.canonicalRect(fromAppKit: window.frame, primaryDisplayHeight: primaryHeight)
    }

    /// Puts the panel in the top-right corner of `visibleFrame` (canonical coordinates) and orders it
    /// front without activating Piccolo. A panel that is on screen already is only ordered front, where
    /// it is.
    public func show(in visibleFrame: CGRect) {
        let window = ensureWindow()
        if !window.isVisible, let primaryHeight = NSScreen.screens.first?.frame.height {
            let area = ScreenSpace.appKitRect(fromCanonical: visibleFrame, primaryDisplayHeight: primaryHeight)
            let size = window.frame.size
            window.setFrameOrigin(
                NSPoint(
                    x: (area.maxX - size.width - Self.margin).rounded(),
                    y: (area.maxY - size.height - Self.margin).rounded()))
        }
        window.orderFrontRegardless()
    }

    /// Takes the panel off the screen.
    public func hide() {
        window?.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    /// The close button is Skip Guide: the model stores the flag and closes the guide, which hides the panel.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.skipGuide()
        return false
    }

    // MARK: Window

    private func ensureWindow() -> OnboardingWindow {
        if let window { return window }
        let controller = NSHostingController(rootView: OnboardingView(model: model, host: host))
        controller.sizingOptions = [.preferredContentSize]
        let window = OnboardingWindow(contentViewController: controller)
        window.title = String(localized: "Getting Started", bundle: .module)
        window.delegate = self
        // Size the window to the view before it is placed.
        let fitting = controller.view.fittingSize
        window.setContentSize(fitting)
        self.window = window
        return window
    }
}

/// The panel itself: never key, never main, and placed exactly.
@MainActor
final class OnboardingWindow: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: OnboardingView.width, height: 200),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered,
            defer: false)
        self.contentViewController = contentViewController
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = OnboardingPanel.level
        collectionBehavior = OnboardingPanel.collectionBehavior
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The panel is placed exactly: AppKit must not move it to keep it inside a screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
