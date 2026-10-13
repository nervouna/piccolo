import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// `arrangeGrid` through the executor, against fake windows and displays: two displays, the secondary to
/// the left of the primary and smaller. Expected frames come from `TileLayout`, not from numbers written
/// down, so that the tests do not depend on how edges round.
private enum Rig {
    static let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 0, y: 30, width: 1550, height: 970))
    static let secondary = Display(
        frame: CGRect(x: -1200, y: 200, width: 1200, height: 800),
        visibleFrame: CGRect(x: -1200, y: 230, width: 1200, height: 770))
    static let both = [primary, secondary]

    static let grid2x2 = GridSpec(count: 4, rows: 2, columns: 2)

    /// A fake window number `number`, placed on `display`, offset by `number` points so that frames differ.
    static func window(
        _ number: UInt32, on display: Display = primary, isStandard: Bool = true,
        isMinimized: Bool = false, isFullScreen: Bool = false
    ) -> Entry {
        let frame = CGRect(
            x: display.visibleFrame.minX + 40 + CGFloat(number) * 10,
            y: display.visibleFrame.minY + 40 + CGFloat(number) * 10,
            width: 400, height: 300)
        let handle = FakeWindow(frame: frame, displays: both.map(\.frame))
        return Entry(
            id: WindowID(rawValue: number), start: frame, handle: handle,
            isStandard: isStandard, isMinimized: isMinimized, isFullScreen: isFullScreen)
    }

    static func id(_ number: UInt32) -> WindowID { WindowID(rawValue: number) }

    /// The cells of `count` windows in `grid` on `display`.
    static func cells(_ count: Int, _ grid: GridSpec = grid2x2, on display: Display = primary) -> [CGRect] {
        TileLayout.grid(windowCount: count, rows: grid.rows, columns: grid.columns)
            .frames(in: display.visibleFrame)
    }
}

/// A window of the rig: what the catalog lists, and the fake behind it.
private struct Entry {
    var id: WindowID
    var start: CGRect
    var handle: FakeWindow
    var isStandard: Bool
    var isMinimized: Bool
    var isFullScreen: Bool

    var catalogWindow: CatalogWindow {
        CatalogWindow(
            candidate: WindowCandidate(
                id: id, frame: start, isStandard: isStandard, isMinimized: isMinimized,
                isFullScreen: isFullScreen),
            pid: 100, handle: handle)
    }
}

/// The catalog of a rig, which the executor's sources hold on to. The handles are fakes that a test
/// uses from one thread only.
private struct Catalog: @unchecked Sendable {
    var windows: [CatalogWindow]

    init(_ entries: [Entry]) {
        windows = entries.map(\.catalogWindow)
    }

    func filtered(by onlyPid: pid_t?) -> [CatalogWindow] {
        windows.filter { onlyPid == nil || $0.pid == onlyPid }
    }
}

/// What the executor asked its sources.
private final class Asked: @unchecked Sendable {
    var onlyPids: [pid_t?] = []
    var catalogCalls: Int { onlyPids.count }
}

/// An executor over `entries` (front to back, as the catalog lists them).
///
/// - Parameters:
///   - focused: The entry that has the focus, if any. The executor reads its frame from the fake, and
///     the history is told it is the focused window.
///   - history: The windows in the order they were focused, most recent first.
private func executor(
    entries: [Entry],
    focused: Entry?,
    history: [UInt32],
    displays: [Display] = Rig.both,
    asked: Asked = Asked(),
    catalogError: (any Error)? = nil
) -> ActionExecutor {
    let focusHistory: FocusHistory = {
        var recorded = FocusHistory()
        for number in history.reversed() { recorded.recordFocus(Rig.id(number)) }
        return recorded
    }()
    let catalog = Catalog(entries)
    return ActionExecutor(
        window: {
            guard let focused else { throw WindowError.noFocusedWindow }
            return focused.handle
        },
        displays: { displays },
        arrangement: ArrangementSource(
            catalog: { onlyPid in
                asked.onlyPids.append(onlyPid)
                if let catalogError { throw catalogError }
                return catalog.filtered(by: onlyPid)
            },
            history: { focusHistory },
            focusedWindowID: { focused?.id }))
}

private func arranged(_ outcome: ActionOutcome) throws -> ArrangeOutcome {
    guard case .arranged(let result) = outcome else {
        throw ExecutorTestFailure("expected an arrangement, got \(outcome)")
    }
    return result
}

private struct ExecutorTestFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

@Suite("ActionExecutor: arrangeGrid")
struct ExecutorArrangeGridTests {
    @Test("four windows take the cells of a 2×2 grid, the most recently focused one the top-left")
    func fourWindows() throws {
        let entries = (1...4).map { Rig.window(UInt32($0)) }
        let run = executor(entries: entries, focused: entries[3], history: [4, 3, 2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        let cells = Rig.cells(4)
        #expect(outcome.displayIndex == 0)
        #expect(outcome.windows.map(\.window) == [4, 3, 2, 1].map(Rig.id))
        #expect(outcome.windows.map(\.target) == cells)
        #expect(outcome.windows.map(\.result) == cells.map { .placed(achieved: $0) })
        for (number, cell) in zip([4, 3, 2, 1], cells) {
            #expect(try entries[number - 1].handle.frame() == cell, "window \(number)")
        }
    }

    @Test("three windows: two on top and the third across the full width below")
    func threeWindows() throws {
        let entries = (1...3).map { Rig.window(UInt32($0)) }
        let run = executor(entries: entries, focused: entries[2], history: [3, 2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        let cells = Rig.cells(3)
        #expect(outcome.windows.map(\.target) == cells)
        #expect(cells[2].width == Rig.primary.visibleFrame.width)
        #expect(try entries[2].handle.frame() == cells[0])
        #expect(try entries[0].handle.frame() == cells[2])
    }

    @Test("with more windows than the grid holds, the most recently focused ones move and the others stay")
    func moreWindowsThanCells() throws {
        let entries = (1...6).map { Rig.window(UInt32($0)) }
        let run = executor(entries: entries, focused: entries[5], history: [6, 5, 4, 3, 2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.windows.map(\.window) == [6, 5, 4, 3].map(Rig.id))
        for number in [1, 2] {
            #expect(entries[number - 1].handle.calls.isEmpty, "window \(number) was touched")
            #expect(try entries[number - 1].handle.frame() == entries[number - 1].start)
        }
    }

    @Test("the order is the focus order, not the order in front of the screen")
    func focusOrderNotStackingOrder() throws {
        // Front to back: 1, 2, 3. Focused last to first: 1 was focused longest ago.
        let entries = (1...3).map { Rig.window(UInt32($0)) }
        let run = executor(entries: entries, focused: entries[2], history: [3, 2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(GridSpec(count: 3, rows: 1, columns: 3))))

        #expect(outcome.windows.map(\.window) == [3, 2, 1].map(Rig.id))
    }

    @Test("windows that were never focused follow the focused ones, in the order of the catalog")
    func unknownWindowsFollow() throws {
        let entries = (1...4).map { Rig.window(UInt32($0)) }
        let run = executor(entries: entries, focused: entries[2], history: [3])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.windows.map(\.window) == [3, 1, 2, 4].map(Rig.id))
    }

    @Test("the focused window counts as the most recently focused one even if the history has not caught up")
    func staleHistory() throws {
        let entries = (1...4).map { Rig.window(UInt32($0)) }
        // The tracker has not seen window 4 yet.
        let run = executor(entries: entries, focused: entries[3], history: [3, 2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.windows.map(\.window) == [4, 3, 2, 1].map(Rig.id))
    }

    @Test("minimized, full-screen and non-standard windows are not arranged")
    func ineligibleWindows() throws {
        let entries = [
            Rig.window(1), Rig.window(2, isMinimized: true), Rig.window(3, isFullScreen: true),
            Rig.window(4, isStandard: false), Rig.window(5),
        ]
        let run = executor(entries: entries, focused: entries[4], history: [5, 4, 3, 2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.windows.map(\.window) == [5, 1].map(Rig.id))
        for number in [2, 3, 4] {
            #expect(entries[number - 1].handle.calls.isEmpty, "window \(number) was touched")
        }
    }

    @Test("onlyPid is passed to the catalog and nothing else is arranged")
    func onlyPid() throws {
        let entries = (1...2).map { Rig.window(UInt32($0)) }
        let asked = Asked()
        let run = executor(entries: entries, focused: entries[1], history: [2, 1], asked: asked)

        _ = try run.run(.arrangeGrid(Rig.grid2x2), onlyPid: 100)
        #expect(asked.onlyPids == [100])

        // No window of this process: the catalog is empty and nothing moves.
        let outcome = try run.run(.arrangeGrid(Rig.grid2x2), onlyPid: 999)
        #expect(outcome == .nothingToDo)
        #expect(asked.onlyPids == [100, 999])
    }
}

@Suite("ActionExecutor: arrangeGrid display")
struct ExecutorArrangeDisplayTests {
    @Test("the display is the one containing the focused window; windows on the other display stay",
          arguments: [0, 1])
    func focusedWindowsDisplay(index: Int) throws {
        let focusedDisplay = Rig.both[index]
        let otherDisplay = Rig.both[1 - index]
        // The windows of the other display were focused most recently of all but one.
        let here = (1...2).map { Rig.window(UInt32($0), on: focusedDisplay) }
        let there = (3...4).map { Rig.window(UInt32($0), on: otherDisplay) }
        let entries = there + here
        let run = executor(entries: entries, focused: here[1], history: [2, 4, 3, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.displayIndex == index)
        #expect(outcome.windows.map(\.window) == [2, 1].map(Rig.id))
        #expect(outcome.windows.map(\.target) == Rig.cells(2, on: focusedDisplay))
        for window in there {
            #expect(window.handle.calls.isEmpty)
            #expect(try window.handle.frame() == window.start)
        }
    }

    @Test("without a focused window, the display is the one of the frontmost window of the catalog")
    func frontmostWindowsDisplay() throws {
        let front = Rig.window(1, on: Rig.secondary)
        let behind = Rig.window(2, on: Rig.primary)
        let run = executor(entries: [front, behind], focused: nil, history: [2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.displayIndex == 1)
        #expect(outcome.windows.map(\.window) == [1].map(Rig.id))
        #expect(behind.handle.calls.isEmpty)
    }

    @Test("without a focused window the focused window is not added to the history")
    func noFocusedWindowAddsNothing() throws {
        let entries = (1...2).map { Rig.window(UInt32($0)) }
        // The sources would name window 2 as focused, but there is no focused window to read.
        var recorded = FocusHistory()
        recorded.recordFocus(Rig.id(1))
        let history = recorded
        let catalog = Catalog(entries)
        let run = ActionExecutor(
            window: { throw WindowError.noFocusedWindow },
            displays: { Rig.both },
            arrangement: ArrangementSource(
                catalog: { _ in catalog.windows },
                history: { history },
                focusedWindowID: { Rig.id(2) }))

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.windows.map(\.window) == [1, 2].map(Rig.id))
    }

    @Test("a missing frontmost application is the same as a missing focused window")
    func noFrontmostApplication() throws {
        let entries = [Rig.window(1)]
        let catalog = Catalog(entries)
        let run = ActionExecutor(
            window: { throw WindowError.noFrontmostApplication },
            displays: { Rig.both },
            arrangement: ArrangementSource(
                catalog: { _ in catalog.windows },
                history: { FocusHistory() },
                focusedWindowID: { nil }))

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.windows.map(\.window) == [1].map(Rig.id))
    }
}

@Suite("ActionExecutor: arrangeGrid nothing to do")
struct ExecutorArrangeNothingToDoTests {
    @Test("no focused window and no candidates: nothing to do")
    func nothingAtAll() throws {
        let run = executor(entries: [], focused: nil, history: [])

        #expect(try run.run(.arrangeGrid(Rig.grid2x2)) == .nothingToDo)
    }

    @Test("a focused window but no candidates: nothing to do")
    func noCandidates() throws {
        let focused = Rig.window(1)
        let run = executor(entries: [], focused: focused, history: [1])

        #expect(try run.run(.arrangeGrid(Rig.grid2x2)) == .nothingToDo)
        #expect(focused.handle.calls.isEmpty)
    }

    @Test("candidates only on another display than the focused window: nothing to do")
    func candidatesElsewhere() throws {
        let focused = Rig.window(1, on: Rig.primary)
        let elsewhere = Rig.window(2, on: Rig.secondary)
        let run = executor(entries: [elsewhere], focused: focused, history: [2, 1])

        #expect(try run.run(.arrangeGrid(Rig.grid2x2)) == .nothingToDo)
        #expect(elsewhere.handle.calls.isEmpty)
    }

    @Test("only ineligible windows: nothing to do")
    func onlyIneligible() throws {
        let entries = [Rig.window(1, isMinimized: true), Rig.window(2, isFullScreen: true)]
        let run = executor(entries: entries, focused: entries[0], history: [2, 1])

        #expect(try run.run(.arrangeGrid(Rig.grid2x2)) == .nothingToDo)
        #expect(entries.allSatisfy { $0.handle.calls.isEmpty })
    }

    @Test("the default executor has no windows and so nothing to do")
    func noSource() throws {
        let window = Rig.window(1)
        let run = ActionExecutor(window: { window.handle }, displays: { Rig.both })

        #expect(try run.run(.arrangeGrid(Rig.grid2x2)) == .nothingToDo)
        #expect(window.handle.calls.isEmpty)
    }

    @Test("an invalid grid is refused even when there is nothing to arrange")
    func invalidGridWithoutWindows() {
        let run = executor(entries: [], focused: nil, history: [])

        #expect(
            throws: ArrangePlannerError.invalidGrid(
                .outOfRange(field: "count", rule: "must be <= rows * columns"))
        ) {
            try run.run(.arrangeGrid(GridSpec(count: 5, rows: 2, columns: 2)))
        }
    }
}

@Suite("ActionExecutor: arrangeGrid failures")
struct ExecutorArrangeFailureTests {
    @Test("a window that fails is reported, and the others are still arranged")
    func oneWindowFails() throws {
        let entries = (1...4).map { Rig.window(UInt32($0)) }
        // Window 3 was closed after it was listed.
        entries[2].handle.failPositionWith = .windowGone
        let run = executor(entries: entries, focused: entries[3], history: [4, 3, 2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        let cells = Rig.cells(4)
        #expect(outcome.windows.map(\.window) == [4, 3, 2, 1].map(Rig.id))
        #expect(outcome.windows[0].result == .placed(achieved: cells[0]))
        #expect(outcome.windows[1].result == .failed(message: "the window no longer exists"))
        #expect(outcome.windows[1].target == cells[1])
        #expect(outcome.windows[2].result == .placed(achieved: cells[2]))
        #expect(outcome.windows[3].result == .placed(achieved: cells[3]))
        #expect(try entries[1].handle.frame() == cells[2])
        #expect(try entries[0].handle.frame() == cells[3])
    }

    @Test("a window that cannot be read is reported with the error's message")
    func unreadableWindow() throws {
        let entries = (1...2).map { Rig.window(UInt32($0)) }
        entries[0].handle.failFrameWith = .accessibility(operation: "read AXPosition", code: -25204)
        let run = executor(entries: entries, focused: entries[1], history: [2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        #expect(outcome.windows[0].result == .placed(achieved: Rig.cells(2)[0]))
        guard case .failed(let message) = outcome.windows[1].result else {
            Issue.record("expected the second window to fail, got \(outcome.windows[1].result)")
            return
        }
        #expect(message.contains("AXPosition"))
    }

    @Test("a window that refuses the size is reported with the frame it achieved")
    func refusesTheSize() throws {
        let entries = (1...4).map { Rig.window(UInt32($0)) }
        let cells = Rig.cells(4)
        // Window 3 takes the top-right cell, which is 775 wide; it needs at least 900.
        entries[2].handle.minimumSize = CGSize(width: 900, height: cells[1].height)
        let run = executor(entries: entries, focused: entries[3], history: [4, 3, 2, 1])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        guard case .placed(let achieved) = outcome.windows[1].result else {
            Issue.record("expected window 3 to be placed, got \(outcome.windows[1].result)")
            return
        }
        #expect(outcome.windows[1].target == cells[1])
        #expect(achieved.width == 900)
        // Pushed back inside the display, flush with its right edge.
        #expect(achieved.maxX == Rig.primary.visibleFrame.maxX)
        #expect(try entries[2].handle.frame() == achieved)
        // The others are on their cells.
        #expect(try entries[3].handle.frame() == cells[0])
        #expect(try entries[1].handle.frame() == cells[2])
        #expect(try entries[0].handle.frame() == cells[3])
    }

    @Test("a fixed-size window is moved to its cell's origin and keeps its size")
    func fixedSize() throws {
        let entries = (1...2).map { Rig.window(UInt32($0)) }
        entries[1].handle.isFixedSize = true
        let run = executor(entries: entries, focused: entries[0], history: [1, 2])

        let outcome = try arranged(try run.run(.arrangeGrid(Rig.grid2x2)))

        let cells = Rig.cells(2)
        #expect(outcome.windows[1].target == cells[1])
        #expect(outcome.windows[1].result == .placed(achieved: CGRect(origin: cells[1].origin, size: entries[1].start.size)))
    }

    @Test("a grid whose cells would be too small is refused and nothing moves")
    func cellTooSmall() {
        // Twelve rows in a 970 pt high display are 80 pt each.
        let entries = (1...12).map { Rig.window(UInt32($0)) }
        let run = executor(entries: entries, focused: entries[11], history: (1...12).reversed().map { UInt32($0) })

        #expect(throws: ArrangePlannerError.cellTooSmall) {
            try run.run(.arrangeGrid(GridSpec(count: 12, rows: 12, columns: 1)))
        }
        #expect(entries.allSatisfy { $0.handle.calls.isEmpty })
    }

    @Test("an invalid grid is refused and nothing moves")
    func invalidGrid() {
        let entries = (1...4).map { Rig.window(UInt32($0)) }
        let run = executor(entries: entries, focused: entries[3], history: [4, 3, 2, 1])

        #expect(throws: ArrangePlannerError.self) {
            try run.run(.arrangeGrid(GridSpec(count: 0, rows: 2, columns: 2)))
        }
        #expect(entries.allSatisfy { $0.handle.calls.isEmpty })
    }

    @Test("a catalog that cannot be read is passed through")
    func catalogFails() {
        let entries = [Rig.window(1)]
        let run = executor(
            entries: entries, focused: entries[0], history: [1], catalogError: WindowError.notTrusted)

        #expect(throws: WindowError.notTrusted) {
            try run.run(.arrangeGrid(Rig.grid2x2))
        }
        #expect(entries[0].handle.calls.isEmpty)
    }

    @Test("a focused window that cannot be reached for another reason is passed through")
    func focusedWindowFails() {
        let entries = [Rig.window(1)]
        let catalog = Catalog(entries)
        let run = ActionExecutor(
            window: { throw WindowError.notTrusted },
            displays: { Rig.both },
            arrangement: ArrangementSource(
                catalog: { _ in catalog.windows },
                history: { FocusHistory() },
                focusedWindowID: { nil }))

        #expect(throws: WindowError.notTrusted) {
            try run.run(.arrangeGrid(Rig.grid2x2))
        }
        #expect(entries[0].handle.calls.isEmpty)
    }

    @Test("no displays is a planning error")
    func noDisplays() {
        let entries = [Rig.window(1)]
        let run = executor(entries: entries, focused: entries[0], history: [1], displays: [])

        #expect(throws: ActionPlanningError.noDisplays) {
            try run.run(.arrangeGrid(Rig.grid2x2))
        }
    }

    @Test("every error of the planner has a message for the control channel")
    func plannerErrorMessages() {
        let errors: [ArrangePlannerError] = [
            .displayIndexOutOfRange, .invalidGrid(.outOfRange(field: "rows", rule: "must be >= 1")),
            .cellTooSmall,
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false, "\(error) has no description")
        }
        #expect(
            ArrangePlannerError.invalidGrid(.outOfRange(field: "rows", rule: "must be >= 1"))
                .errorDescription?.contains("rows") == true)
    }
}

@Suite("ActionExecutor: focus history")
struct ExecutorFocusHistoryTests {
    @Test("the history is the one of the source, most recent first")
    func focusHistory() {
        let entries = (1...3).map { Rig.window(UInt32($0)) }
        let run = executor(entries: entries, focused: entries[2], history: [3, 1, 2])

        #expect(run.focusHistory == [3, 1, 2].map(Rig.id))
    }

    @Test("the default executor has no history")
    func noHistory() {
        let run = ActionExecutor(window: { Rig.window(1).handle }, displays: { Rig.both })

        #expect(run.focusHistory.isEmpty)
    }
}
