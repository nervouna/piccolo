import AppKit
import PiccoloCore

/// A display, in canonical coordinates.
public struct ScreenInfo: Sendable, Equatable {
    /// Position in `NSScreen.screens`; 0 is the primary display.
    public var index: Int
    public var isPrimary: Bool
    public var frame: CGRect
    /// The frame without the menu bar and the Dock.
    public var visibleFrame: CGRect

    public init(index: Int, isPrimary: Bool, frame: CGRect, visibleFrame: CGRect) {
        self.index = index
        self.isPrimary = isPrimary
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

extension ScreenInfo {
    /// The same screen as the pure geometry type of `PiccoloCore`.
    public var display: Display {
        Display(frame: frame, visibleFrame: visibleFrame)
    }
}

public enum Screens {
    /// The attached displays, converted from AppKit space to canonical space.
    @MainActor
    public static func current() -> [ScreenInfo] {
        make(from: NSScreen.screens.map { (frame: $0.frame, visibleFrame: $0.visibleFrame) })
    }

    /// The screens as `Display`s for `PiccoloCore`, in the same order: the first is the primary display.
    public static func displays(from screens: [ScreenInfo]) -> [Display] {
        screens.map(\.display)
    }

    /// The attached displays as `Display`s, readable from any thread.
    ///
    /// `NSScreen` belongs to the main thread, so a call from another thread (the control server's
    /// queue, say) waits for the main thread. Called on the main thread it reads directly.
    public static func currentDisplays() -> [Display] {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { displays(from: current()) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { displays(from: current()) }
        }
    }

    /// Converts AppKit-space frames (`NSScreen.frame` and `visibleFrame`, in
    /// `NSScreen.screens` order) to canonical space. The first entry is the primary
    /// display, whose height anchors the conversion.
    static func make(from screens: [(frame: CGRect, visibleFrame: CGRect)]) -> [ScreenInfo] {
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return screens.enumerated().map { index, screen in
            ScreenInfo(
                index: index,
                isPrimary: index == 0,
                frame: ScreenSpace.canonicalRect(
                    fromAppKit: screen.frame, primaryDisplayHeight: primaryHeight),
                visibleFrame: ScreenSpace.canonicalRect(
                    fromAppKit: screen.visibleFrame, primaryDisplayHeight: primaryHeight))
        }
    }
}
