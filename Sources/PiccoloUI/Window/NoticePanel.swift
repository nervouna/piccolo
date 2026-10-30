import AppKit
import PiccoloCore

/// The failure notice: a rounded, translucent HUD with a symbol and one line of text, in the middle
/// of a display, for about a second.
///
/// The panel follows the rules of the destination preview's highlight (`HighlightPanels`): it must
/// never take the focus or activate Piccolo, because a window that comes to the front in the middle of
/// a shortcut would be the one the next action finds focused, and an app that has been the active
/// application stops firing simulated hotkeys (see `CLAUDE.md`). It is therefore a non-activating
/// panel that cannot become key or main, is shown with `orderFrontRegardless()` and never with
/// `makeKeyAndOrderFront(_:)`, ignores the mouse and does not hide when Piccolo is not the active
/// application. Level ``level`` (`.statusBar`), collection behaviour ``collectionBehavior``.
///
/// A new notice while one is showing replaces it and restarts the timer.
@MainActor
public final class NoticePanel {
    /// The window level of the panel.
    public static let level = NSWindow.Level.statusBar

    /// The collection behaviour of the panel.
    public static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]

    /// How long the notice stays fully shown, and how long it takes to fade out, in seconds.
    public static let displayDuration: TimeInterval = 1.0
    public static let fadeDuration: TimeInterval = 0.2

    static let cornerRadius: CGFloat = 12
    static let fontSize: CGFloat = 15
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 14
    static let spacing: CGFloat = 10
    static let maximumTextWidth: CGFloat = 420

    private var panel: NoticeWindow?
    private var generation = 0
    private var hideWork: DispatchWorkItem?

    public init() {}

    /// Whether a notice is on screen (shown or fading out).
    public private(set) var isVisible = false

    /// The frame of the panel in canonical coordinates, as long as it is visible; `nil` otherwise.
    public var canonicalFrame: CGRect? {
        guard isVisible, let panel, let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return ScreenSpace.canonicalRect(fromAppKit: panel.frame, primaryDisplayHeight: primaryHeight)
    }

    /// Shows `text` with the SF Symbol `symbolName`, centred on `visibleFrame` (canonical coordinates),
    /// replacing a notice that is showing.
    public func show(text: String, symbolName: String, centeredIn visibleFrame: CGRect) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        generation += 1
        let mine = generation
        hideWork?.cancel()

        let panel = self.panel ?? NoticeWindow()
        self.panel = panel
        let content = panel.noticeView
        content.set(text: text, symbolName: symbolName)
        let size = content.fittingSize
        let center = ScreenSpace.appKitRect(fromCanonical: visibleFrame, primaryDisplayHeight: primaryHeight)
        let frame = NSRect(
            x: (center.midX - size.width / 2).rounded(), y: (center.midY - size.height / 2).rounded(),
            width: size.width, height: size.height)
        panel.setFrame(frame, display: false)

        // Cancel a fade-out that is running, and show it fully.
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        isVisible = true

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == mine else { return }
                self.fadeOut(generation: mine)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration, execute: work)
    }

    /// Hides the notice at once.
    public func hide() {
        generation += 1
        hideWork?.cancel()
        panel?.orderOut(nil)
        isVisible = false
    }

    private func fadeOut(generation mine: Int) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    // Replaced in the meantime: leave it.
                    guard let self, self.generation == mine else { return }
                    panel.orderOut(nil)
                    self.isVisible = false
                }
            })
    }
}

/// The panel itself: never key, never main, and placed exactly.
@MainActor
final class NoticeWindow: NSPanel {
    let noticeView = NoticeView()

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = NoticePanel.level
        collectionBehavior = NoticePanel.collectionBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        contentView = noticeView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The panel is placed exactly: AppKit must not move it to keep it inside a screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The HUD: a translucent rounded background with a symbol before the text.
@MainActor
final class NoticeView: NSVisualEffectView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = NoticePanel.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: NoticePanel.fontSize, weight: .medium)
        icon.contentTintColor = .labelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        label.font = .systemFont(ofSize: NoticePanel.fontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = NoticePanel.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: NoticePanel.horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -NoticePanel.horizontalPadding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: NoticePanel.verticalPadding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -NoticePanel.verticalPadding),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: NoticePanel.maximumTextWidth),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func set(text: String, symbolName: String) {
        label.stringValue = text
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        layoutSubtreeIfNeeded()
    }
}
