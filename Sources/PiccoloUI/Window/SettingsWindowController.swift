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

    /// The name the frame is saved under. It changed with the taller default size, so that a frame
    /// saved by an earlier version, too short for the General tab, is not restored.
    private static let frameAutosaveName = "PiccoloSettings.v4"
    /// Tall enough for the whole General tab without scrolling (its form is about 830 pt high, and the
    /// tabs and the padding around it take about 60 pt). The restart note of the language picker, which
    /// is there only after a change, makes the form about 80 pt higher; it scrolls then.
    static let defaultContentSize = NSSize(width: 640, height: 920)
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

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let hosting = NSHostingController(rootView: SettingsView(model: model, host: host))
        // The window decides its size, not the content: the content fills it.
        hosting.sizingOptions = []
        // The view has its size before the window exists: laid out at zero size first, the
        // content's padding would make its width negative.
        hosting.view.frame = NSRect(origin: .zero, size: Self.defaultContentSize)

        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Piccolo Settings", bundle: .module)
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
