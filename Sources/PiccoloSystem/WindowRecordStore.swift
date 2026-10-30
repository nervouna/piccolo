import CoreGraphics
import Foundation
import PiccoloCore

/// The windows Piccolo has moved, with where each came from and where it left it, shared by the
/// threads that run actions (see ``PiccoloCore/WindowRecords`` for the rules).
///
/// A thin lock around `WindowRecords`. In memory only: the records are gone when Piccolo quits.
/// Planning only reads it; a run writes it after it has changed a window.
public final class WindowRecordStore: @unchecked Sendable {
    private let lock = NSLock()
    private var records = WindowRecords()

    public init() {}

    /// Every record, ordered by window number.
    public var entries: [(window: WindowID, record: WindowRecord)] {
        locked { $0.entries }
    }

    /// The record of `window`, if Piccolo holds one.
    public func record(for window: WindowID) -> WindowRecord? {
        locked { $0[window] }
    }

    /// See ``PiccoloCore/WindowRecords/recordChange(of:from:to:cycle:)``.
    func recordChange(of window: WindowID, from before: CGRect, to achieved: CGRect, cycle: CycleStep? = nil) {
        locked { $0.recordChange(of: window, from: before, to: achieved, cycle: cycle) }
    }

    /// Forgets `window`.
    func clear(_ window: WindowID) {
        locked { $0.clear(window) }
    }

    private func locked<Result>(_ body: (inout WindowRecords) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&records)
    }
}
