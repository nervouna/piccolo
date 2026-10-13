import CoreGraphics
import Foundation

/// Independent measurement of windows: straight from the window server (CGWindowList),
/// by window number. It deliberately uses neither Piccolo's adapters nor the fixture's
/// own report, so that a bug in either cannot hide itself.
///
/// The window server reports frames in canonical coordinates (global, top-left origin,
/// y down) and, without the Screen Recording permission, bounds but no titles.
enum Measure {
    /// The on-screen frame of the window with this number, or nil when the window
    /// server does not list it as on screen.
    static func frame(ofWindow windowNumber: Int) -> CGRect? {
        guard windowNumber > 0,
            let entries = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]],
            let entry = entries.first(where: {
                ($0[kCGWindowNumber as String] as? Int) == windowNumber
            }),
            entry[kCGWindowIsOnscreen as String] as? Bool == true,
            let bounds = entry[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    /// An observation of the window's frame for `eventually`, matching `expected`.
    static func observation(
        ofWindow windowNumber: Int, matching expected: CGRect
    ) -> Observation<CGRect> {
        guard let measured = frame(ofWindow: windowNumber) else {
            return .unsatisfied("window \(windowNumber) is not listed as on screen")
        }
        guard framesMatch(measured, expected) else {
            return .unsatisfied("measured \(describe(measured))")
        }
        return .satisfied(measured)
    }

    /// Waits until the window is measured at `expected` (within the tolerance) and
    /// returns what was measured.
    static func waitForFrame(
        ofWindow windowNumber: Int, matching expected: CGRect, timeout: TimeInterval = 5
    ) async throws -> CGRect {
        try await eventually(
            "window \(windowNumber) to be measured at \(describe(expected)) ±\(frameTolerance)",
            timeout: timeout
        ) {
            observation(ofWindow: windowNumber, matching: expected)
        }
    }
}
