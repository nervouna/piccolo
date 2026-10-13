import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// Joining the window server's windows with Accessibility's, without any real window.
@Suite("WindowCatalog")
struct WindowCatalogTests {
    private static let ownPid: pid_t = 50

    private func onScreen(_ number: Int, pid: pid_t, _ frame: CGRect = CGRect(x: 0, y: 30, width: 400, height: 300))
        -> OnScreenWindow
    {
        OnScreenWindow(windowNumber: number, pid: pid, ownerName: "App \(pid)", frame: frame)
    }

    private func accessible(
        _ number: UInt32?, _ frame: CGRect = CGRect(x: 0, y: 30, width: 400, height: 300),
        isStandard: Bool = true, isMinimized: Bool = false, isFullScreen: Bool = false,
        handle: FakeWindow? = nil
    ) -> AccessibleWindow {
        AccessibleWindow(
            number: number.map { WindowID(rawValue: $0) }, frame: frame, isStandard: isStandard,
            isMinimized: isMinimized, isFullScreen: isFullScreen,
            handle: handle ?? FakeWindow(frame: frame, displays: [CGRect(x: 0, y: 0, width: 2000, height: 1200)]))
    }

    /// The catalog of `windows` with `byPid` as what Accessibility knows. Records the pids asked.
    private func catalog(
        _ windows: [OnScreenWindow], ownPid: pid_t = ownPid, onlyPid: pid_t? = nil,
        byPid: [pid_t: [AccessibleWindow]], asked: Asked = Asked()
    ) -> [CatalogWindow] {
        WindowCatalog.windows(onScreen: windows, ownPid: ownPid, onlyPid: onlyPid) { pid in
            asked.pids.append(pid)
            return byPid[pid]
        }
    }

    private final class Asked {
        var pids: [pid_t] = []
    }

    // MARK: Order and identity

    @Test("windows come in the order of the window server, whatever the order Accessibility lists them in")
    func frontToBack() {
        let windows = [onScreen(30, pid: 1), onScreen(20, pid: 2), onScreen(10, pid: 1)]
        let result = catalog(
            windows, byPid: [1: [accessible(10), accessible(30)], 2: [accessible(20)]])

        #expect(result.map(\.candidate.id) == [30, 20, 10].map { WindowID(rawValue: $0) })
        #expect(result.map(\.pid) == [1, 2, 1])
    }

    @Test("each application is asked once, in the order of its frontmost window")
    func askedOnce() {
        let asked = Asked()
        let windows = [onScreen(3, pid: 2), onScreen(2, pid: 1), onScreen(1, pid: 2)]

        _ = catalog(windows, byPid: [1: [accessible(2)], 2: [accessible(3), accessible(1)]], asked: asked)

        #expect(asked.pids == [2, 1])
    }

    @Test("kind, state and frame come from Accessibility")
    func attributes() {
        let frame = CGRect(x: 10, y: 40, width: 500, height: 350)
        let windows = [onScreen(1, pid: 1), onScreen(2, pid: 1), onScreen(3, pid: 1)]
        let result = catalog(
            windows,
            byPid: [
                1: [
                    accessible(1, frame),
                    accessible(2, isStandard: false),
                    accessible(3, isMinimized: true, isFullScreen: true),
                ]
            ])

        #expect(result[0].candidate == WindowCandidate(
            id: WindowID(rawValue: 1), frame: frame, isStandard: true, isMinimized: false,
            isFullScreen: false))
        #expect(result[1].candidate.isStandard == false)
        #expect(result[2].candidate.isMinimized && result[2].candidate.isFullScreen)
    }

    @Test("the handle is the one Accessibility gave")
    func handle() throws {
        let fake = FakeWindow(frame: CGRect(x: 0, y: 30, width: 400, height: 300), displays: [])
        let result = catalog([onScreen(1, pid: 1)], byPid: [1: [accessible(1, handle: fake)]])

        try result[0].handle.setPosition(CGPoint(x: 70, y: 80))

        #expect(fake.origin == CGPoint(x: 70, y: 80))
    }

    // MARK: What is left out

    @Test("Piccolo's own windows are never listed, and its Accessibility is not even asked")
    func ownWindows() {
        let asked = Asked()
        let windows = [onScreen(1, pid: Self.ownPid), onScreen(2, pid: 1)]

        let result = catalog(
            windows, byPid: [Self.ownPid: [accessible(1)], 1: [accessible(2)]], asked: asked)

        #expect(result.map(\.candidate.id) == [WindowID(rawValue: 2)])
        #expect(asked.pids == [1])
    }

    @Test("with onlyPid, only that process is asked and listed")
    func onlyPid() {
        let asked = Asked()
        let windows = [onScreen(1, pid: 1), onScreen(2, pid: 2), onScreen(3, pid: 2)]

        let result = catalog(
            windows, onlyPid: 2, byPid: [1: [accessible(1)], 2: [accessible(2), accessible(3)]],
            asked: asked)

        #expect(result.map(\.candidate.id) == [2, 3].map { WindowID(rawValue: $0) })
        #expect(asked.pids == [2])
    }

    @Test("onlyPid naming Piccolo itself lists nothing")
    func onlyOwnPid() {
        let result = catalog(
            [onScreen(1, pid: Self.ownPid)], onlyPid: Self.ownPid, byPid: [Self.ownPid: [accessible(1)]])

        #expect(result.isEmpty)
    }

    @Test("an application that does not answer is skipped, and the others are still listed")
    func unresponsiveApplication() {
        let windows = [onScreen(1, pid: 1), onScreen(2, pid: 2), onScreen(3, pid: 3)]

        let result = catalog(windows, byPid: [1: [accessible(1)], 3: [accessible(3)]])

        #expect(result.map(\.candidate.id) == [1, 3].map { WindowID(rawValue: $0) })
    }

    @Test("a window Accessibility does not know cannot be moved, so it is left out")
    func unknownToAccessibility() {
        let windows = [onScreen(1, pid: 1), onScreen(2, pid: 1)]

        let result = catalog(windows, byPid: [1: [accessible(2)]])

        #expect(result.map(\.candidate.id) == [WindowID(rawValue: 2)])
    }

    @Test("a window that is not on screen (minimized, in another Space) is left out")
    func notOnScreen() {
        let windows = [onScreen(1, pid: 1)]

        let result = catalog(windows, byPid: [1: [accessible(1), accessible(7, isMinimized: true)]])

        #expect(result.map(\.candidate.id) == [WindowID(rawValue: 1)])
    }

    @Test("with no window on screen there is nothing to ask")
    func empty() {
        let asked = Asked()

        #expect(catalog([], byPid: [:], asked: asked).isEmpty)
        #expect(asked.pids.isEmpty)
    }

    // MARK: The fallback by application and frame

    @Test("a window without a number is matched to the window on screen with the same frame")
    func fallbackByFrame() {
        let first = CGRect(x: 0, y: 30, width: 400, height: 300)
        let second = CGRect(x: 100, y: 130, width: 500, height: 400)
        let windows = [onScreen(8, pid: 1, first), onScreen(5, pid: 1, second)]

        let result = catalog(windows, byPid: [1: [accessible(nil, second), accessible(nil, first)]])

        #expect(result.map(\.candidate.id) == [8, 5].map { WindowID(rawValue: $0) })
        #expect(result.map(\.candidate.frame) == [first, second])
    }

    @Test("the fallback tolerates one point and no more")
    func fallbackTolerance() {
        let frame = CGRect(x: 0, y: 30, width: 400, height: 300)
        let windows = [onScreen(1, pid: 1, frame)]

        let near = catalog(windows, byPid: [1: [accessible(nil, frame.offsetBy(dx: 0.9, dy: -1))]])
        let far = catalog(windows, byPid: [1: [accessible(nil, frame.offsetBy(dx: 1.5, dy: 0))]])

        #expect(near.count == 1)
        #expect(far.isEmpty)
    }

    @Test("the fallback only looks at windows of the same application")
    func fallbackSameApplication() {
        let frame = CGRect(x: 0, y: 30, width: 400, height: 300)
        let windows = [onScreen(1, pid: 2, frame), onScreen(2, pid: 1, frame)]

        let result = catalog(windows, byPid: [1: [accessible(nil, frame)], 2: []])

        #expect(result.map(\.candidate.id) == [WindowID(rawValue: 2)])
    }

    @Test("windows with the same frame and no number get different windows, in the order of the window server")
    func fallbackDuplicateFrames() {
        let frame = CGRect(x: 0, y: 30, width: 400, height: 300)
        let windows = [onScreen(9, pid: 1, frame), onScreen(4, pid: 1, frame)]
        let handles = [FakeWindow(frame: frame, displays: []), FakeWindow(frame: frame, displays: [])]

        let result = catalog(
            windows,
            byPid: [1: [accessible(nil, frame, handle: handles[0]), accessible(nil, frame, handle: handles[1])]])

        #expect(result.map(\.candidate.id) == [9, 4].map { WindowID(rawValue: $0) })
        #expect(result[0].handle as? FakeWindow === handles[0])
        #expect(result[1].handle as? FakeWindow === handles[1])
    }

    @Test("a window claimed by its number is not taken by the fallback")
    func numberBeforeFallback() {
        let frame = CGRect(x: 0, y: 30, width: 400, height: 300)
        let windows = [onScreen(1, pid: 1, frame), onScreen(2, pid: 1, frame)]

        // Listed first, but without a number: it must not take window 1, which the other one has.
        let result = catalog(windows, byPid: [1: [accessible(nil, frame), accessible(1, frame)]])

        #expect(result.map(\.candidate.id) == [1, 2].map { WindowID(rawValue: $0) })
    }

    @Test("a window with a number that is not on screen does not fall back to another window")
    func numberedNotOnScreenDoesNotFallBack() {
        let frame = CGRect(x: 0, y: 30, width: 400, height: 300)
        let windows = [onScreen(1, pid: 1, frame)]

        let result = catalog(windows, byPid: [1: [accessible(99, frame)]])

        #expect(result.isEmpty)
    }
}
