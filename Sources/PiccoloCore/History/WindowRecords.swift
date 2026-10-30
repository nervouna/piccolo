import CoreGraphics

/// The preset and step Piccolo last placed a window at (see ``PresetCycle``).
public struct CycleStep: Equatable, Sendable {
    public var preset: Preset
    /// 0 for the preset's own frame, then 1 and 2.
    public var step: Int

    public init(preset: Preset, step: Int) {
        self.preset = preset
        self.step = step
    }
}

/// What Piccolo remembers of a window it moved.
public struct WindowRecord: Equatable, Sendable {
    /// The frame the window had before Piccolo moved it (the one Restore Window goes back to).
    public var origin: CGRect
    /// The frame it ended at after Piccolo's last change.
    public var lastAchieved: CGRect
    /// The preset and step of the last change, when it was a cycling preset.
    public var cycle: CycleStep?

    public init(origin: CGRect, lastAchieved: CGRect, cycle: CycleStep? = nil) {
        self.origin = origin
        self.lastAchieved = lastAchieved
        self.cycle = cycle
    }

    /// Whether a window at `frame` is still where Piccolo last left it.
    public func isInPlace(at frame: CGRect) -> Bool {
        FrameTolerance.matches(frame, lastAchieved)
    }
}

/// The records of the windows Piccolo moved: the rules of the store, without locks or windows.
public struct WindowRecords: Equatable, Sendable {
    private var records: [WindowID: WindowRecord] = [:]

    public init() {}

    /// Every record, ordered by window number.
    public var entries: [(window: WindowID, record: WindowRecord)] {
        records.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { window in
            records[window].map { (window, $0) }
        }
    }

    public subscript(window: WindowID) -> WindowRecord? {
        records[window]
    }

    /// Notes that an action changed `window` from `before` to `achieved`.
    ///
    /// When the window has no record, or is not at its record's `lastAchieved` (the user moved it
    /// since), `before` becomes the new origin. Otherwise the origin stays. `lastAchieved` and `cycle`
    /// are always replaced.
    public mutating func recordChange(
        of window: WindowID, from before: CGRect, to achieved: CGRect, cycle: CycleStep? = nil
    ) {
        var origin = before
        if let existing = records[window], existing.isInPlace(at: before) {
            origin = existing.origin
        }
        records[window] = WindowRecord(origin: origin, lastAchieved: achieved, cycle: cycle)
    }

    /// Forgets `window`.
    public mutating func clear(_ window: WindowID) {
        records[window] = nil
    }

    public static func == (lhs: WindowRecords, rhs: WindowRecords) -> Bool {
        lhs.records == rhs.records
    }
}
