import CoreGraphics
import Foundation

import PiccoloCore

@testable import PiccoloSystem

/// What the linked resize tests share: a desk of fake windows on fake displays, an executor over it,
/// and the record of every call a window received.
enum DeskRig {
    static let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1200, height: 840),
        visibleFrame: CGRect(x: 0, y: 40, width: 1200, height: 800))
    static let secondary = Display(
        frame: CGRect(x: -1000, y: 100, width: 1000, height: 700),
        visibleFrame: CGRect(x: -1000, y: 140, width: 1000, height: 660))

    /// The step the tests move a divider by: 5%, which is 60 points of the primary display's width
    /// and 40 points of its height.
    static let step = 0.05

    static func id(_ number: UInt32) -> WindowID { WindowID(rawValue: number) }
}

struct DeskFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// A window of the desk: a `FakeWindow` that logs what the executor does to it, and lets the desk
/// look for overlaps whenever the executor goes on to another window.
final class DeskWindow: WindowFrameAccess, @unchecked Sendable {
    let number: UInt32
    let pid: pid_t
    let fake: FakeWindow
    var isClosed = false
    private let desk: Desk

    var windowID: WindowID? { DeskRig.id(number) }

    fileprivate init(number: UInt32, pid: pid_t, fake: FakeWindow, desk: Desk) {
        self.number = number
        self.pid = pid
        self.fake = fake
        self.desk = desk
    }

    func frame() throws -> CGRect {
        if isClosed { throw WindowError.windowGone }
        return try fake.frame()
    }

    func setSize(_ size: CGSize) throws {
        if isClosed { throw WindowError.windowGone }
        desk.willChange(window: number, with: "size")
        try fake.setSize(size)
        desk.didChange(window: number, kind: .size, frame: fake.frameValue)
    }

    func setPosition(_ origin: CGPoint) throws {
        if isClosed { throw WindowError.windowGone }
        desk.willChange(window: number, with: "position")
        try fake.setPosition(origin)
        desk.didChange(window: number, kind: .position, frame: fake.frameValue)
    }
}

/// Fake windows on fake displays. Window `n` is listed on screen unless it was closed; the focused
/// window and the order of focus are set by the test. Tests use it from one thread only.
final class Desk: @unchecked Sendable {
    let displays: [Display]
    private(set) var windows: [UInt32: DeskWindow] = [:]
    /// The windows on screen, front to back.
    private(set) var order: [UInt32] = []
    var focused: UInt32?
    /// The windows in the order they were focused, most recent first.
    var focusOrder: [UInt32] = []
    var catalogError: (any Error)?

    /// Every size and position change the windows received, as "<number> size" or "<number> position".
    var log: [String] = []
    /// One change a window took: which window, what changed, the frame after it and the time on `clock`.
    struct Change: Equatable {
        enum Kind { case size, position }
        var window: UInt32
        var kind: Kind
        var frame: CGRect
        var time: TimeInterval
    }

    /// Every size and position change the windows took (those that threw are not in it), in order.
    private(set) var trace: [Change] = []
    /// The clock the changes are timed on; without one their time is 0.
    var clock: FakeClock?

    /// The `onlyPid` of each request for the windows on screen.
    private(set) var catalogRequests: [pid_t?] = []
    private var overlapsFound: [String] = []
    private var isWatching = false
    private var lastChanged: UInt32?

    let store = LayoutGroupStore()
    let records = WindowRecordStore()

    init(displays: [Display] = [DeskRig.primary]) {
        self.displays = displays
    }

    /// Opens window `number` on a display, at a cascade position or at `frame`, and makes it the
    /// most recently focused one.
    @discardableResult
    func open(
        _ number: UInt32, on displayIndex: Int = 0, at frame: CGRect? = nil, pid: pid_t = 100,
        minimum: CGSize? = nil
    ) -> DeskWindow {
        let visible = displays[displayIndex].visibleFrame
        let start = frame
            ?? CGRect(
                x: visible.minX + 20 + CGFloat(number) * 25, y: visible.minY + 20 + CGFloat(number) * 20,
                width: 400, height: 300)
        let fake = FakeWindow(frame: start, displays: displays.map(\.frame))
        if let minimum { fake.minimumSize = minimum }
        let window = DeskWindow(number: number, pid: pid, fake: fake, desk: self)
        windows[number] = window
        order.append(number)
        return window
    }

    /// Opens windows 1 through `count` on the first display. Window 1 has the focus and is the
    /// most recently focused, so that a grid puts window `n` in cell `n - 1`.
    @discardableResult
    func openWindows(_ count: Int) -> [DeskWindow] {
        let opened = (1...count).map { open(UInt32($0)) }
        focused = 1
        focusOrder = (1...count).map { UInt32($0) }
        return opened
    }

    func window(_ number: UInt32) -> DeskWindow { windows[number]! }

    func frame(of number: UInt32) throws -> CGRect { try window(number).frame() }

    /// The frames of windows 1 through `count`.
    func frames(_ count: Int) throws -> [CGRect] {
        try (1...count).map { try frame(of: UInt32($0)) }
    }

    /// Closes the window: it is no longer on screen, and its handle is stale.
    func close(_ number: UInt32) {
        window(number).isClosed = true
        order.removeAll { $0 == number }
    }

    /// Calls the windows received since `mark`.
    func calls(since mark: Int) -> [String] { Array(log[mark...]) }

    // MARK: Executor

    lazy var executor = ActionExecutor(
        window: { [self] in
            guard let focused, let window = windows[focused], !window.isClosed else {
                throw WindowError.noFocusedWindow
            }
            return window
        },
        displays: { [self] in displays },
        arrangement: ArrangementSource(
            catalog: { [self] onlyPid in
                catalogRequests.append(onlyPid)
                if let catalogError { throw catalogError }
                return try order.compactMap { number -> CatalogWindow? in
                    let window = windows[number]!
                    guard onlyPid == nil || window.pid == onlyPid else { return nil }
                    return CatalogWindow(
                        candidate: WindowCandidate(
                            id: DeskRig.id(number), frame: try window.frame(), isStandard: true,
                            isMinimized: false, isFullScreen: false),
                        pid: window.pid, handle: window)
                }
            },
            history: { [self] in
                var history = FocusHistory()
                for number in focusOrder.reversed() { history.recordFocus(DeskRig.id(number)) }
                return history
            },
            focusedWindowID: { [self] in focused.map(DeskRig.id) }),
        groups: store, records: records)

    /// Arranges the most recently focused windows.
    @discardableResult
    func arrange(count: Int, rows: Int, columns: Int, onlyPid: pid_t? = nil) throws -> ArrangeOutcome {
        let outcome = try executor.run(
            .arrangeGrid(GridSpec(count: count, rows: rows, columns: columns)), onlyPid: onlyPid, settings: .pinned())
        guard case .arranged(let arranged) = outcome else {
            throw DeskFailure("expected an arrangement, got \(outcome)")
        }
        return arranged
    }

    /// Presses a divider key with `step` as the resize step.
    func move(
        _ direction: Direction, step: Double = DeskRig.step, onlyPid: pid_t? = nil
    ) throws -> DividerMoveOutcome {
        let outcome = try executor.run(.moveDivider(direction), onlyPid: onlyPid, settings: ActionSettings.pinned(resizeStep: step))
        guard case .dividerMove(let result) = outcome else {
            throw DeskFailure("expected a divider move, got \(outcome)")
        }
        return result
    }

    /// Presses a divider key and expects the divider to have moved.
    func moved(
        _ direction: Direction, step: Double = DeskRig.step, onlyPid: pid_t? = nil
    ) throws -> DividerMoved {
        let outcome = try move(direction, step: step, onlyPid: onlyPid)
        guard case .moved(let moved) = outcome else {
            throw DeskFailure("expected the divider to move, got \(outcome)")
        }
        return moved
    }

    /// Presses a swap key. `settings` carries the gap and the animation; the defaults have neither.
    func swap(
        _ direction: Direction, settings: ActionSettings = .pinned(), onlyPid: pid_t? = nil
    ) throws -> SwapOutcome {
        let outcome = try executor.run(.swapWindow(direction), onlyPid: onlyPid, settings: settings)
        guard case .swap(let result) = outcome else {
            throw DeskFailure("expected a swap, got \(outcome)")
        }
        return result
    }

    /// Presses a swap key and expects the windows to have traded cells.
    ///
    /// - Returns: the display and every window of the group in cell order, after the swap.
    @discardableResult
    func swapped(
        _ direction: Direction, settings: ActionSettings = .pinned(), onlyPid: pid_t? = nil
    ) throws -> (display: Int, windows: [ArrangedWindow]) {
        let outcome = try swap(direction, settings: settings, onlyPid: onlyPid)
        guard case .swapped(let display, let windows) = outcome else {
            throw DeskFailure("expected the windows to swap, got \(outcome)")
        }
        return (display, windows)
    }

    // MARK: Overlaps

    /// From now on, the windows are checked for overlaps each time the executor goes on from one
    /// window to the next one, and at the end (see ``overlaps``).
    ///
    /// Within the calls for one window (size, position, size) it may overlap its neighbour for an
    /// instant: a window that grows towards the left or the top takes its new size before its new
    /// position, which is how ``FrameSetter/apply(_:to:within:)`` works. What the order of the
    /// windows guarantees, and this checks, is that the space a window grows into was freed before.
    func startWatchingOverlaps() {
        isWatching = true
        overlapsFound = []
        lastChanged = nil
    }

    /// The overlaps seen since `startWatchingOverlaps()`, including the state now.
    var overlaps: [String] {
        checkOverlaps(label: "at the end")
        return overlapsFound
    }

    fileprivate func didChange(window number: UInt32, kind: Change.Kind, frame: CGRect) {
        trace.append(Change(window: number, kind: kind, frame: frame, time: clock?.time ?? 0))
    }

    fileprivate func willChange(window number: UInt32, with operation: String) {
        log.append("\(number) \(operation)")
        if isWatching, let last = lastChanged, last != number {
            checkOverlaps(label: "when the move went on from window \(last) to window \(number)")
        }
        lastChanged = number
    }

    private func checkOverlaps(label: String) {
        guard isWatching else { return }
        let open = order.compactMap { windows[$0] }
        for (index, first) in open.enumerated() {
            for second in open[(index + 1)...] {
                let shared = first.fake.frameValue.intersection(second.fake.frameValue)
                if !shared.isNull, shared.width > 0.5, shared.height > 0.5 {
                    overlapsFound.append(
                        "\(label), windows \(first.number) and \(second.number) overlap by \(shared.width)×\(shared.height)"
                    )
                }
            }
        }
    }
}

extension FakeWindow {
    /// The frame without the failure injection of `frame()`.
    var frameValue: CGRect { CGRect(origin: origin, size: size) }
}
