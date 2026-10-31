import AppKit
import SwiftUI

/// The content of the Settings window: the view of the selected tab, filling the window.
///
/// Both tabs are SwiftUI views in a hosting controller of their own; only the selected one has its
/// view in the window. The window decides their size, except for the General tab's height: that
/// is the height its content asks for (``generalFittingHeight``), which the window follows.
@MainActor
final class SettingsContentController: NSViewController {
    private let shortcuts: NSHostingController<ShortcutsTab>
    private let general: NSHostingController<GeneralPane>
    let generalHeight = GeneralHeight()

    /// The tab whose view is in the window, if any has been shown.
    private(set) var tab: SettingsTab?
    /// Called when the height the General tab asks for may have changed.
    var onGeneralFittingHeightChange: (() -> Void)?

    init(model: SettingsModel, host: SettingsHost) {
        shortcuts = NSHostingController(rootView: ShortcutsTab(model: model, host: host))
        general = NSHostingController(
            rootView: GeneralPane(model: model, host: host, height: generalHeight))
        super.init(nibName: nil, bundle: nil)
        // The window decides the size of both tabs, not their content: nothing in the views may resize
        // the window by itself, which would not keep its top edge or animate.
        shortcuts.sizingOptions = []
        general.sizingOptions = []
        addChild(shortcuts)
        addChild(general)
        generalHeight.onChange = { [weak self] in
            // Reported while the view is laid out: the window changes its size after that.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onGeneralFittingHeightChange?() }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsContentController is not loaded from a nib")
    }

    override func loadView() {
        // The view has its size before the window exists: laid out at zero size first, the content's
        // padding would make its width negative.
        view = NSView(
            frame: NSRect(origin: .zero, size: SettingsWindowSizing.shortcutsDefaultContentSize))
    }

    private func controller(for tab: SettingsTab) -> NSViewController {
        switch tab {
        case .shortcuts: shortcuts
        case .general: general
        }
    }

    /// Puts the view of `tab` in the window, in place of the other one's.
    func show(_ tab: SettingsTab) {
        guard tab != self.tab else { return }
        if let shown = self.tab {
            controller(for: shown).view.removeFromSuperview()
        }
        let incoming = controller(for: tab).view
        incoming.frame = view.bounds
        incoming.autoresizingMask = [.width, .height]
        view.addSubview(incoming)
        self.tab = tab
        // Laid out now, so that the height the General tab asks for is there to be read.
        view.layoutSubtreeIfNeeded()
    }

    /// The height the General tab's content asks for at its width: the height at which it does not
    /// scroll. Zero until the tab has been laid out.
    var generalFittingHeight: CGFloat {
        generalHeight.value
    }

    /// Whether the selected tab's content fits its visible area without scrolling: no scroll view in
    /// it has more to show than it shows, and the General tab is as tall as it asks to be.
    var contentFits: Bool {
        guard let tab else { return true }
        view.layoutSubtreeIfNeeded()
        let tolerance: CGFloat = 1
        for scrollView in Self.scrollViews(in: controller(for: tab).view) {
            guard let document = scrollView.documentView else { continue }
            if document.frame.height > scrollView.contentView.bounds.height + tolerance { return false }
        }
        if tab == .general, generalFittingHeight > view.bounds.height + tolerance { return false }
        return true
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scrollView = view as? NSScrollView, !scrollView.isHiddenOrHasHiddenAncestor {
            found.append(scrollView)
        }
        for subview in view.subviews {
            found += scrollViews(in: subview)
        }
        return found
    }
}

/// The height the General tab's content asks for, as the tab reports it.
@MainActor
final class GeneralHeight {
    private(set) var value: CGFloat = 0
    var onChange: (() -> Void)?

    func report(_ height: CGFloat) {
        guard abs(height - value) > 0.01 else { return }
        value = height
        onChange?()
    }
}

/// The General tab at the width of its window: its form fixed at that width, in a scroll view for the
/// screen that is too small for it.
///
/// The content is laid out at the height it asks for whatever the window's, and reports that height
/// (the window is made as tall as that, or as tall as its screen allows). Without the scroll view, a
/// window as tall as the content asks gives the strip of problems with the config file more than it
/// needs and the form less, which then scrolls.
struct GeneralPane: View {
    let model: SettingsModel
    let host: SettingsHost
    let height: GeneralHeight

    var body: some View {
        ScrollView {
            GeneralTab(model: model, host: host)
                .frame(width: SettingsWindowSizing.generalContentWidth)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    height.report(newHeight)
                }
        }
    }
}
