/// The groups Piccolo has arranged and still tracks: at most one per display, and no window in
/// more than one.
///
/// A value type, so that the rules are testable without windows. The app keeps one instance in
/// memory behind a lock (`LayoutGroupStore` in `PiccoloSystem`); nothing is persisted.
public struct LayoutGroups: Equatable, Sendable {
    /// A group and the display it was arranged on.
    public struct Entry: Equatable, Sendable {
        /// The index of the display in the list the arrangement was planned on, the primary first.
        public var display: Int
        public var group: LayoutGroup

        public init(display: Int, group: LayoutGroup) {
            self.display = display
            self.group = group
        }
    }

    private var byDisplay: [Int: LayoutGroup] = [:]

    public init() {}

    /// Every group, in display order.
    public var entries: [Entry] {
        byDisplay.keys.sorted().map { Entry(display: $0, group: byDisplay[$0]!) }
    }

    /// The group that holds `window`, with its display.
    public func entry(containing window: WindowID) -> Entry? {
        entries.first { $0.group.cell(of: window) != nil }
    }

    /// Records `group` as the group of `display`, replacing the one that was there.
    ///
    /// A window belongs to one group only: any other group that holds one of `group`'s windows is
    /// dissolved too, because those windows were just placed again.
    public mutating func record(_ group: LayoutGroup, onDisplay display: Int) {
        let members = Set(group.windows)
        for (other, existing) in byDisplay where other != display {
            if existing.windows.contains(where: members.contains) {
                byDisplay[other] = nil
            }
        }
        byDisplay[display] = group
    }

    /// Replaces the group of `display` with `group`, for a group that moved a divider. Does
    /// nothing when the display has no group any more.
    public mutating func update(_ group: LayoutGroup, onDisplay display: Int) {
        guard byDisplay[display] != nil else { return }
        byDisplay[display] = group
    }

    /// Dissolves the group of `display`, if it has one.
    public mutating func dissolve(display: Int) {
        byDisplay[display] = nil
    }
}
