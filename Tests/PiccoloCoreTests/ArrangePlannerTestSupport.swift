import CoreGraphics
import Testing

@testable import PiccoloCore

/// Fixtures shared by the `ArrangePlanner` test files.
enum ArrangePlannerSupport {
    /// The primary display. Its visible frame, below a 25 pt menu bar, is `(0, 25, 1440, 875)`.
    static let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))

    /// A display to the right of the primary, with a 25 pt Dock at the bottom.
    static let right = Display(
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))

    static let twoDisplays = [primary, right]

    /// A rect fully on the primary display.
    static let onPrimary = CGRect(x: 100, y: 100, width: 400, height: 300)

    /// A rect fully on the right display.
    static let onRight = CGRect(x: 1600, y: 100, width: 400, height: 300)

    static let last4In2x2 = GridSpec(count: 4, rows: 2, columns: 2)

    /// A standard, visible, windowed candidate. Its frame is on the primary display by default.
    static func window(
        _ raw: UInt32,
        frame: CGRect = ArrangePlannerSupport.onPrimary,
        standard: Bool = true,
        minimized: Bool = false,
        fullScreen: Bool = false
    ) -> WindowCandidate {
        WindowCandidate(
            id: WindowID(rawValue: raw),
            frame: frame,
            isStandard: standard,
            isMinimized: minimized,
            isFullScreen: fullScreen)
    }

    /// `count` standard windows on the primary display, numbered 1 to `count` and listed front to back.
    static func windows(_ count: Int) -> [WindowCandidate] {
        (0..<count).map { window(UInt32($0 + 1)) }
    }

    /// The window IDs for the raw values, in order.
    static func ids(_ raw: [UInt32]) -> [WindowID] {
        raw.map { WindowID(rawValue: $0) }
    }

    /// A history whose `order` is `raw`, most recent first.
    static func history(_ raw: [UInt32]) -> FocusHistory {
        var history = FocusHistory()
        for value in raw.reversed() {
            history.recordFocus(WindowID(rawValue: value))
        }
        return history
    }

    /// Runs the planner with the arguments the tests usually leave alone.
    static func plan(
        grid: GridSpec = last4In2x2,
        displayIndex: Int = 0,
        candidates: [WindowCandidate],
        history: FocusHistory = FocusHistory(),
        displays: [Display] = twoDisplays
    ) throws(ArrangePlannerError) -> ArrangePlan? {
        try ArrangePlanner.plan(
            grid: grid,
            displayIndex: displayIndex,
            candidates: candidates,
            history: history,
            displays: displays)
    }

    /// Runs the planner and requires a plan.
    static func planned(
        grid: GridSpec = last4In2x2,
        displayIndex: Int = 0,
        candidates: [WindowCandidate],
        history: FocusHistory = FocusHistory(),
        displays: [Display] = twoDisplays
    ) throws -> ArrangePlan {
        let result = try plan(
            grid: grid,
            displayIndex: displayIndex,
            candidates: candidates,
            history: history,
            displays: displays)
        return try #require(result)
    }

    /// The frames `TileLayout.grid` gives `count` windows on `visible`, in row-major order.
    static func gridFrames(_ count: Int, rows: Int = 2, columns: Int = 2, on visible: CGRect) -> [CGRect] {
        TileLayout.grid(windowCount: count, rows: rows, columns: columns).frames(in: visible)
    }
}
