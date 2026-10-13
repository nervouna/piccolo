import CoreGraphics
import Testing

@testable import PiccoloCore

@Suite("Arrange planner errors")
struct ArrangePlannerErrorTests {
    typealias Support = ArrangePlannerSupport

    /// A grid that breaks one rule of the grid validation, with the error the planner must throw.
    struct InvalidGrid: Sendable, CustomTestStringConvertible {
        let grid: GridSpec
        let error: ValidationError

        var testDescription: String {
            "rows \(grid.rows), columns \(grid.columns), count \(grid.count)"
        }
    }

    static let invalidGrids: [InvalidGrid] = [
        InvalidGrid(
            grid: GridSpec(count: 1, rows: 0, columns: 2),
            error: .outOfRange(field: "rows", rule: "must be >= 1")),
        InvalidGrid(
            grid: GridSpec(count: 1, rows: -1, columns: 2),
            error: .outOfRange(field: "rows", rule: "must be >= 1")),
        InvalidGrid(
            grid: GridSpec(count: 1, rows: 2, columns: 0),
            error: .outOfRange(field: "columns", rule: "must be >= 1")),
        InvalidGrid(
            grid: GridSpec(count: 0, rows: 2, columns: 2),
            error: .outOfRange(field: "count", rule: "must be >= 1")),
        InvalidGrid(
            grid: GridSpec(count: -1, rows: 2, columns: 2),
            error: .outOfRange(field: "count", rule: "must be >= 1")),
        InvalidGrid(
            grid: GridSpec(count: 5, rows: 2, columns: 2),
            error: .outOfRange(field: "count", rule: "must be <= rows * columns")),
    ]

    /// Plans `candidates` in `grid` on a single display whose visible frame is `visible`.
    private func plan(
        on visible: CGRect,
        grid: GridSpec = Support.last4In2x2,
        candidates: [WindowCandidate]
    ) throws(ArrangePlannerError) -> ArrangePlan? {
        try ArrangePlanner.plan(
            grid: grid,
            displayIndex: 0,
            candidates: candidates,
            history: FocusHistory(),
            displays: [Display(frame: visible, visibleFrame: visible)])
    }

    // MARK: Display index

    @Test("a display index outside the displays is an error, even with no windows")
    func displayIndexOutOfRange() {
        for index in [-1, 2] {
            #expect(throws: ArrangePlannerError.displayIndexOutOfRange) {
                try ArrangePlanner.plan(
                    grid: Support.last4In2x2,
                    displayIndex: index,
                    candidates: Support.windows(2),
                    history: FocusHistory(),
                    displays: Support.twoDisplays)
            }
        }
        #expect(throws: ArrangePlannerError.displayIndexOutOfRange) {
            try ArrangePlanner.plan(
                grid: Support.last4In2x2,
                displayIndex: 0,
                candidates: [],
                history: FocusHistory(),
                displays: [])
        }
    }

    // MARK: Grid

    @Test("an invalid grid is an error", arguments: invalidGrids)
    func invalidGrid(_ invalid: InvalidGrid) {
        #expect(throws: ArrangePlannerError.invalidGrid(invalid.error)) {
            try ArrangePlanner.plan(
                grid: invalid.grid,
                displayIndex: 0,
                candidates: Support.windows(1),
                history: FocusHistory(),
                displays: Support.twoDisplays)
        }
    }

    @Test("an invalid grid is an error even when there is nothing to arrange")
    func invalidGridWithNoWindows() {
        #expect(throws: ArrangePlannerError.invalidGrid(.outOfRange(field: "count", rule: "must be <= rows * columns"))) {
            try ArrangePlanner.plan(
                grid: GridSpec(count: 5, rows: 2, columns: 2),
                displayIndex: 0,
                candidates: [],
                history: FocusHistory(),
                displays: Support.twoDisplays)
        }
    }

    // MARK: Cell size

    @Test("a 2x2 grid on a 150x150 visible frame has cells below the minimum")
    func smallFrameTooSmallCells() {
        #expect(throws: ArrangePlannerError.cellTooSmall) {
            try plan(on: CGRect(x: 0, y: 0, width: 150, height: 150), candidates: Support.windows(4))
        }
    }

    @Test("a column narrower than the minimum is an error")
    func columnTooNarrow() {
        // 199 pt split in two gives 100 and 99 pt, and 99 is below the minimum.
        #expect(throws: ArrangePlannerError.cellTooSmall) {
            try plan(
                on: CGRect(x: 0, y: 0, width: 199, height: 200),
                grid: GridSpec(count: 2, rows: 1, columns: 2),
                candidates: Support.windows(2))
        }
    }

    @Test("a row shorter than the minimum is an error")
    func rowTooShort() {
        // 199 pt split in two gives 100 and 99 pt, and 99 is below the minimum.
        #expect(throws: ArrangePlannerError.cellTooSmall) {
            try plan(
                on: CGRect(x: 0, y: 0, width: 200, height: 199),
                grid: GridSpec(count: 2, rows: 2, columns: 1),
                candidates: Support.windows(2))
        }
    }

    @Test("a single window on a frame smaller than the minimum is an error")
    func singleCellTooSmall() {
        #expect(throws: ArrangePlannerError.cellTooSmall) {
            try plan(
                on: CGRect(x: 0, y: 0, width: 99, height: 99),
                grid: GridSpec(count: 1, rows: 1, columns: 1),
                candidates: Support.windows(1))
        }
    }

    @Test("a cell of exactly the minimum size is allowed")
    func minimumSizeAllowed() throws {
        let four = try plan(on: CGRect(x: 0, y: 0, width: 200, height: 200), candidates: Support.windows(4))
        #expect(four?.assignments.map(\.frame) == [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 100, width: 100, height: 100),
            CGRect(x: 100, y: 100, width: 100, height: 100),
        ])

        let single = try plan(
            on: CGRect(x: 0, y: 0, width: 100, height: 100),
            grid: GridSpec(count: 1, rows: 1, columns: 1),
            candidates: Support.windows(1))
        #expect(single?.assignments.map(\.frame) == [CGRect(x: 0, y: 0, width: 100, height: 100)])
    }

    @Test("a frame too small for a cell does not matter when nothing is arranged")
    func tinyFrameWithNoWindows() throws {
        let result = try plan(on: CGRect(x: 0, y: 0, width: 150, height: 150), candidates: [])
        #expect(result == nil)
    }
}
