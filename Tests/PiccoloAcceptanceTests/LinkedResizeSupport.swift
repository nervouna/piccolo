import CoreGraphics
import Foundation
import PiccoloCore
import PiccoloSystem
import Testing

extension ConfigDirectory {
    /// Writes a config with no bindings, this resize step and this grid fill order as `name`, and
    /// returns its URL.
    @discardableResult
    func write(
        resizeStep: Double, animation: WindowAnimation = Config.defaultAnimation,
        gridFillOrder: GridFillOrder = .rows, gap: Int = Config.defaultGap,
        destinationPreview: Bool = Config.defaultDestinationPreview, bindings: [KeyBinding] = [],
        as name: String = "config.json"
    ) throws -> URL {
        let target = file(name)
        try ConfigStore(url: target).save(
            Config(
                resizeStep: resizeStep, animation: animation, gridFillOrder: gridFillOrder,
                destinationPreview: destinationPreview, gap: gap, bindings: bindings))
        return target
    }
}

/// Runs `body` against a Piccolo whose config has no bindings (unless `bindings` gives some), the
/// resize step `step`, the window `animation`, the grid fill order `gridFillOrder`, the window `gap`
/// and the destination preview setting, so that the expected frames do not depend on the config of whoever runs the tests,
/// and with a fixture that starts with no windows. Afterwards the fixture windows are closed and
/// Piccolo is back on the fresh-install config the test started on (see `withConfigDirectory`).
func withLinkedResize<Result>(
    step: Double = LinkedRun.defaultStep,
    animation: WindowAnimation = Config.defaultAnimation,
    gridFillOrder: GridFillOrder = .rows,
    gap: Int = Config.defaultGap,
    destinationPreview: Bool = Config.defaultDestinationPreview,
    bindings: [KeyBinding] = [],
    _ body: (LinkedRun) async throws -> Result
) async throws -> Result {
    let screen = try await ArrangeRun.screens()[0]
    return try await withConfigDirectory { directory in
        try PiccoloClient().loadConfig(
            at: try directory.write(
                resizeStep: step, animation: animation, gridFillOrder: gridFillOrder, gap: gap,
                destinationPreview: destinationPreview, bindings: bindings))
        return try await withFixture { fixture in
            try await body(
                LinkedRun(
                    run: ArrangeRun(fixture: fixture), screen: screen, step: step,
                    fillOrder: gridFillOrder))
        }
    }
}

/// The steps the linked resize tests share, on top of `ArrangeRun`: windows arranged so that a test
/// knows which window sits in which cell, a key pressed from a focused window, and the checks on what
/// the window server then measures.
///
/// Every move goes through `piccolo.moveDivider`, which passes the fixture's pid as `onlyPid`, and
/// every group is made by `ArrangeRun.arrange`, which does the same: the windows of the machine's
/// owner never join a group, so a divider move cannot touch them.
///
/// Expected frames come from `TileLayout` on the visible frame of the display the app reports. A
/// measured frame is compared with the expected one within two points: each of the width and the
/// height is the difference of two edges, and each edge is accurate to one point (see
/// `docs/acceptance.md`). Neighbouring windows are compared edge to edge within one point, the
/// tolerance of `expectTiled`.
struct LinkedRun {
    static let defaultStep = 0.05
    /// The tolerance for a window measured against its expected frame, in points.
    static let frameTolerance: CGFloat = 2

    let run: ArrangeRun
    let screen: ScreenInfo
    /// The resize step of the config in effect, as a fraction.
    let step: Double
    /// The grid fill order of the config in effect: it decides which cell is cell `i` of an arrangement.
    var fillOrder: GridFillOrder = .rows

    var fixture: FixtureApp { run.fixture }
    var piccolo: PiccoloClient { run.piccolo }

    // MARK: Setting up

    /// Opens windows on the display under test, in a cascade.
    func open(_ ids: [String], minSizes: [String: CGSize] = [:]) async throws -> [FixtureWindow] {
        try await run.open(ids, on: screen, minSizes: minSizes)
    }

    /// Focuses the windows so that the first one is the most recently focused, and arranges them in
    /// `grid`. Window `i` ends up in cell `i` (row-major, or column-major with columns first),
    /// whatever the layout. Checks the arrangement and the group Piccolo records for it.
    ///
    /// - Returns: The layout and the frames the windows are measured at.
    @discardableResult
    func arrange(_ windows: [FixtureWindow], in grid: GridSpec) async throws -> (layout: TileLayout, frames: [CGRect]) {
        try await run.focus(windows.reversed())
        let result = try run.arrange(grid)
        let measured = try await run.expectArranged(
            result, order: windows, grid: grid, on: screen, fillOrder: fillOrder)
        let layout = ArrangeRun.cells(windows.count, in: grid, on: screen, fillOrder: fillOrder).layout
        run.expectTiled(measured, layout: layout, on: screen)
        try expectGroup(windows, layout: layout, frames: measured)
        return (layout, measured)
    }

    // MARK: Pressing

    /// Focuses `window` (unless `refocus` is false: the window already has the focus) and presses
    /// the key.
    func press(
        _ key: Direction, from window: FixtureWindow, refocus: Bool = true
    ) async throws -> PiccoloClient.MoveDividerResult {
        if refocus { try await Focus.bring(window, of: fixture) }
        return try piccolo.moveDivider(key, onlyPid: try fixture.processID())
    }

    /// Presses the key and expects the divider to move.
    ///
    /// - Returns: The windows of the group in cell order, with what Piccolo reports for each.
    func pressExpectingMove(
        _ key: Direction, from window: FixtureWindow, refocus: Bool = true
    ) async throws -> [PiccoloClient.ArrangedWindow] {
        let result = try await press(key, from: window, refocus: refocus)
        guard case .moved(let display, let reported) = result else {
            throw AcceptanceFailure("\(key) from window '\(window.id)' answered \(result), expected the divider to move")
        }
        #expect(display == screen.index, "the group is on display \(display), the test is about display \(screen.index)")
        return reported
    }

    /// Presses the key and expects nothing to happen, for this reason.
    func pressExpectingNothing(
        _ key: Direction, from window: FixtureWindow, reason: String, refocus: Bool = true
    ) async throws -> PiccoloClient.DividerNothingToDo {
        let result = try await press(key, from: window, refocus: refocus)
        guard case .nothingToDo(let nothing) = result else {
            throw AcceptanceFailure(
                "\(key) from window '\(window.id)' answered \(result), expected nothing to do (\(reason))")
        }
        #expect(
            nothing.reason == reason,
            "\(key) from window '\(window.id)' did nothing because \"\(nothing.reason)\" (\(nothing.message)), expected \"\(reason)\"")
        return nothing
    }

    // MARK: Checking

    /// Waits until the window is measured at `expected` (within `LinkedRun.frameTolerance`) and has
    /// stayed there (see `Measure.waitForFrame`).
    func waitForFrame(of window: FixtureWindow, matching expected: CGRect) async throws -> CGRect {
        do {
            return try await Measure.waitForFrame(
                ofWindow: window.windowNumber, matching: expected, tolerance: Self.frameTolerance)
        } catch let failure as AcceptanceFailure {
            throw AcceptanceFailure("window '\(window.id)': \(failure.message)", isRetryable: failure.isRetryable)
        }
    }

    /// Checks that the windows (in cell order) are measured where `layout` puts them, that they tile
    /// the visible frame without a gap or an overlap, that Piccolo's report lists each of them at its
    /// cell, and that the group Piccolo records holds the same layout and frames.
    ///
    /// - Returns: The measured frames, in cell order.
    @discardableResult
    func expectLayout(
        _ layout: TileLayout, windows: [FixtureWindow], reported: [PiccoloClient.ArrangedWindow]? = nil
    ) async throws -> [CGRect] {
        let cells = layout.frames(in: screen.visibleFrame)
        var measured: [CGRect] = []
        for (window, cell) in zip(windows, cells) {
            measured.append(try await waitForFrame(of: window, matching: cell))
        }
        run.expectTiled(measured, layout: layout, on: screen)

        if let reported {
            #expect(
                reported.map(\.windowNumber) == windows.map(\.windowNumber),
                "the answer lists the windows \(reported.map(\.windowNumber)), expected \(windows.map { "\($0.id)=\($0.windowNumber)" }) in cell order"
            )
            for (index, entry) in reported.enumerated() where index < cells.count {
                #expect(
                    framesMatch(entry.target, cells[index], tolerance: Self.frameTolerance),
                    "window '\(windows[index].id)' was sent to \(describe(entry.target)), the layout puts cell \(index) at \(describe(cells[index]))"
                )
                if let error = entry.error {
                    Issue.record("window '\(windows[index].id)' could not be moved: \(error)")
                }
            }
        }
        try expectGroup(windows, layout: layout, frames: measured)
        return measured
    }

    /// Checks `groups.list`: one group on the display under test that holds exactly these windows in
    /// this order, in the layout (its fractions within 0.003, about three points on a wide display) and
    /// at the frames they are measured at.
    func expectGroup(_ windows: [FixtureWindow], layout: TileLayout, frames: [CGRect]) throws {
        let groups = try piccolo.groups()
        guard let group = groups.first(where: { $0.display == screen.index }) else {
            throw AcceptanceFailure("groups.list has no group for display \(screen.index): \(groups)")
        }
        #expect(
            group.windows.map(\.windowNumber) == windows.map(\.windowNumber),
            "the group holds the windows \(group.windows.map(\.windowNumber)), expected \(windows.map { "\($0.id)=\($0.windowNumber)" }) in cell order"
        )
        #expect(
            framesMatch(group.visibleFrame, screen.visibleFrame),
            "the group is framed in \(describe(group.visibleFrame)), the display's visible frame is \(describe(screen.visibleFrame))"
        )
        Self.expectClose(group.layout, layout)
        for (member, frame) in zip(group.windows, frames) {
            #expect(
                framesMatch(member.frame, frame, tolerance: Self.frameTolerance),
                "the group recorded \(describe(member.frame)) for window \(member.windowNumber), it is measured at \(describe(frame))"
            )
        }
    }

    /// Checks that two layouts have the same orientation, the same rows (columns) and cells, with
    /// fractions within 0.003.
    static func expectClose(_ actual: TileLayout, _ expected: TileLayout) {
        let tolerance = 0.003
        guard actual.orientation == expected.orientation else {
            Issue.record("the group's layout is \(layoutText(actual)), expected \(layoutText(expected))")
            return
        }
        switch expected.orientation {
        case .rows:
            guard actual.rows.count == expected.rows.count,
                zip(actual.rows, expected.rows).allSatisfy({ $0.widths.count == $1.widths.count })
            else {
                Issue.record("the group's layout is \(layoutText(actual)), expected \(layoutText(expected))")
                return
            }
            for (row, wanted) in zip(actual.rows, expected.rows) {
                #expect(
                    abs(row.height - wanted.height) <= tolerance
                        && zip(row.widths, wanted.widths).allSatisfy { abs($0 - $1) <= tolerance },
                    "the group's row is \(row), expected \(wanted)")
            }
        case .columns:
            guard actual.columns.count == expected.columns.count,
                zip(actual.columns, expected.columns).allSatisfy({ $0.heights.count == $1.heights.count })
            else {
                Issue.record("the group's layout is \(layoutText(actual)), expected \(layoutText(expected))")
                return
            }
            for (column, wanted) in zip(actual.columns, expected.columns) {
                #expect(
                    abs(column.width - wanted.width) <= tolerance
                        && zip(column.heights, wanted.heights).allSatisfy { abs($0 - $1) <= tolerance },
                    "the group's column is \(column), expected \(wanted)")
            }
        }
    }

    /// A layout for a failure message: its rows or its columns.
    private static func layoutText(_ layout: TileLayout) -> String {
        switch layout.orientation {
        case .rows: return "rows \(layout.rows)"
        case .columns: return "columns \(layout.columns)"
        }
    }

    /// Checks that each window is still measured where it was (within one point).
    func expectUnmoved(_ windows: [FixtureWindow], at frames: [CGRect]) {
        run.expectUnmoved(windows, at: frames)
    }

    /// The measured frame of each window, for checking later that nothing moved.
    func measuredFrames(_ windows: [FixtureWindow]) throws -> [CGRect] {
        try windows.map { window in
            guard let frame = Measure.frame(ofWindow: window.windowNumber) else {
                throw AcceptanceFailure("window '\(window.id)' (\(window.windowNumber)) is not listed as on screen")
            }
            return frame
        }
    }

    // MARK: Layouts of the design table

    /// A single row with vertical dividers at these positions, as fractions of the width.
    static func row(dividers: [Double]) -> TileLayout {
        TileLayout(rows: [TileLayout.Row(height: 1, widths: fractions(dividers))])
    }

    /// A single column with horizontal dividers at these positions, as fractions of the height.
    static func column(dividers: [Double]) -> TileLayout {
        TileLayout(rows: fractions(dividers).map { TileLayout.Row(height: $0, widths: [1]) })
    }

    /// Two columns side by side with a vertical divider at `divider` (a fraction of the width). The left
    /// column holds `left` equal cells, the right one `right` equal cells, top to bottom.
    static func twoColumns(divider: Double, left: Int, right: Int) -> TileLayout {
        TileLayout(columns: [
            TileLayout.Column(width: divider, heights: Array(repeating: 1 / Double(left), count: left)),
            TileLayout.Column(width: 1 - divider, heights: Array(repeating: 1 / Double(right), count: right)),
        ])
    }

    /// The fractions between consecutive dividers, from 0 to 1.
    static func fractions(_ dividers: [Double]) -> [Double] {
        zip([0.0] + dividers, dividers + [1.0]).map { $1 - $0 }
    }
}
