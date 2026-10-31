import AppKit
import PiccoloCore
import SwiftUI

/// Owns the Settings window: an `NSWindow` with toolbar tabs (Shortcuts and General) that hosts the
/// views of the tabs, created on first use and kept for the rest of the run.
///
/// ``SettingsModel/tab`` is the source of truth for the tab: a click on a toolbar item sets it, and
/// whatever sets it (the debug control channel) changes the tab of an open window. Each tab has its
/// own window size (see ``SettingsWindowSizing``): the window animates to it when the tab changes,
/// keeping its top edge, and is never taller than the visible frame of its screen. Opening the
/// window and changing the tab leave no text field with the focus.
///
/// It is also what keeps recording from outliving its window: closing the window, the window
/// losing key status and the app being deactivated all cancel a recording, which restores the
/// global hotkeys. While the window is open and a binding is recording, it catches the key
/// press before the rest of the app sees it, so that shortcuts like ⌘Q or ⌘, can be recorded. When
/// nothing records it catches ⌘Z and ⇧⌘Z for ``SettingsModel/undo()`` and ``SettingsModel/redo()``,
/// since Piccolo has no Edit menu.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    public let model: SettingsModel
    private let host: SettingsHost
    private var window: NSWindow?
    private(set) var content: SettingsContentController?
    private var toolbar: NSToolbar?
    /// The content size of the Shortcuts tab: the one the person gave it, restored from the saved frame.
    private var shortcutsContentSize = SettingsWindowSizing.shortcutsDefaultContentSize
    /// How many frame changes the controller itself is making. The person's moves and resizes are
    /// those that come while it is zero.
    private var ownFrameChanges = 0
    /// Whether the next time the window becomes key it is being opened, so that no field keeps the focus.
    private var clearsFocusWhenKey = false
    /// The resize animation under way, if any: the frame it goes to, and a number that tells it from the
    /// ones before and after it.
    private var animation: (target: CGRect, id: Int)?
    private var animationCount = 0
    /// Whether the window animates to the size of a tab. A test turns it off, so that it need not wait.
    var animatesFrameChanges = true
    /// Whether the person asked the system for less motion, in which case the window does not animate. A
    /// test sets it, so that the machine's setting does not matter.
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Called, once, when the controller is not changing the window's frame any more: the last resize
    /// animation it started has reported that it is over. A test waits for it, in place of a clock.
    var onResizeEnd: (() -> Void)?
    private var keyMonitor: Any?
    /// How many key presses the key monitor has handled for this window while it was key, whatever it did
    /// with them. The debug control channel posts a key press and waits for this to change
    /// (`settings.pressKey`); nothing else reads it.
    public private(set) var keyPressesSeen = 0
    private var deactivationObserver: (any NSObjectProtocol)?
    private var activationObserver: (any NSObjectProtocol)?

    /// The name the frame of the Shortcuts tab is saved under. Only that tab's frame is: the General
    /// tab's size follows its content.
    static let defaultFrameName = "PiccoloSettings.shortcuts"
    private let frameName: String

    /// The visible frame of the screen a window is on, in AppKit space. A test sets another one.
    var visibleFrameProvider: (NSWindow) -> CGRect? = { window in
        (window.screen ?? NSScreen.main)?.visibleFrame
    }

    public convenience init(model: SettingsModel, host: SettingsHost) {
        self.init(model: model, host: host, frameName: Self.defaultFrameName)
    }

    /// - Parameter frameName: The name the Shortcuts tab's frame is saved under. Tests give theirs.
    init(model: SettingsModel, host: SettingsHost, frameName: String) {
        self.model = model
        self.host = host
        self.frameName = frameName
        super.init()
        observeTab()
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.cancelRecording()
            }
        }
        // Back from System Settings, where the user may have allowed or removed the login item, or
        // given Piccolo a language of its own.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshLoginItem()
                self?.model.refreshLanguage()
            }
        }
    }

    isolated deinit {
        if let deactivationObserver {
            NotificationCenter.default.removeObserver(deactivationObserver)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: State

    /// Whether the window is on screen (or minimized into the Dock).
    public var isOpen: Bool {
        guard let window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    /// Whether the window is the key window of an active app: the one that receives key presses.
    public var isKey: Bool {
        guard let window else { return false }
        return NSApp.isActive && window.isKeyWindow
    }

    /// The frame of the window in AppKit space, when it is open.
    public var windowFrame: CGRect? {
        guard let window, isOpen else { return nil }
        return window.frame
    }

    /// The title of the window: the name of the selected tab.
    public var windowTitle: String? {
        window?.title
    }

    /// What has the keyboard focus in the window.
    public enum FirstResponderKind: String, Sendable {
        /// The window itself, or nothing: no control has the focus.
        case none
        /// A text field, or the field editor that edits one.
        case textField
        case other
    }

    public var firstResponderKind: FirstResponderKind {
        guard let responder = window?.firstResponder, responder !== window else { return .none }
        if responder is NSTextField { return .textField }
        if let text = responder as? NSTextView, text.isFieldEditor { return .textField }
        return .other
    }

    /// Whether the selected tab's content fits its visible area without scrolling, when the window is
    /// open.
    public var contentFits: Bool? {
        guard isOpen, let content else { return nil }
        return content.contentFits
    }

    // MARK: Showing and closing

    /// Opens the window, or brings it to the front, and makes Piccolo the active application, so
    /// that the window is the key window whichever application was in front. It does so for every
    /// caller alike: the menu's "Settings…", a second launch of the app and the debug control
    /// channel.
    ///
    /// The window is ordered front at once. The activation is a request to the system, which
    /// answers a moment later (about 0.1 s, measured), so the window can be on screen before
    /// Piccolo is active.
    ///
    /// Since macOS 14 an app cannot always activate itself, and the plain request, `NSApp.activate()`,
    /// is refused now and then: measured on macOS 27 with a window of another application in front
    /// and no user event behind the request, it brought Piccolo forward in 6 of 10 rounds, and in
    /// 5 of 10 with `activate(options: .activateAllWindows)`; in the others the window stayed behind
    /// the other application for good. (The menu is drawn by another process on macOS 27, so a click
    /// on "Settings…" is not an event in Piccolo either.) The request that came through every time
    /// (40 of 40 rounds in 4 runs) is `NSRunningApplication.current.activate(options:)` with
    /// ``takeTheFront`` added. The acceptance test "Settings in front" runs 10 rounds of it.
    ///
    /// Nothing here asks LaunchServices to open Piccolo, so the reopen event of a second launch,
    /// which calls this method, can never start a loop of reopen events. When Piccolo is active
    /// already, only the window is brought forward.
    public func show() {
        let window = ensureWindow()
        let opening = !window.isVisible
        if opening {
            // The tab may have changed, and the screen too, since the window was closed.
            fitWindow(animated: false)
        }
        if opening || !window.isKeyWindow {
            clearsFocusWhenKey = true
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        installKeyMonitor()
        model.refreshLoginItem()
        model.refreshLanguage()
        if !NSApp.isActive {
            NSRunningApplication.current.activate(options: [.activateAllWindows, Self.takeTheFront])
        }
        window.makeKeyAndOrderFront(nil)
        if opening {
            // The toolbar takes its height from the frame once the window is on screen: the size of the
            // tab is fitted again with it, so that the window ends inside the visible frame.
            fitWindow(animated: false)
        }
    }

    /// The activation option that takes the front from the application that has it: the value of
    /// `NSApplication.ActivationOptions.activateIgnoringOtherApps`. The constant is deprecated since
    /// macOS 14 ("will have no effect"), yet on macOS 27 it is the difference between an activation that
    /// is refused now and then and one that never is (see ``show()``), so it is still passed. It is
    /// written as its value so that the build stays free of the deprecation warning; the acceptance
    /// test "settingsInFront 1" is what notices a system that stops honouring it.
    private static let takeTheFront = NSApplication.ActivationOptions(rawValue: 1 << 1)

    /// Closes the window and cancels any recording, also when the window was not open.
    public func close() {
        model.cancelRecording()
        window?.close()
    }

    func ensureWindow() -> NSWindow {
        if let window { return window }
        // The window's first place is not one the person chose: nothing of it is saved.
        ownFrameChanges += 1
        defer { ownFrameChanges -= 1 }

        let content = SettingsContentController(model: model, host: host)
        content.onGeneralFittingHeightChange = { [weak self] in
            self?.generalFittingHeightChanged()
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowSizing.shortcutsDefaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.contentViewController = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.toolbarStyle = .preference
        window.toolbar = makeToolbar()
        self.window = window
        self.content = content

        // The Shortcuts tab's size is the one it was left at, if any; the General tab's follows its content.
        window.contentMinSize = SettingsWindowSizing.shortcutsMinimumContentSize
        window.setContentSize(SettingsWindowSizing.shortcutsDefaultContentSize)
        if window.setFrameUsingName(frameName) {
            shortcutsContentSize = Self.limited(
                window.contentRect(forFrameRect: window.frame).size,
                atLeast: SettingsWindowSizing.shortcutsMinimumContentSize)
        } else {
            window.center()
        }
        showTab(model.tab, animated: false)
        return window
    }

    // MARK: Tabs

    /// Follows ``SettingsModel/tab`` for as long as the controller lives.
    private func observeTab() {
        withObservationTracking {
            _ = model.tab
        } onChange: { [weak self] in
            // Called before the tab has its new value: look at it after.
            Task { @MainActor in
                self?.tabChanged()
                self?.observeTab()
            }
        }
    }

    private func tabChanged() {
        guard let window, let content, content.tab != model.tab else { return }
        // A rejected change belongs to the tab it was made on.
        model.clearError()
        showTab(model.tab, animated: window.isVisible)
        if model.tab == .general {
            // The user can change the login item and the language in System Settings at any time.
            model.refreshLoginItem()
            model.refreshLanguage()
        }
    }

    /// Shows `tab`: its view, its name as the window title, its toolbar item highlighted and its size.
    private func showTab(_ tab: SettingsTab, animated: Bool) {
        guard let window, let content else { return }
        content.show(tab)
        window.title = SettingsTabText.title(of: tab)
        toolbar?.selectedItemIdentifier = Self.itemIdentifier(of: tab)
        // Only the Shortcuts tab can be resized, and so zoomed.
        window.standardWindowButton(.zoomButton)?.isEnabled = tab == .shortcuts
        fitWindow(animated: animated)
        clearFocus()
    }

    /// Gives the window the size of the selected tab, with its top-left corner where it is and inside
    /// `visibleFrame` (default: that of its screen).
    private func fitWindow(animated: Bool, visibleFrame: CGRect? = nil) {
        guard let window, let tab = content?.tab,
            let visible = visibleFrame ?? visibleFrameProvider(window)
        else { return }
        let contentSize: CGSize
        switch tab {
        case .shortcuts:
            contentSize = shortcutsContentSize
        case .general:
            // Zero when the tab has not been laid out yet: its form then scrolls until it has.
            let height = content?.generalFittingHeight ?? 0
            contentSize = CGSize(
                width: SettingsWindowSizing.generalContentWidth,
                height: height > 0 ? height : SettingsWindowSizing.shortcutsDefaultContentSize.height)
        }
        let windowSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        let frame = SettingsWindowSizing.frame(replacing: window.frame, size: windowSize, visibleFrame: visible)

        // The limits come first: a frame outside them would be pulled back.
        let fitted = window.contentRect(forFrameRect: frame).size
        switch tab {
        case .shortcuts:
            window.contentMinSize = Self.limited(
                SettingsWindowSizing.shortcutsMinimumContentSize, atMost: fitted)
            window.contentMaxSize = SettingsWindowSizing.unlimited
        case .general:
            window.contentMinSize = fitted
            window.contentMaxSize = fitted
        }
        setFrame(frame, animated: animated)
    }

    /// Whether the controller is changing the window's frame itself: a resize animation it started has
    /// not reported that it is over.
    var isResizing: Bool {
        ownFrameChanges > 0
    }

    func generalFittingHeightChanged() {
        guard content?.tab == .general else { return }
        fitWindow(animated: window?.isVisible ?? false)
    }

    /// Gives the window `frame`, animated when it can be. The last frame asked for is the one the window ends
    /// at, whether an earlier animation is still under way or not.
    ///
    /// An animation under way is only left alone when it goes to `frame` already. Otherwise it is replaced,
    /// by a new animation or, when the frame is not to be animated, by one that takes no time: a frame set
    /// with `NSWindow.setFrame` does not stop it, it would carry on and overwrite the frame. The window's
    /// frame says nothing about an animation under way (it moves on a later turn of the run loop, and may
    /// be where the new frame is when that arrives): the frame the animation goes to is what counts.
    private func setFrame(_ frame: CGRect, animated: Bool) {
        guard let window else { return }
        if let animation {
            if Self.isSame(animation.target, frame) { return }
        } else if Self.isSame(frame, window.frame) {
            return
        }
        let animates = animated && animatesFrameChanges && window.isVisible && !reducesMotion()
        guard animates || animation != nil else {
            ownFrameChanges += 1
            window.setFrame(frame, display: window.isVisible)
            ownFrameChanges -= 1
            return
        }
        animationCount += 1
        let id = animationCount
        animation = (frame, id)
        ownFrameChanges += 1
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = animates ? window.animationResizeTime(frame) : 0
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            },
            completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // The report of an animation that was replaced says nothing about the one that replaced
                    // it: each ends its own, whichever comes first.
                    self.ownFrameChanges -= 1
                    if self.animation?.id == id { self.animation = nil }
                    if self.ownFrameChanges == 0, let onResizeEnd = self.onResizeEnd {
                        self.onResizeEnd = nil
                        onResizeEnd()
                    }
                }
            })
    }

    private static func isSame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }

    private static func limited(_ size: CGSize, atLeast minimum: CGSize) -> CGSize {
        CGSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
    }

    private static func limited(_ size: CGSize, atMost maximum: CGSize) -> CGSize {
        CGSize(width: min(size.width, maximum.width), height: min(size.height, maximum.height))
    }

    /// Moves the window to the top-left corner of the visible frame of the screen at `index` in
    /// `NSScreen.screens` (inset by 40 pt), and fits its size to that screen. Returns whether the window
    /// is open and there is such a screen. The debug control channel uses it, so that a test can look at
    /// the window on each screen.
    @discardableResult
    public func moveWindow(toScreenAt index: Int) -> Bool {
        guard let window, isOpen, NSScreen.screens.indices.contains(index) else { return false }
        let visible = NSScreen.screens[index].visibleFrame
        ownFrameChanges += 1
        window.setFrameTopLeftPoint(CGPoint(x: visible.minX + 40, y: visible.maxY - 40))
        ownFrameChanges -= 1
        fitWindow(animated: false, visibleFrame: visible)
        return true
    }

    // MARK: Toolbar

    private static func itemIdentifier(of tab: SettingsTab) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(tab.rawValue)
    }

    private static func tab(of identifier: NSToolbarItem.Identifier) -> SettingsTab? {
        SettingsTab(rawValue: identifier.rawValue)
    }

    private static var itemIdentifiers: [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(itemIdentifier(of:))
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "PiccoloSettings.tabs")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        toolbar.centeredItemIdentifiers = Set(Self.itemIdentifiers)
        self.toolbar = toolbar
        return toolbar
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    public func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = Self.tab(of: itemIdentifier) else { return nil }
        let title = SettingsTabText.title(of: tab)
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = title
        item.paletteLabel = title
        item.image = NSImage(systemSymbolName: SettingsTabText.symbolName(of: tab), accessibilityDescription: title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = Self.tab(of: sender.itemIdentifier) else { return }
        model.tab = tab
        // Not waiting for the observation, so that the click is answered at once.
        tabChanged()
    }

    // MARK: Focus

    /// Takes the keyboard focus from whatever has it, so that the window itself is the first
    /// responder until the person clicks a field. The system, or SwiftUI, gives it to the first text
    /// field when a window opens or a view is put in it, and the next pass of the run loop is
    /// after both are done.
    private func clearFocus() {
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let window = self?.window, window.isVisible else { return }
                window.makeFirstResponder(nil)
            }
        }
    }

    // MARK: NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
        // A confirmation still showing, and a shortcut that waits to be replaced, must not come back with
        // the window the next time it opens.
        model.cancelRestoreDefaults()
        model.resolveConflict(replace: false)
        model.dismissLayoutEditor()
        removeKeyMonitor()
    }

    public func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        guard clearsFocusWhenKey else { return }
        clearsFocusWhenKey = false
        clearFocus()
    }

    /// Remembers where the person left the Shortcuts tab: its size and the window's place.
    public func windowDidResize(_ notification: Notification) {
        rememberShortcutsFrame()
    }

    public func windowDidMove(_ notification: Notification) {
        rememberShortcutsFrame()
    }

    private func rememberShortcutsFrame() {
        guard ownFrameChanges == 0, content?.tab == .shortcuts, let window else { return }
        shortcutsContentSize = window.contentRect(forFrameRect: window.frame).size
        window.saveFrame(usingName: frameName)
    }

    /// On another screen the window is fitted to that screen's visible frame.
    public func windowDidChangeScreen(_ notification: Notification) {
        fitWindow(animated: false)
    }

    // MARK: Key presses

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.offer(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Gives a key press to the window's own handling if it is for this window while it is key. Returns
    /// `nil` (the event is swallowed) when the press was taken, the event itself otherwise.
    private func offer(_ event: NSEvent) -> NSEvent? {
        guard isKey, event.window === window else {
            return event
        }
        let taken = take(event)
        // Counted after the press has had its effect, so that a caller that sees the count change sees the result.
        keyPressesSeen += 1
        return taken ? nil : event
    }

    /// What the window does with a key press: while a row records, the recorder takes every press (⌘Z
    /// included, which is a shortcut like any other then); otherwise ⌘Z undoes the last change and ⇧⌘Z
    /// redoes it, unless a text field is being edited (it keeps its own undo) or a sheet is open on the
    /// window (the sheet's own keys). Piccolo has no Edit menu, so nothing else would act on them. Answers
    /// whether the press was taken.
    func take(_ event: NSEvent) -> Bool {
        if model.isRecording {
            let press = Shortcut(keyCode: Int(event.keyCode), modifiers: Self.modifiers(of: event))
            return model.record(press)
        }
        guard
            let command = SettingsUndoKey.command(
                characters: event.charactersIgnoringModifiers, keyCode: Int(event.keyCode),
                modifiers: Self.modifiers(of: event)),
            firstResponderKind != .textField, window?.attachedSheet == nil, model.layoutEditor == nil
        else {
            return false
        }
        switch command {
        case .undo: model.undo()
        case .redo: model.redo()
        }
        // Taken also when there was nothing to undo: nothing else would do anything with the press.
        return true
    }

    /// The modifiers held with a key event, as the config names them.
    static func modifiers(of event: NSEvent) -> Set<Modifier> {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<Modifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
