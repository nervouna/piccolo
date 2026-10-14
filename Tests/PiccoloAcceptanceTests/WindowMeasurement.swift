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
        ofWindow windowNumber: Int, matching expected: CGRect, tolerance: CGFloat = frameTolerance
    ) -> Observation<CGRect> {
        guard let measured = frame(ofWindow: windowNumber) else {
            return .unsatisfied("window \(windowNumber) is not listed as on screen")
        }
        guard framesMatch(measured, expected, tolerance: tolerance) else {
            return .unsatisfied("measured \(describe(measured))")
        }
        return .satisfied(measured)
    }

    /// How long a frame has to stay as it is to count as the window's frame.
    static let settleTime: TimeInterval = 0.03

    /// Waits until the window is measured at `expected` (within `tolerance`) and returns what was
    /// measured.
    ///
    /// The window server shows a frame some milliseconds after the app made it, and a window that
    /// glides (the animation of every action) passes frames within the tolerance of its target a
    /// moment before it arrives. A frame therefore counts only once the same frame was measured twice,
    /// ``settleTime`` apart: otherwise a frame a point short of the target would be returned, and the
    /// edges of neighbouring windows could be a point or two apart.
    static func waitForFrame(
        ofWindow windowNumber: Int, matching expected: CGRect, tolerance: CGFloat = frameTolerance,
        timeout: TimeInterval = 5
    ) async throws -> CGRect {
        var candidate: (frame: CGRect, since: ContinuousClock.Instant)?
        let clock = ContinuousClock()
        return try await eventually(
            "window \(windowNumber) to be measured at \(describe(expected)) ±\(tolerance), and to stay there",
            timeout: timeout, interval: settleTime
        ) { () -> Observation<CGRect> in
            switch observation(ofWindow: windowNumber, matching: expected, tolerance: tolerance) {
            case .unsatisfied(let seen):
                candidate = nil
                return .unsatisfied(seen)
            case .satisfied(let measured):
                if let held = candidate, held.frame == measured {
                    return held.since.duration(to: clock.now) >= .seconds(settleTime)
                        ? .satisfied(measured) : .unsatisfied("measured \(describe(measured)), not yet for \(settleTime) s")
                }
                candidate = (measured, clock.now)
                return .unsatisfied("measured \(describe(measured)), not yet settled")
            }
        }
    }
}
