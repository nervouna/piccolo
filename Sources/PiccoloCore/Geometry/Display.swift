import CoreGraphics

/// One screen in the canonical space (top-left origin, y down).
public struct Display: Equatable, Sendable {
    /// The whole screen.
    public var frame: CGRect
    /// The screen without the menu bar and the Dock.
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}
