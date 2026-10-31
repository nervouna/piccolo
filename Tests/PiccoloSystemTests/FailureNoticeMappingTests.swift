import CoreGraphics
import Testing

import PiccoloCore

@testable import PiccoloSystem

@Suite("FailureNotice: what a run produced")
struct FailureNoticeMappingTests {
    private static let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    private static let leftHalf = Action.placeWindow(.preset(.leftHalf))
    private static let nextDisplay = Action.moveToDisplay(.next)
    private static let grid = Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))
    private static let divider = Action.moveDivider(.right)
    private static let swap = Action.swapWindow(.left)

    private static func arrangedWindow(failing: Bool) -> ArrangedWindow {
        ArrangedWindow(
            window: WindowID(rawValue: 1), target: frame,
            result: failing ? .failed(message: "gone") : .placed(achieved: frame))
    }

    // MARK: Errors

    @Test("window errors")
    func windowErrors() {
        #expect(FailureNotice(error: WindowError.notTrusted) == .accessibilityNotGranted)
        #expect(FailureNotice(error: WindowError.noFrontmostApplication) == .noWindow)
        #expect(FailureNotice(error: WindowError.noFocusedWindow) == .noWindow)
        #expect(FailureNotice(error: WindowError.ownWindow) == .ownWindow)
        #expect(FailureNotice(error: WindowError.windowGone) == .windowNotChangeable)
        #expect(FailureNotice(error: WindowError.attributeNotSettable("AXSize")) == .windowNotChangeable)
        #expect(FailureNotice(error: WindowError.accessibility(operation: "read", code: -25205)) == .windowNotChangeable)
    }

    @Test("every error of the arrangement planner is a grid that does not fit")
    func arrangePlannerErrors() {
        #expect(FailureNotice(error: ArrangePlannerError.cellTooSmall) == .gridDoesNotFit)
        #expect(FailureNotice(error: ArrangePlannerError.displayIndexOutOfRange) == .gridDoesNotFit)
        #expect(FailureNotice(error: ArrangePlannerError.invalidGrid(.outOfRange(field: "rows", rule: "must be >= 1"))) == .gridDoesNotFit)
    }

    @Test("a config error gives no notice")
    func configErrors() {
        #expect(FailureNotice(error: ActionExecutionError.invalidResizeStep(0)) == nil)
        #expect(FailureNotice(error: ActionPlanningError.noDisplays) == nil)
        #expect(FailureNotice(error: ActionPlanningError.notSingleWindowAction) == nil)
        struct Unknown: Error {}
        #expect(FailureNotice(error: Unknown()) == nil)
    }

    // MARK: Outcomes

    @Test("a placed window gives no notice")
    func placed() {
        let outcome = ActionOutcome.placed(target: Self.frame, achieved: Self.frame)
        #expect(FailureNotice(outcome: outcome, for: Self.leftHalf) == nil)
    }

    @Test("nothing to do: a notice for moveToDisplay and arrangeGrid, none for placeWindow")
    func nothingToDo() {
        #expect(FailureNotice(outcome: .nothingToDo, for: Self.nextDisplay) == .noOtherDisplay)
        #expect(FailureNotice(outcome: .nothingToDo, for: Self.grid) == .nothingToArrange)
        #expect(FailureNotice(outcome: .nothingToDo, for: Self.leftHalf) == nil)
        #expect(FailureNotice(outcome: .nothingToDo, for: Self.divider) == nil)
        #expect(FailureNotice(outcome: .nothingToDo, for: Self.swap) == nil)
        #expect(FailureNotice(outcome: .nothingToDo, for: .restoreWindow) == .nothingToRestore)
        #expect(FailureNotice(outcome: .placed(target: .zero, achieved: .zero), for: .restoreWindow) == nil)
    }

    @Test("an arrangement: a notice only when a window failed")
    func arranged() {
        let good = ArrangeOutcome(
            displayIndex: 0, windows: [Self.arrangedWindow(failing: false), Self.arrangedWindow(failing: false)])
        let bad = ArrangeOutcome(
            displayIndex: 0, windows: [Self.arrangedWindow(failing: false), Self.arrangedWindow(failing: true)])
        #expect(FailureNotice(outcome: .arranged(good), for: Self.grid) == nil)
        #expect(FailureNotice(outcome: .arranged(bad), for: Self.grid) == .windowNotChangeable)
    }

    @Test("a divider move: a notice only when a window failed")
    func dividerMoved() {
        let good = DividerMoved(display: 0, windows: [Self.arrangedWindow(failing: false)])
        let bad = DividerMoved(display: 0, windows: [Self.arrangedWindow(failing: true)])
        #expect(FailureNotice(outcome: .dividerMove(.moved(good)), for: Self.divider) == nil)
        #expect(FailureNotice(outcome: .dividerMove(.moved(bad)), for: Self.divider) == .windowNotChangeable)
    }

    @Test("the reasons a divider did not move")
    func dividerReasons() {
        let id = WindowID(rawValue: 7)
        func notice(_ reason: DividerMoveOutcome.Reason) -> FailureNotice? {
            FailureNotice(outcome: .dividerMove(.nothingToDo(reason)), for: Self.divider)
        }
        #expect(notice(.noFocusedWindow) == .noWindow)
        #expect(notice(.noGroup) == .noGroup)
        #expect(notice(.dissolved(.missing(id))) == .dissolved)
        #expect(notice(.dissolved(.moved(id))) == .dissolved)
        #expect(notice(.cannotMove) == .cannotMove)
    }

    @Test("a swap: a notice only when a window failed")
    func swapped() {
        let good = ActionOutcome.swap(.swapped(display: 0, windows: [Self.arrangedWindow(failing: false)]))
        let bad = ActionOutcome.swap(
            .swapped(display: 0, windows: [Self.arrangedWindow(failing: false), Self.arrangedWindow(failing: true)]))
        #expect(FailureNotice(outcome: good, for: Self.swap) == nil)
        #expect(FailureNotice(outcome: bad, for: Self.swap) == .windowNotChangeable)
    }

    @Test("the reasons a swap did nothing")
    func swapReasons() {
        let id = WindowID(rawValue: 7)
        func notice(_ reason: SwapOutcome.Reason) -> FailureNotice? {
            FailureNotice(outcome: .swap(.nothingToDo(reason)), for: Self.swap)
        }
        #expect(notice(.noFocusedWindow) == .noWindow)
        #expect(notice(.noGroup) == .noGroup)
        #expect(notice(.dissolved(.missing(id))) == .dissolved)
        #expect(notice(.dissolved(.moved(id))) == .dissolved)
        #expect(notice(.noNeighbour(bounced: false)) == .noNeighbour)
        #expect(notice(.noNeighbour(bounced: true)) == nil)
    }

    @Test("the notices have stable names")
    func names() {
        #expect(FailureNotice.noGroup.rawValue == "noGroup")
        #expect(FailureNotice.noNeighbour.rawValue == "noNeighbour")
        #expect(FailureNotice.allCases.count == 12)
        #expect(Set(FailureNotice.allCases.map(\.rawValue)).count == 12)
    }
}
