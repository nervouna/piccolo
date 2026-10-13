import AppKit
import ApplicationServices

/// The process's Accessibility (AXIsProcessTrusted) permission.
///
/// The system ties the grant to the app's bundle ID and signing identity, and
/// asks about the "responsible process": launch Piccolo through LaunchServices
/// (Finder, `open`), not from a terminal, or the terminal's grant is checked.
public struct AccessibilityPermission: Sendable {
    /// The Accessibility pane of System Settings > Privacy & Security.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    public init() {}

    /// Whether this process is currently trusted for Accessibility. Never prompts.
    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that offers to open System Settings when the
    /// process is not trusted. Does nothing visible when it already is.
    ///
    /// - Returns: Whether the process is trusted at the time of the call.
    @discardableResult
    public func requestPrompt() -> Bool {
        // The literal is the value of `kAXTrustedCheckOptionPrompt`. The imported
        // global is a mutable `Unmanaged<CFString>`, which Swift 6 rejects as
        // shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility pane of System Settings.
    @MainActor
    public func openSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }
}
