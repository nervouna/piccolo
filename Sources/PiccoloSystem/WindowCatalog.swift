import ApplicationServices
import CoreGraphics
import Foundation
import PiccoloCore

/// A window the arrange action may move: what the planner needs to know about it, and a handle
/// that sets its frame.
public struct CatalogWindow {
    public var candidate: WindowCandidate
    public var pid: pid_t
    public var handle: any WindowFrameAccess

    public init(candidate: WindowCandidate, pid: pid_t, handle: any WindowFrameAccess) {
        self.candidate = candidate
        self.pid = pid
        self.handle = handle
    }
}

/// One window of an application as Accessibility describes it.
struct AccessibleWindow {
    /// The window's number, or `nil` when the system did not give one (see ``WindowNumber``).
    var number: WindowID?
    var frame: CGRect
    var isStandard: Bool
    var isMinimized: Bool
    var isFullScreen: Bool
    var handle: any WindowFrameAccess
}

/// The windows on screen in the current Space, front to back, ready for ``ArrangePlanner``.
///
/// The window server (CGWindowList) says which windows are on screen and in which order; Accessibility
/// says what kind of window each one is and is the way to set its frame. The two are joined by
/// window number (see ``WindowNumber``). If the number cannot be had for a window, it is joined by
/// application and frame instead.
public enum WindowCatalog {
    /// Accessibility calls made while enumerating are cut off after this long (in seconds), so that
    /// one application that does not answer cannot stall the catalog: it is skipped.
    public static let messagingTimeout: Float = 0.3

    /// The windows on screen right now, front to back.
    ///
    /// Piccolo's own windows are left out. Windows of applications that do not answer Accessibility
    /// within ``messagingTimeout``, and windows that Accessibility does not know, are left out too:
    /// without it a window cannot be moved.
    ///
    /// Only applications with a window on screen are asked, all at the same time, so that the time
    /// it takes is that of the slowest application and not the sum of all of them.
    ///
    /// - Parameter onlyPid: When given, only the windows of this process are listed.
    /// - Throws: ``WindowError/notTrusted`` when Accessibility access is not granted.
    public static func current(onlyPid: pid_t? = nil) throws -> [CatalogWindow] {
        guard AccessibilityPermission().isTrusted else { throw WindowError.notTrusted }
        let onScreen = OnScreenWindows.list()
        let ownPid = ProcessInfo.processInfo.processIdentifier

        let pids = applications(of: onScreen, ownPid: ownPid, onlyPid: onlyPid)
        let answers = Answers()
        DispatchQueue.concurrentPerform(iterations: pids.count) { index in
            answers.set(AccessibilityWindows.read(pid: pids[index], timeout: messagingTimeout), for: pids[index])
        }
        return windows(
            onScreen: onScreen, ownPid: ownPid, onlyPid: onlyPid, accessibleWindows: { answers.get($0) })
    }

    /// What the applications answered, filled in from several threads. The windows hold Accessibility
    /// elements, which are only used again on the thread that asks for the catalog.
    private final class Answers: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [pid_t: [AccessibleWindow]] = [:]

        func set(_ windows: [AccessibleWindow]?, for pid: pid_t) {
            lock.lock()
            defer { lock.unlock() }
            answers[pid] = windows
        }

        func get(_ pid: pid_t) -> [AccessibleWindow]? {
            lock.lock()
            defer { lock.unlock() }
            return answers[pid]
        }
    }

    /// The processes that have a window on screen and may be listed, in the order of their frontmost
    /// window.
    static func applications(of onScreen: [OnScreenWindow], ownPid: pid_t, onlyPid: pid_t?) -> [pid_t] {
        var pids: [pid_t] = []
        for window in onScreen where window.pid != ownPid && (onlyPid == nil || window.pid == onlyPid) {
            if !pids.contains(window.pid) { pids.append(window.pid) }
        }
        return pids
    }

    /// Joins the window server's list with Accessibility's.
    ///
    /// - Parameters:
    ///   - onScreen: The windows on screen, front to back.
    ///   - ownPid: The process whose windows are never listed.
    ///   - onlyPid: When given, the only process whose windows are listed.
    ///   - accessibleWindows: The Accessibility windows of an application, or `nil` when it does not
    ///     answer. It is asked once per application that has a window on screen.
    /// - Returns: The windows that are on screen and known to Accessibility, in the order of `onScreen`.
    static func windows(
        onScreen: [OnScreenWindow],
        ownPid: pid_t,
        onlyPid: pid_t? = nil,
        accessibleWindows: (pid_t) -> [AccessibleWindow]?
    ) -> [CatalogWindow] {
        let wanted = onScreen.filter { $0.pid != ownPid && (onlyPid == nil || $0.pid == onlyPid) }
        let pids = applications(of: onScreen, ownPid: ownPid, onlyPid: onlyPid)

        var found: [Int: CatalogWindow] = [:]
        for pid in pids {
            guard let accessible = accessibleWindows(pid) else { continue }
            let ownWindows = wanted.filter { $0.pid == pid }
            let numbers = WindowMatching.numbers(
                of: accessible.map { (number: $0.number, frame: $0.frame) }, among: ownWindows)
            for (window, number) in zip(accessible, numbers) {
                guard let number else { continue }
                found[Int(number.rawValue)] = CatalogWindow(
                    candidate: WindowCandidate(
                        id: number,
                        frame: window.frame,
                        isStandard: window.isStandard,
                        isMinimized: window.isMinimized,
                        isFullScreen: window.isFullScreen),
                    pid: pid,
                    handle: window.handle)
            }
        }
        return wanted.compactMap { found[$0.windowNumber] }
    }
}

/// Joins Accessibility windows with window server windows of the same application.
enum WindowMatching {
    /// For each Accessibility window, the number of the window server window it is.
    ///
    /// 1. A window with a number is that window, if the application has such a window on screen;
    ///    otherwise it is not on screen (minimized, in another Space) and gets `nil`.
    /// 2. A window without a number is matched to a window on screen that no other window claimed
    ///    and whose frame equals its own within one point, in the order of `onScreen`.
    ///
    /// A window on screen is claimed at most once.
    ///
    /// - Parameters:
    ///   - accessible: The Accessibility windows: the number if known, and the frame.
    ///   - onScreen: The window server windows of the same application, front to back.
    static func numbers(
        of accessible: [(number: WindowID?, frame: CGRect)],
        among onScreen: [OnScreenWindow]
    ) -> [WindowID?] {
        var result = [WindowID?](repeating: nil, count: accessible.count)
        var claimed: Set<Int> = []

        for (index, window) in accessible.enumerated() {
            guard let number = window.number,
                onScreen.contains(where: { $0.windowNumber == Int(number.rawValue) })
            else { continue }
            result[index] = number
            claimed.insert(Int(number.rawValue))
        }

        for (index, window) in accessible.enumerated() where window.number == nil {
            guard
                let match = onScreen.first(where: {
                    !claimed.contains($0.windowNumber) && sameFrame($0.frame, window.frame)
                }),
                let raw = UInt32(exactly: match.windowNumber)
            else { continue }
            result[index] = WindowID(rawValue: raw)
            claimed.insert(match.windowNumber)
        }
        return result
    }

    /// Whether two frames agree within one point, the accuracy of the frames the window server reports.
    private static func sameFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
    }
}

/// The identity of one window in the focus history.
enum WindowIdentity {
    /// The window number of `element`, a window of the process `pid`.
    ///
    /// The number comes from ``WindowNumber``. If the system gives none, the window is matched to a
    /// window of the same application on screen by its frame. `nil` when neither works.
    static func id(of element: AXUIElement, pid: pid_t) -> WindowID? {
        if let number = WindowNumber.of(element) { return number }

        guard let frame = try? AccessibilityWindow(element: element, whenGone: .windowGone).frame() else {
            return nil
        }
        let own = OnScreenWindows.list().filter { $0.pid == pid }
        return WindowMatching.numbers(of: [(number: nil, frame: frame)], among: own)[0]
    }
}
