import Foundation
import PiccoloCore

/// The groups of windows Piccolo has arranged, shared by the threads that run actions.
///
/// A thin lock around ``LayoutGroups``, which holds the rules. In memory only: the groups are gone
/// when Piccolo quits.
public final class LayoutGroupStore: @unchecked Sendable {
    private let lock = NSLock()
    private var groups = LayoutGroups()

    public init() {}

    /// Every group, in display order.
    public var entries: [LayoutGroups.Entry] {
        locked { $0.entries }
    }

    /// The group that holds `window`, with its display.
    func entry(containing window: WindowID) -> LayoutGroups.Entry? {
        locked { $0.entry(containing: window) }
    }

    /// Records `group` as the group of `display`; see ``LayoutGroups/record(_:onDisplay:)``.
    func record(_ group: LayoutGroup, onDisplay display: Int) {
        locked { $0.record(group, onDisplay: display) }
    }

    /// Replaces the group of `display`; see ``LayoutGroups/update(_:onDisplay:)``.
    func update(_ group: LayoutGroup, onDisplay display: Int) {
        locked { $0.update(group, onDisplay: display) }
    }

    /// Dissolves the group of `display`.
    func dissolve(display: Int) {
        locked { $0.dissolve(display: display) }
    }

    private func locked<Result>(_ body: (inout LayoutGroups) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&groups)
    }
}
