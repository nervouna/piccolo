import AppKit

/// The application that currently receives keyboard input.
public struct FrontmostApplication: Sendable, Equatable {
    public var pid: pid_t
    public var bundleID: String?
    public var name: String?

    public init(pid: pid_t, bundleID: String?, name: String?) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }

    /// The frontmost application, or nil when there is none (for example on the login
    /// window).
    public static func current() -> FrontmostApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostApplication(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            name: app.localizedName)
    }
}
