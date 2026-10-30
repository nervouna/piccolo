import CoreGraphics
import Testing

@testable import PiccoloCore

@Suite("WindowRecords: the update rules")
struct WindowRecordsTests {
    private let window = WindowID(rawValue: 7)
    private let start = CGRect(x: 100, y: 100, width: 600, height: 400)
    private let half = CGRect(x: 0, y: 0, width: 800, height: 900)
    private let full = CGRect(x: 0, y: 0, width: 1600, height: 900)

    @Test("a window without a record gets its frame before the change as origin")
    func firstChange() {
        var records = WindowRecords()
        records.recordChange(of: window, from: start, to: half)
        #expect(records[window] == WindowRecord(origin: start, lastAchieved: half))
    }

    @Test("a window still at its last achieved frame keeps its origin")
    func keepsOrigin() {
        var records = WindowRecords()
        records.recordChange(of: window, from: start, to: half)
        records.recordChange(of: window, from: half.insetBy(dx: 1, dy: 1), to: full)
        #expect(records[window] == WindowRecord(origin: start, lastAchieved: full))
    }

    @Test("a window the user moved since takes its frame before the change as the new origin")
    func movedWindow() {
        var records = WindowRecords()
        records.recordChange(of: window, from: start, to: half)
        let userFrame = CGRect(x: 300, y: 50, width: 500, height: 500)
        records.recordChange(of: window, from: userFrame, to: full)
        #expect(records[window] == WindowRecord(origin: userFrame, lastAchieved: full))
    }

    @Test("the cycle step is replaced by every change and is none for an ordinary one")
    func cycle() {
        var records = WindowRecords()
        records.recordChange(
            of: window, from: start, to: half, cycle: CycleStep(preset: .leftHalf, step: 0))
        #expect(records[window]?.cycle == CycleStep(preset: .leftHalf, step: 0))
        records.recordChange(of: window, from: half, to: full)
        #expect(records[window]?.cycle == nil)
    }

    @Test("clearing forgets the window and only that one")
    func clear() {
        var records = WindowRecords()
        records.recordChange(of: window, from: start, to: half)
        records.recordChange(of: WindowID(rawValue: 3), from: start, to: full)
        records.clear(window)
        #expect(records[window] == nil)
        #expect(records.entries.map(\.window) == [WindowID(rawValue: 3)])
    }
}
