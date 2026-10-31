import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// How the executor keeps the window records and uses them for cycling and Restore Window.
private enum RecordRig {
    static let display = Display(
        frame: CGRect(x: 200, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 200, y: 30, width: 1600, height: 970))
    static let start = CGRect(x: 300, y: 150, width: 600, height: 400)
    static let id = WindowID(rawValue: 42)

    static func window(id: WindowID? = RecordRig.id, at frame: CGRect = start) -> FakeWindow {
        let window = FakeWindow(frame: frame, displays: [display.frame])
        window.windowID = id
        return window
    }

    static func executor(
        _ window: FakeWindow, records: WindowRecordStore = WindowRecordStore()
    ) -> ActionExecutor {
        ActionExecutor(window: { window }, displays: { [display] }, records: records)
    }

    static func frame(_ preset: Preset, _ step: Int) -> CGRect {
        PresetCycle.frame(of: preset, step: step, in: display.visibleFrame)!
    }
}

@Suite("ActionExecutor: window records of single-window actions")
struct SingleActionRecordTests {
    @Test("a placement records the frame before as origin and the achieved frame, with the preset step")
    func recordsPlacement() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)

        _ = try executor.run(.placeWindow(.preset(.leftHalf)))

        let record = try #require(executor.records.record(for: RecordRig.id))
        #expect(record.origin == RecordRig.start)
        #expect(record.lastAchieved == RecordRig.frame(.leftHalf, 0))
        #expect(record.cycle == CycleStep(preset: .leftHalf, step: 0))
    }

    @Test("an action that is not a cycling preset records no step")
    func noStep() throws {
        let executor = RecordRig.executor(RecordRig.window())
        _ = try executor.run(.placeWindow(.preset(.maximize)))
        #expect(executor.records.record(for: RecordRig.id)?.cycle == nil)
    }

    @Test("a second action keeps the origin while the window is where the first left it")
    func keepsOrigin() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)

        _ = try executor.run(.placeWindow(.preset(.leftHalf)))
        _ = try executor.run(.placeWindow(.preset(.maximize)))

        let record = try #require(executor.records.record(for: RecordRig.id))
        #expect(record.origin == RecordRig.start)
        #expect(record.lastAchieved == (try window.frame()))
    }

    @Test("a window the user moved gets the frame it had as the new origin")
    func movedWindowNewOrigin() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)
        _ = try executor.run(.placeWindow(.preset(.leftHalf)))

        let moved = CGRect(x: 500, y: 200, width: 450, height: 350)
        try FrameSetter.apply(moved, to: window)
        _ = try executor.run(.placeWindow(.preset(.maximize)))

        #expect(executor.records.record(for: RecordRig.id)?.origin == moved)
    }

    @Test("pressing a half again takes the window through 1/2, 2/3 and 1/3 and back, and run and records agree")
    func cycles() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)

        for step in [0, 1, 2, 0] {
            _ = try executor.run(.placeWindow(.preset(.leftHalf)))
            #expect(try window.frame() == RecordRig.frame(.leftHalf, step))
            #expect(executor.records.record(for: RecordRig.id)?.cycle == CycleStep(preset: .leftHalf, step: step))
        }
        // The origin is still where the window started.
        #expect(executor.records.record(for: RecordRig.id)?.origin == RecordRig.start)
    }

    @Test("a window that refused the exact size still cycles, by its recorded achieved frame")
    func refusedSize() throws {
        let window = RecordRig.window()
        window.minimumSize = CGSize(width: 1000, height: 100)
        let executor = RecordRig.executor(window)

        _ = try executor.run(.placeWindow(.preset(.leftHalf)))
        let first = try window.frame()
        _ = try executor.run(.placeWindow(.preset(.leftHalf)))
        // Step 1 is 2/3 of 1600, which the window can take; step 0 was 800, which it refused (1000).
        #expect(first.width == 1000)
        #expect(try window.frame().width == RecordRig.frame(.leftHalf, 1).width)
    }

    @Test("a window that could not be changed is not recorded")
    func failedWindow() throws {
        let window = RecordRig.window()
        window.failPositionWith = .windowGone
        let executor = RecordRig.executor(window)

        #expect(throws: WindowError.windowGone) {
            try executor.run(.placeWindow(.preset(.leftHalf)))
        }
        #expect(executor.records.record(for: RecordRig.id) == nil)
    }

    @Test("a window without a number is not recorded and cycles by its frame alone")
    func noWindowID() throws {
        let window = RecordRig.window(id: nil)
        let executor = RecordRig.executor(window)

        _ = try executor.run(.placeWindow(.preset(.leftHalf)))
        _ = try executor.run(.placeWindow(.preset(.leftHalf)))

        #expect(try window.frame() == RecordRig.frame(.leftHalf, 1))
        #expect(executor.windowRecords.isEmpty)
        // Nor can it be restored.
        #expect(try executor.run(.restoreWindow) == .nothingToDo)
        #expect(try window.frame() == RecordRig.frame(.leftHalf, 1))
    }
}

@Suite("ActionExecutor: restoreWindow")
struct RestoreExecutionTests {
    @Test("it puts the window back at its origin and clears the record")
    func restores() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)
        _ = try executor.run(.placeWindow(.preset(.leftHalf)))
        _ = try executor.run(.placeWindow(.preset(.maximize)))

        let outcome = try executor.run(.restoreWindow)

        #expect(outcome == .placed(target: RecordRig.start, achieved: RecordRig.start))
        #expect(try window.frame() == RecordRig.start)
        #expect(executor.records.record(for: RecordRig.id) == nil)
        // One level only: a second restore has nothing to go back to.
        #expect(try executor.run(.restoreWindow) == .nothingToDo)
    }

    @Test("without a record there is nothing to do and the window stays")
    func noRecord() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)

        #expect(try executor.run(.restoreWindow) == .nothingToDo)
        #expect(try window.frame() == RecordRig.start)
    }

    @Test("a window the user moved has nothing to restore, and its record is dropped")
    func movedWindow() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)
        _ = try executor.run(.placeWindow(.preset(.leftHalf)))
        let moved = CGRect(x: 640, y: 120, width: 500, height: 500)
        try FrameSetter.apply(moved, to: window)

        #expect(try executor.run(.restoreWindow) == .nothingToDo)
        #expect(try window.frame() == moved)
        #expect(executor.records.record(for: RecordRig.id) == nil)
    }

    @Test("planning for restore only reads the store")
    func previewIsReadOnly() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)
        _ = try executor.run(.placeWindow(.preset(.leftHalf)))
        let before = executor.windowRecords.map(\.record)

        #expect(try executor.destinations(for: .restoreWindow) == [Destination(frame: RecordRig.start)])
        #expect(try executor.destinations(for: .placeWindow(.preset(.leftHalf)))
            == [Destination(frame: RecordRig.frame(.leftHalf, 1))])
        #expect(try executor.destinations(for: .placeWindow(.preset(.maximize))).count == 1)

        #expect(executor.windowRecords.map(\.record) == before)
        #expect(try window.frame() == RecordRig.frame(.leftHalf, 0))
    }

    @Test("planning with nothing to restore answers no destination and leaves a stale record")
    func previewOfNothing() throws {
        let window = RecordRig.window()
        let executor = RecordRig.executor(window)
        _ = try executor.run(.placeWindow(.preset(.leftHalf)))
        try FrameSetter.apply(CGRect(x: 640, y: 120, width: 500, height: 500), to: window)

        #expect(try executor.destinations(for: .restoreWindow).isEmpty)
        #expect(executor.records.record(for: RecordRig.id) != nil)
    }
}

@Suite("ActionExecutor: window records of arrangements and divider moves")
struct ArrangementRecordTests {
    @Test("an arrangement records every window of it with the frame it had before")
    func arrangement() throws {
        let desk = Desk()
        desk.openWindows(4)
        let before = try desk.frames(4)

        try desk.arrange(count: 4, rows: 2, columns: 2)

        let records = desk.executor.windowRecords
        #expect(records.map(\.window) == (1...4).map { DeskRig.id(UInt32($0)) })
        for (index, entry) in records.enumerated() {
            #expect(entry.record.origin == before[index], "window \(index + 1)")
            #expect(entry.record.lastAchieved == (try desk.frame(of: UInt32(index + 1))))
            #expect(entry.record.cycle == nil)
        }
    }

    @Test("a window of an arrangement that failed is not recorded")
    func failedWindow() throws {
        let desk = Desk()
        desk.openWindows(2)
        desk.window(2).fake.failPositionWith = .windowGone

        let outcome = try desk.arrange(count: 2, rows: 1, columns: 2)

        #expect(outcome.windows.contains { if case .failed = $0.result { true } else { false } })
        #expect(desk.executor.windowRecords.map(\.window) == [DeskRig.id(1)])
    }

    @Test("a divider move records only the windows whose cell changed, and keeps their origins")
    func dividerMove() throws {
        let desk = Desk()
        desk.openWindows(3)
        let before = try desk.frames(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        let arranged = Dictionary(
            uniqueKeysWithValues: desk.executor.windowRecords.map { ($0.window, $0.record) })

        _ = try desk.moved(.right)

        let after = Dictionary(
            uniqueKeysWithValues: desk.executor.windowRecords.map { ($0.window, $0.record) })
        for number in [UInt32(1), 2] {
            let id = DeskRig.id(number)
            #expect(after[id]?.origin == before[Int(number) - 1], "window \(number) keeps its origin")
            #expect(after[id]?.lastAchieved == (try desk.frame(of: number)))
            #expect(after[id]?.lastAchieved != arranged[id]?.lastAchieved, "window \(number) changed")
        }
        // The third window did not change cell, so its record is exactly what the arrangement made.
        #expect(after[DeskRig.id(3)] == arranged[DeskRig.id(3)])
    }

    @Test("planning a divider move, a swap and an arrangement leaves the records alone")
    func previewIsReadOnly() throws {
        let desk = Desk()
        desk.openWindows(3)
        try desk.arrange(count: 3, rows: 1, columns: 3)
        let records = desk.executor.windowRecords.map(\.record)

        _ = try desk.executor.destinations(for: .moveDivider(.right), settings: ActionSettings(resizeStep: 0.05))
        _ = try desk.executor.destinations(for: .swapWindow(.right))
        _ = try desk.executor.destinations(for: .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)))

        #expect(desk.executor.windowRecords.map(\.record) == records)
    }

    @Test("restoring a window of an arrangement puts it back where it was before the arrangement")
    func restoreAfterArrangement() throws {
        let desk = Desk()
        desk.openWindows(2)
        let before = try desk.frames(2)
        try desk.arrange(count: 2, rows: 1, columns: 2)

        _ = try desk.executor.run(.restoreWindow)

        #expect(try desk.frame(of: 1) == before[0])
        #expect(desk.executor.windowRecords.map(\.window) == [DeskRig.id(2)])
    }
}
