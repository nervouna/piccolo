import AppKit
import PiccoloCore
import SwiftUI

/// Owns the Settings window: an `NSWindow` that hosts ``SettingsView``, created on first use and
/// kept for the rest of the run.
///
/// It is also what keeps recording from outliving its window: closing the window, the window
/// losing key status and the app being deactivated all cancel a recording, which restores the
/// global hotkeys. While the window is open and a binding is recording, it catches the key
/// press before the rest of the app sees it, so that shortcuts like ⌘Q or ⌘, can be recorded.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public let model: SettingsModel
    private let host: SettingsHost
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var deactivationObserver: (any NSObjectProtocol)?
    private var activationObserver: (any NSObjectProtocol)?

    private static let frameAutosaveName = "PiccoloSettings"
    private static let defaultContentSize = NSSize(width: 640, height: 580)
    private static let minimumContentSize = NSSize(width: 560, height: 480)

    public init(model: SettingsModel, host: SettingsHost) {
        self.model = model
        self.host = host
        super.init()
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.cancelRecording()
            }
        }
        // Back from System Settings, where the user may have allowed or removed the login item.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshLoginItem()
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

    // MARK: Showing and closing

    /// Opens the window, or brings it to the front, and activates the app.
    ///
    /// Since macOS 14 an app is not always allowed to activate itself. When the request comes from
    /// the user (a click on a menu item) the system allows it; otherwise the window is on screen
    /// but may stay behind other apps, and launching the app again through LaunchServices brings it
    /// forward.
    public func show() {
        let window = ensureWindow()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        installKeyMonitor()
        model.refreshLoginItem()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window and cancels any recording, also when the window was not open.
    public func close() {
        model.cancelRecording()
        window?.close()
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let hosting = NSHostingController(rootView: SettingsView(model: model, host: host))
        // The window decides its size, not the content: the content fills it.
        hosting.sizingOptions = []
        // The view has its size before the window exists: laid out at zero size first, the
        // content's padding would make its width negative.
        hosting.view.frame = NSRect(origin: .zero, size: Self.defaultContentSize)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Piccolo Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = Self.minimumContentSize
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        self.window = window
        return window
    }

    // MARK: NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
        // A confirmation still showing must not come back with the window the next time it opens.
        model.cancelRestoreDefaults()
        removeKeyMonitor()
    }

    public func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }

    // MARK: Key presses while recording

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

    /// Gives a key press to the model if a binding is recording and the press is for this window.
    /// Returns `nil` (the event is swallowed) when the recorder took it.
    private func offer(_ event: NSEvent) -> NSEvent? {
        guard model.recordingBindingID != nil, isKey, event.window === window else {
            return event
        }
        let press = Shortcut(keyCode: Int(event.keyCode), modifiers: Self.modifiers(of: event))
        return model.record(press) ? nil : event
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
