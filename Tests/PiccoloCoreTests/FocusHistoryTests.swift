import Foundation
import Testing

@testable import PiccoloCore

@Suite("Focus history")
struct FocusHistoryTests {
    private func id(_ raw: UInt32) -> WindowID {
        WindowID(rawValue: raw)
    }

    private func ids(_ raw: UInt32...) -> [WindowID] {
        raw.map { WindowID(rawValue: $0) }
    }

    /// A history whose `order` is `raw`, most recent first.
    private func makeHistory(_ raw: UInt32..., capacity: Int = 256) -> FocusHistory {
        var history = FocusHistory(capacity: capacity)
        for value in raw.reversed() {
            history.recordFocus(WindowID(rawValue: value))
        }
        return history
    }

    // MARK: Recording

    @Test("a new history is empty")
    func emptyHistory() {
        #expect(FocusHistory().order.isEmpty)
    }

    @Test("recording focus puts the most recent window first")
    func recordingOrder() {
        var history = FocusHistory()
        history.recordFocus(id(1))
        history.recordFocus(id(2))
        history.recordFocus(id(3))
        #expect(history.order == ids(3, 2, 1))
    }

    @Test("re-recording a window moves it to the front without duplicating it")
    func rerecordMovesToFront() {
        var history = makeHistory(1, 2, 3)
        history.recordFocus(id(3))
        #expect(history.order == ids(3, 1, 2))
        history.recordFocus(id(3))
        #expect(history.order == ids(3, 1, 2))
    }

    @Test("re-recording a window in a full history keeps every other entry")
    func rerecordInFullHistory() {
        var history = makeHistory(1, 2, 3, capacity: 3)
        history.recordFocus(id(2))
        #expect(history.order == ids(2, 1, 3))
    }

    // MARK: Capacity

    @Test("the default capacity is 256 entries")
    func defaultCapacity() {
        var history = FocusHistory()
        for raw in 1...300 {
            history.recordFocus(WindowID(rawValue: UInt32(raw)))
        }
        #expect(history.order.count == 256)
        #expect(history.order.first == id(300))
        #expect(history.order.last == id(45))
    }

    @Test("exceeding the capacity drops the least recent entries")
    func capacityEviction() {
        var history = makeHistory(1, 2, 3, capacity: 3)
        history.recordFocus(id(4))
        #expect(history.order == ids(4, 1, 2))
        history.recordFocus(id(5))
        #expect(history.order == ids(5, 4, 1))
    }

    @Test("a capacity of 1 keeps only the most recent window")
    func capacityOne() {
        var history = FocusHistory(capacity: 1)
        history.recordFocus(id(1))
        history.recordFocus(id(2))
        #expect(history.order == ids(2))
    }

    @Test("a capacity below 1 is a precondition failure")
    func capacityZeroPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = FocusHistory(capacity: 0)
        }
    }

    @Test("a negative capacity is a precondition failure")
    func capacityNegativePrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = FocusHistory(capacity: -1)
        }
    }

    // MARK: Forget

    @Test("forgetting a known window removes it and keeps the order of the rest")
    func forgetKnown() {
        var history = makeHistory(1, 2, 3)
        history.forget(id(2))
        #expect(history.order == ids(1, 3))
    }

    @Test("forgetting an unknown window changes nothing")
    func forgetUnknown() {
        var history = makeHistory(1, 2, 3)
        history.forget(id(9))
        #expect(history.order == ids(1, 2, 3))
    }

    @Test("a forgotten window can be recorded again as the most recent")
    func recordAfterForget() {
        var history = makeHistory(1, 2, 3)
        history.forget(id(1))
        history.recordFocus(id(1))
        #expect(history.order == ids(1, 2, 3))
    }

    // MARK: Prune

    @Test("prune drops every entry that is not live and keeps the order of the rest")
    func pruneDropsDeadEntries() {
        var history = makeHistory(1, 2, 3, 4, 5)
        history.prune(keeping: [id(5), id(2), id(4), id(9)])
        #expect(history.order == ids(2, 4, 5))
    }

    @Test("prune with a set that holds every entry changes nothing")
    func pruneKeepsAll() {
        var history = makeHistory(1, 2, 3)
        history.prune(keeping: [id(1), id(2), id(3), id(4)])
        #expect(history.order == ids(1, 2, 3))
    }

    @Test("prune with an empty set empties the history")
    func pruneEmpty() {
        var history = makeHistory(1, 2, 3)
        history.prune(keeping: [])
        #expect(history.order.isEmpty)
    }

    // MARK: mostRecent

    @Test("when every candidate is known, they come most recent first")
    func mostRecentAllKnown() {
        let history = makeHistory(3, 1, 2)
        #expect(history.mostRecent(3, among: ids(1, 2, 3)) == ids(3, 1, 2))
        #expect(history.mostRecent(3, among: ids(2, 3, 1)) == ids(3, 1, 2))
    }

    @Test("when no candidate is known, they keep the given order")
    func mostRecentNoneKnown() {
        let history = makeHistory(1, 2, 3)
        #expect(history.mostRecent(3, among: ids(9, 7, 8)) == ids(9, 7, 8))
    }

    @Test("with mixed candidates, known ones come first by recency, then unknown ones in the given order")
    func mostRecentMixed() {
        let history = makeHistory(3, 1, 2)
        #expect(history.mostRecent(4, among: ids(9, 2, 8, 1)) == ids(1, 2, 9, 8))
        #expect(history.mostRecent(3, among: ids(9, 2, 8, 1)) == ids(1, 2, 9))
        #expect(history.mostRecent(2, among: ids(9, 2, 8, 1)) == ids(1, 2))
    }

    @Test("history entries that are not candidates are ignored")
    func mostRecentIgnoresNonCandidates() {
        let history = makeHistory(3, 1, 2)
        #expect(history.mostRecent(5, among: ids(2, 9)) == ids(2, 9))
        #expect(history.mostRecent(5, among: ids(9)) == ids(9))
        #expect(history.mostRecent(5, among: ids(3)) == ids(3))
    }

    @Test("a duplicate known candidate counts once")
    func mostRecentDuplicateKnown() {
        let history = makeHistory(2, 1)
        #expect(history.mostRecent(4, among: ids(1, 2, 1, 2)) == ids(2, 1))
        #expect(history.mostRecent(1, among: ids(1, 2, 1, 2)) == ids(2))
    }

    @Test("a duplicate unknown candidate counts once, at its first occurrence")
    func mostRecentDuplicateUnknown() {
        let history = FocusHistory()
        #expect(history.mostRecent(4, among: ids(9, 8, 9, 7, 8)) == ids(9, 8, 7))
        #expect(history.mostRecent(4, among: ids(8, 9, 8)) == ids(8, 9))
    }

    @Test("duplicates among mixed candidates count once each")
    func mostRecentDuplicateMixed() {
        let history = makeHistory(1)
        #expect(history.mostRecent(4, among: ids(9, 1, 8, 9, 1)) == ids(1, 9, 8))
        #expect(history.mostRecent(2, among: ids(9, 1, 8, 9, 1)) == ids(1, 9))
    }

    @Test("a count larger than the candidates returns all of them")
    func mostRecentCountLargerThanCandidates() {
        let history = makeHistory(1, 2, 3)
        #expect(history.mostRecent(10, among: ids(3, 4)) == ids(3, 4))
        #expect(history.mostRecent(10, among: ids(9)) == ids(9))
    }

    @Test("no candidates give an empty result")
    func mostRecentNoCandidates() {
        let history = makeHistory(1, 2, 3)
        #expect(history.mostRecent(3, among: []).isEmpty)
    }

    @Test("a count of 0 or below gives an empty result", arguments: [0, -1, -5, Int.min])
    func mostRecentNonPositiveCount(count: Int) {
        let history = makeHistory(1, 2, 3)
        #expect(history.mostRecent(count, among: ids(1, 2, 3, 4)).isEmpty)
    }

    // MARK: Value semantics

    @Test("a copy is not affected by later changes to the original, and the other way round")
    func valueSemantics() {
        var original = makeHistory(1, 2)
        var copy = original

        original.recordFocus(id(3))
        original.forget(id(1))
        #expect(copy.order == ids(1, 2))
        #expect(original.order == ids(3, 2))

        copy.recordFocus(id(4))
        #expect(original.order == ids(3, 2))
        #expect(copy.order == ids(4, 1, 2))
    }

    @Test("histories with the same contents are equal")
    func equality() {
        #expect(makeHistory(1, 2) == makeHistory(1, 2))
        #expect(makeHistory(1, 2) != makeHistory(2, 1))
    }
}
