import CoreGraphics
import Foundation
import PiccoloCore
import PiccoloSystem
import Testing

/// The steps the arrange tests share: windows opened on a display and focused in a known order, the
/// grid the app should lay them out in, and the checks on what the window server then measures.
///
/// Every arrangement goes through `ArrangeRun`, which passes the fixture's pid as `onlyPid`: no
/// test can arrange a window that is not the fixture's.
struct ArrangeRun {
    let fixture: FixtureApp
    let piccolo: PiccoloClient

    init(fixture: FixtureApp, piccolo: PiccoloClient = PiccoloClient()) {
        self.fixture = fixture
        self.piccolo = piccolo
    }

    // MARK: Setting up

    /// A window frame for the `index`-th window of a cascade on `screen`. Distinct for every index,
    /// well inside the display, and never one of the cells of a grid.
    static func cascadeFrame(_ index: Int, on screen: ScreenInfo, size: CGSize? = nil) -> CGRect {
        let visible = screen.visibleFrame
        let size = size ?? CGSize(width: min(520, visible.width * 0.4), height: min(380, visible.height * 0.4))
        return Layout.frame(
            in: screen, offset: CGPoint(x: 40 + CGFloat(index) * 35, y: 40 + CGFloat(index) * 30), size: size)
    }

    /// Opens the windows `ids` on `screen`, in a cascade, and waits until each is measured where it
    /// was opened. `minSizes` gives some of them a minimum size, which is also their opening size.
    func open(
        _ ids: [String], on screen: ScreenInfo, firstIndex: Int = 0, minSizes: [String: CGSize] = [:]
    ) async throws -> [FixtureWindow] {
        var windows: [FixtureWindow] = []
        for (offset, id) in ids.enumerated() {
            let frame = Self.cascadeFrame(firstIndex + offset, on: screen, size: minSizes[id])
            let window = try fixture.open(id: id, frame: frame, minSize: minSizes[id])
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
            windows.append(window)
        }
        return windows
    }

    /// Focuses the windows one after the other, each one verified with `Focus.bring`, and waits until
    /// Piccolo's focus history lists them: the last one first.
    func focus(_ windows: [FixtureWindow]) async throws {
        for window in windows {
            try await Focus.bring(window, of: fixture)
        }
        try await waitForHistory(of: windows)
    }

    /// Waits until the focus history, reduced to `windows`, lists them in the reverse of the order given.
    func waitForHistory(of windows: [FixtureWindow]) async throws {
        let expected = windows.reversed().map(\.windowNumber)
        let numbers = Set(expected)
        _ = try await eventually(
            "focus.history to list the fixture windows \(expected), most recent first", timeout: 8
        ) { () throws -> Observation<Void> in
            let all = try piccolo.focusHistory()
            let history = all.filter { numbers.contains($0) }
            return history == expected
                ? .satisfied(())
                : .unsatisfied("it lists \(history) of the fixture's windows, and \(all.count) windows in all (first ten: \(all.prefix(10)))")
        }
    }

    // MARK: Arranging

    /// Arranges the fixture's windows and returns the answer.
    func arrange(_ grid: GridSpec) throws -> PiccoloClient.ArrangeResult {
        try piccolo.arrangeGrid(grid, onlyPid: try fixture.processID())
    }

    /// The cells of `count` windows in `grid`, as `TileLayout` lays them out on the visible frame, in
    /// the fill order of the config in effect (rows first unless the test sets `gridFillOrder`).
    static func cells(
        _ count: Int, in grid: GridSpec, on screen: ScreenInfo, fillOrder: GridFillOrder = .rows
    ) -> (layout: TileLayout, frames: [CGRect]) {
        let layout = TileLayout.grid(
            windowCount: count, rows: grid.rows, columns: grid.columns, fillOrder: fillOrder)
        return (layout, layout.frames(in: screen.visibleFrame))
    }

    // MARK: Checking

    /// Checks an arrangement: the answer lists `order` (the window in the top-left cell first), each
    /// window was sent to its cell and is measured there. `fillOrder` is the one the config in effect
    /// names; it decides which cell is cell `i`.
    ///
    /// Windows named in `refusing` are expected to have refused the size: their reported and measured
    /// frames are compared with each other, not with the cell.
    ///
    /// - Returns: The measured frame of each window, in the order of `order`.
    @discardableResult
    func expectArranged(
        _ result: PiccoloClient.ArrangeResult,
        order: [FixtureWindow],
        grid: GridSpec,
        on screen: ScreenInfo,
        refusing: Set<String> = [],
        fillOrder: GridFillOrder = .rows
    ) async throws -> [CGRect] {
        guard case .arranged(let display, let reported) = result else {
            throw AcceptanceFailure("arrangeGrid answered \(result), expected an arrangement of \(order.map(\.id))")
        }
        #expect(display == screen.index, "the windows were arranged on display \(display), the test is about display \(screen.index)")
        #expect(
            reported.map(\.windowNumber) == order.map(\.windowNumber),
            "the answer lists the windows \(reported.map(\.windowNumber)), expected \(order.map { "\($0.id)=\($0.windowNumber)" })"
        )
        guard reported.count == order.count else {
            throw AcceptanceFailure("the answer lists \(reported.count) windows, expected \(order.count)")
        }

        let (_, cells) = Self.cells(order.count, in: grid, on: screen, fillOrder: fillOrder)
        var measuredFrames: [CGRect] = []
        for (index, window) in order.enumerated() {
            let entry = reported[index]
            #expect(
                framesMatch(entry.target, cells[index]),
                "window '\(window.id)' was sent to \(describe(entry.target)), TileLayout puts cell \(index) at \(describe(cells[index]))"
            )
            if let error = entry.error {
                throw AcceptanceFailure("window '\(window.id)' could not be moved: \(error)")
            }
            guard let achieved = entry.achieved else {
                throw AcceptanceFailure("the answer for window '\(window.id)' has neither achieved nor error")
            }
            let measured = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: achieved)
            if !refusing.contains(window.id) {
                #expect(
                    framesMatch(measured, cells[index]),
                    "window '\(window.id)' is measured at \(describe(measured)), its cell is \(describe(cells[index]))"
                )
            }
            measuredFrames.append(measured)
        }
        return measuredFrames
    }

    /// Checks that measured frames (in cell order) tile `screen`'s visible frame as `layout` says:
    /// neighbouring cells share an edge within one point (no overlap, no gap), and together they reach
    /// the edges of the visible frame.
    func expectTiled(_ measured: [CGRect], layout: TileLayout, on screen: ScreenInfo) {
        let visible = screen.visibleFrame
        switch layout.orientation {
        case .rows: expectTiledRows(measured, layout: layout)
        case .columns: expectTiledColumns(measured, layout: layout)
        }

        let all = measured.reduce(CGRect.null) { $0.union($1) }
        #expect(
            approximatelyEqual(all.minX, visible.minX) && approximatelyEqual(all.minY, visible.minY)
                && approximatelyEqual(all.maxX, visible.maxX) && approximatelyEqual(all.maxY, visible.maxY),
            "the cells together span \(describe(all)), the visible frame is \(describe(visible)); the cells are \(measured.map { describe($0) })")
    }

    private func expectTiledRows(_ measured: [CGRect], layout: TileLayout) {
        var rows: [[CGRect]] = []
        var next = 0
        for row in layout.rows {
            rows.append(Array(measured[next..<(next + row.widths.count)]))
            next += row.widths.count
        }

        for (rowIndex, row) in rows.enumerated() {
            for (left, right) in zip(row, row.dropFirst()) {
                #expect(
                    approximatelyEqual(left.maxX, right.minX),
                    "row \(rowIndex): a cell ends at x \(left.maxX) and the next one starts at x \(right.minX), they should share an edge (no gap or overlap wider than \(frameTolerance) pt)"
                )
            }
            if rowIndex + 1 < rows.count {
                for above in row {
                    for below in rows[rowIndex + 1]
                    where min(above.maxX, below.maxX) - max(above.minX, below.minX) > frameTolerance {
                        #expect(
                            approximatelyEqual(above.maxY, below.minY),
                            "a cell in row \(rowIndex) ends at y \(above.maxY) and the cell below it starts at y \(below.minY), they should share an edge (no gap or overlap wider than \(frameTolerance) pt)"
                        )
                    }
                }
            }
        }
    }

    /// The columns of a column layout, the way `expectTiledRows` checks the rows of a row layout.
    private func expectTiledColumns(_ measured: [CGRect], layout: TileLayout) {
        var columns: [[CGRect]] = []
        var next = 0
        for column in layout.columns {
            columns.append(Array(measured[next..<(next + column.heights.count)]))
            next += column.heights.count
        }

        for (columnIndex, column) in columns.enumerated() {
            for (above, below) in zip(column, column.dropFirst()) {
                #expect(
                    approximatelyEqual(above.maxY, below.minY),
                    "column \(columnIndex): a cell ends at y \(above.maxY) and the next one starts at y \(below.minY), they should share an edge (no gap or overlap wider than \(frameTolerance) pt)"
                )
            }
            if columnIndex + 1 < columns.count {
                for left in column {
                    for right in columns[columnIndex + 1]
                    where min(left.maxY, right.maxY) - max(left.minY, right.minY) > frameTolerance {
                        #expect(
                            approximatelyEqual(left.maxX, right.minX),
                            "a cell in column \(columnIndex) ends at x \(left.maxX) and the cell to its right starts at x \(right.minX), they should share an edge (no gap or overlap wider than \(frameTolerance) pt)"
                        )
                    }
                }
            }
        }
    }

    /// The given windows that are on screen, front to back, as the window server stacks them.
    static func stacking(of windows: [FixtureWindow]) -> [Int] {
        let numbers = Set(windows.map(\.windowNumber))
        guard
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return info.compactMap { $0[kCGWindowNumber as String] as? Int }.filter { numbers.contains($0) }
    }

    /// Checks that each window is still measured where it was (within the tolerance).
    func expectUnmoved(_ windows: [FixtureWindow], at frames: [CGRect]) {
        for (window, frame) in zip(windows, frames) {
            let measured = Measure.frame(ofWindow: window.windowNumber)
            #expect(
                measured.map { framesMatch($0, frame) } == true,
                "window '\(window.id)' should not have moved from \(describe(frame)), it is measured at \(measured.map { describe($0) } ?? "nowhere")"
            )
        }
    }

    /// The displays as this process sees them (see `Layout.screens`).
    static func screens() async throws -> [ScreenInfo] {
        try await MainActor.run { try Layout.screens() }
    }
}
