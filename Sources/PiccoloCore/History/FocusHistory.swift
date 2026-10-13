/// The order in which windows were focused, most recent first, bounded by a capacity.
///
/// Each window appears at most once: recording a window moves it to the front. The history
/// does not observe focus or check that windows still exist. Callers report focus with
/// `recordFocus(_:)` and drop closed windows with `forget(_:)` or `prune(keeping:)`.
public struct FocusHistory: Equatable, Sendable {
    private let capacity: Int
    /// Most recent first. Holds no duplicates and never more than `capacity` entries.
    private var entries: [WindowID]

    /// Creates an empty history that remembers at most `capacity` windows.
    ///
    /// - Precondition: `capacity` is at least 1.
    public init(capacity: Int = 256) {
        precondition(capacity >= 1, "capacity must be at least 1")
        self.capacity = capacity
        self.entries = []
    }

    /// The remembered windows, most recent first.
    public var order: [WindowID] {
        entries
    }

    /// Makes `id` the most recent window. If the history is over capacity afterwards, the
    /// least recent entries are dropped.
    public mutating func recordFocus(_ id: WindowID) {
        if let index = entries.firstIndex(of: id) {
            entries.remove(at: index)
        }
        entries.insert(id, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    /// Removes `id` from the history. An unknown window is ignored.
    public mutating func forget(_ id: WindowID) {
        entries.removeAll { $0 == id }
    }

    /// Removes every window that is not in `live`, keeping the order of the rest.
    public mutating func prune(keeping live: Set<WindowID>) {
        entries.removeAll { !live.contains($0) }
    }

    /// Picks at most `count` of `candidates`, in this order:
    ///
    /// 1. candidates that are in the history, most recent first;
    /// 2. candidates that are not in the history, in the order they were given.
    ///
    /// A candidate given more than once counts once, at its first occurrence. History entries
    /// that are not candidates are ignored. A `count` of 0 or less gives an empty result.
    public func mostRecent(_ count: Int, among candidates: [WindowID]) -> [WindowID] {
        guard count > 0 else { return [] }

        let candidateSet = Set(candidates)
        let remembered = Set(entries)
        let known = entries.filter { candidateSet.contains($0) }

        var seen: Set<WindowID> = []
        let unknown = candidates.filter { !remembered.contains($0) && seen.insert($0).inserted }

        return Array((known + unknown).prefix(count))
    }
}
