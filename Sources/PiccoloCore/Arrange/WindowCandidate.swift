import CoreGraphics

/// A window the arrange planner may move, as the system reports it.
public struct WindowCandidate: Equatable, Sendable {
    /// The window's identity, as used by `FocusHistory`.
    public var id: WindowID
    /// The window's frame in the canonical space, including the title bar.
    public var frame: CGRect
    /// Whether the window is a standard window, rather than a panel, sheet or other auxiliary window.
    public var isStandard: Bool
    public var isMinimized: Bool
    public var isFullScreen: Bool

    public init(
        id: WindowID,
        frame: CGRect,
        isStandard: Bool,
        isMinimized: Bool,
        isFullScreen: Bool
    ) {
        self.id = id
        self.frame = frame
        self.isStandard = isStandard
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
    }
}
