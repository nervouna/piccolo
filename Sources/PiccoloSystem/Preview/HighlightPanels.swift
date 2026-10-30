import AppKit
import PiccoloCore

/// The highlight of the destination preview: one panel per destination frame, drawn as a rounded
/// rectangle in the accent colour, as the window-tiling preview of macOS is.
///
/// The panels must never take the focus or activate Piccolo: a window that comes to the front in
/// the middle of a shortcut would be the one the action then finds focused, and an app that has been
/// the active application stops firing simulated hotkeys (see `docs/acceptance.md`). They are therefore
/// non-activating panels that cannot become key or main, are shown with `orderFrontRegardless()` and
/// never with `makeKeyAndOrderFront(_:)`, ignore the mouse, and do not hide when Piccolo is not
/// the active application (which a panel does by default, and Piccolo never is).
///
/// - Level: ``level``, `.statusBar`, above ordinary windows and floating panels, below menus.
/// - Collection behaviour: `canJoinAllSpaces` and `fullScreenAuxiliary` (on the current Space, also
///   over a full-screen app), `stationary` (not moved by Mission Control) and `ignoresCycle` (not in
///   the window cycle).
@MainActor
public final class HighlightPanels: HighlightPresenter {
    /// The window level of the panels.
    public static let level = NSWindow.Level.statusBar

    /// The collection behaviour of the panels.
    public static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]

    /// How long the highlight takes to fade in and out, in seconds.
    static let fadeIn: TimeInterval = 0.08
    static let fadeOut: TimeInterval = 0.12

    private var panels: [HighlightPanel] = []
    /// Counts the calls, so that the end of a fade-out knows whether the panel has been used since.
    private var generation = 0

    public init() {}

    public func present(_ frames: [CGRect]) {
        generation += 1
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        while panels.count < frames.count {
            panels.append(HighlightPanel())
        }
        for (panel, frame) in zip(panels, frames) {
            panel.setFrame(
                ScreenSpace.appKitRect(fromCanonical: frame, primaryDisplayHeight: primaryHeight),
                display: false)
            panel.contentView?.needsDisplay = true
            if !panel.isVisible {
                panel.alphaValue = 0
            }
            panel.orderFrontRegardless()
            fade(panel, to: 1, duration: Self.fadeIn)
        }
        for panel in panels.dropFirst(frames.count) {
            panel.orderOut(nil)
        }
    }

    public func dismiss() {
        generation += 1
        let mine = generation
        let visible = panels.filter(\.isVisible)
        for panel in visible {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = Self.fadeOut
                    panel.animator().alphaValue = 0
                },
                completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        // Used again in the meantime: leave it.
                        guard let self, self.generation == mine else { return }
                        panel.orderOut(nil)
                    }
                })
        }
    }

    private func fade(_ panel: NSPanel, to alpha: CGFloat, duration: TimeInterval) {
        guard panel.alphaValue != alpha else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alpha
        }
    }
}

/// A panel that shows one highlight and nothing else.
@MainActor
final class HighlightPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = HighlightPanels.level
        collectionBehavior = HighlightPanels.collectionBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        contentView = HighlightView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The panel is placed exactly: AppKit must not move it to keep it inside a screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The picture: a rounded rectangle filled with the accent colour at low opacity and outlined with it.
/// The colours are the system's dynamic ones, resolved when the view draws, so that it follows light
/// and dark mode and the accent colour.
final class HighlightView: NSView {
    static let cornerRadius: CGFloat = 10
    static let borderWidth: CGFloat = 3
    static let fillOpacity: CGFloat = 0.2

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let inset = Self.borderWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = min(Self.cornerRadius, rect.width / 2, rect.height / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.controlAccentColor.withAlphaComponent(Self.fillOpacity).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = Self.borderWidth
        path.stroke()
    }
}
