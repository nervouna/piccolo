import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for the window gap, driven through the installed Debug Piccolo on windows of the
/// fixture app, with a temporary config that sets `gap: 12`. The expected frames are derived from the
/// display Piccolo reports, with the rule written out here: an edge on the visible frame's edge is
/// `gap` inside it, an edge shared with a neighbour `gap / 2` inside the divider. They are compared
/// with the measured frames within 1 pt.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Window gap")
    struct WindowGap {
        private let piccolo = PiccoloClient()
        private static let gap: CGFloat = 12

        // MARK: Expected frames

        /// The frame between these edges, as the rule gives it.
        private static func frame(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) -> CGRect {
            CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }

        /// A window on the left of a divider at `divider` (x), full height: `gap` to the left, top and
        /// bottom edges and half of it to the divider.
        private static func leftOf(_ divider: CGFloat, in v: CGRect) -> CGRect {
            frame(left: v.minX + gap, top: v.minY + gap, right: divider - gap / 2, bottom: v.maxY - gap)
        }

        /// A window on the right of a divider at `divider` (x), full height.
        private static func rightOf(_ divider: CGFloat, in v: CGRect) -> CGRect {
            frame(left: divider + gap / 2, top: v.minY + gap, right: v.maxX - gap, bottom: v.maxY - gap)
        }

        // MARK: Running

        /// Runs `body` with a temporary config of this gap (and the default step, no bindings), a fixture
        /// with no windows, and the display under test.
        private func withGap<Result>(
            _ gap: Int, _ body: (FixtureApp, ScreenInfo) async throws -> Result
        ) async throws -> Result {
            let screen = try Layout.screens()[0]
            return try await withConfigDirectory { directory in
                try piccolo.loadConfig(at: try directory.write(Config.frameTest(gap: gap)))
                return try await withFixture { fixture in try await body(fixture, screen) }
            }
        }

        private func openFocused(
            _ fixture: FixtureApp, id: String, on screen: ScreenInfo, index: Int = 0
        ) async throws -> FixtureWindow {
            let frame = ArrangeRun.cascadeFrame(index, on: screen)
            let window = try fixture.open(id: id, frame: frame)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
            try await Focus.bring(window, of: fixture)
            return window
        }

        private func place(_ preset: Preset, expecting expected: CGRect, window: FixtureWindow) async throws -> CGRect {
            let result = try piccolo.runAction(.placeWindow(.preset(preset)))
            guard case .placed = result else {
                throw AcceptanceFailure("\(preset.rawValue) answered \(result), expected a placement")
            }
            return try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
        }

        // MARK: 1. Halves

        @Test("gap 1. leftHalf is 12 pt from the left, top and bottom edges and 6 pt left of the middle; rightHalf on a second window leaves 12 pt between them")
        func halves() async throws {
            try await withGap(12) { fixture, screen in
                let v = screen.visibleFrame
                let first = try await openFocused(fixture, id: "gap-left", on: screen)
                let second = try await openFocused(fixture, id: "gap-right", on: screen, index: 1)

                try await Focus.bring(first, of: fixture)
                let leftExpected = Self.leftOf(v.minX + v.width / 2, in: v)
                let left = try await place(.leftHalf, expecting: leftExpected, window: first)
                #expect(approximatelyEqual(left.minX - v.minX, 12), "left edge is \(left.minX - v.minX) pt from the visible frame")
                #expect(approximatelyEqual(left.minY - v.minY, 12), "top edge is \(left.minY - v.minY) pt from the visible frame")
                #expect(approximatelyEqual(v.maxY - left.maxY, 12), "bottom edge is \(v.maxY - left.maxY) pt from the visible frame")
                #expect(approximatelyEqual(v.midX - left.maxX, 6), "right edge is \(v.midX - left.maxX) pt left of the middle")

                try await Focus.bring(second, of: fixture)
                let rightExpected = Self.rightOf(v.minX + v.width / 2, in: v)
                let right = try await place(.rightHalf, expecting: rightExpected, window: second)
                #expect(approximatelyEqual(right.minX - left.maxX, 12), "the windows are \(right.minX - left.maxX) pt apart")
                #expect(approximatelyEqual(v.maxX - right.maxX, 12), "right window is \(v.maxX - right.maxX) pt from the right edge")
            }
        }

        // MARK: 2. Maximize

        @Test("gap 2. maximize is 12 pt from every edge of the visible frame")
        func maximize() async throws {
            try await withGap(12) { fixture, screen in
                let v = screen.visibleFrame
                let window = try await openFocused(fixture, id: "gap-max", on: screen)
                let expected = Self.frame(left: v.minX + 12, top: v.minY + 12, right: v.maxX - 12, bottom: v.maxY - 12)
                let measured = try await place(.maximize, expecting: expected, window: window)
                #expect(approximatelyEqual(measured.minX - v.minX, 12) && approximatelyEqual(v.maxX - measured.maxX, 12))
                #expect(approximatelyEqual(measured.minY - v.minY, 12) && approximatelyEqual(v.maxY - measured.maxY, 12))
            }
        }

        // MARK: 3. Cycling

        @Test("gap 3. leftHalf three times reaches the gapped 1/2, 2/3 and 1/3, and the fourth press is back at 1/2")
        func cycle() async throws {
            try await withGap(12) { fixture, screen in
                let v = screen.visibleFrame
                let window = try await openFocused(fixture, id: "gap-cycle", on: screen)
                let dividers: [CGFloat] = [v.minX + v.width / 2, v.minX + v.width * 2 / 3, v.minX + v.width / 3, v.minX + v.width / 2]
                for (round, divider) in dividers.enumerated() {
                    let expected = Self.leftOf(divider, in: v)
                    let measured = try await place(.leftHalf, expecting: expected, window: window)
                    #expect(
                        approximatelyEqual(measured.maxX, divider - 6),
                        "press \(round + 1): the right edge is at \(measured.maxX), 6 pt left of the divider at \(divider) is \(divider - 6)"
                    )
                }
            }
        }

        // MARK: 4. Arrangement and divider move

        @Test("gap 4. arrangeGrid of two windows in 1 × 2 leaves 12 pt between them and to the edges, and moveDivider right keeps the 12 pt")
        func arrangeAndMove() async throws {
            try await withGap(12) { fixture, screen in
                let v = screen.visibleFrame
                let run = ArrangeRun(fixture: fixture)
                let windows = try await run.open(["gap-a", "gap-b"], on: screen)
                try await run.focus(windows.reversed())

                let grid = GridSpec(count: 2, rows: 1, columns: 2)
                let result = try run.arrange(grid)
                guard case .arranged(_, let reported) = result, reported.count == 2 else {
                    throw AcceptanceFailure("arrangeGrid answered \(result), expected an arrangement of two windows")
                }
                let divider = v.minX + v.width / 2
                let first = try await Measure.waitForFrame(
                    ofWindow: windows[0].windowNumber, matching: Self.leftOf(divider, in: v))
                let second = try await Measure.waitForFrame(
                    ofWindow: windows[1].windowNumber, matching: Self.rightOf(divider, in: v))
                #expect(approximatelyEqual(second.minX - first.maxX, 12), "the windows are \(second.minX - first.maxX) pt apart")
                #expect(approximatelyEqual(first.minX - v.minX, 12) && approximatelyEqual(v.maxX - second.maxX, 12))
                #expect(approximatelyEqual(first.minY - v.minY, 12) && approximatelyEqual(v.maxY - first.maxY, 12))

                // The first window is focused (the most recent); the divider moves right by the step.
                try await Focus.bring(windows[0], of: fixture)
                let step = Config.defaultResizeStep
                let moved = try piccolo.moveDivider(.right, onlyPid: try fixture.processID())
                guard case .moved = moved else {
                    throw AcceptanceFailure("moveDivider right answered \(moved), expected the divider to move")
                }
                let newDivider = divider + v.width * CGFloat(step)
                let firstAfter = try await Measure.waitForFrame(
                    ofWindow: windows[0].windowNumber, matching: Self.leftOf(newDivider, in: v))
                let secondAfter = try await Measure.waitForFrame(
                    ofWindow: windows[1].windowNumber, matching: Self.rightOf(newDivider, in: v))
                #expect(
                    approximatelyEqual(secondAfter.minX - firstAfter.maxX, 12),
                    "after the divider move the windows are \(secondAfter.minX - firstAfter.maxX) pt apart")
                #expect(approximatelyEqual(firstAfter.minX - v.minX, 12) && approximatelyEqual(v.maxX - secondAfter.maxX, 12))
            }
        }

        // MARK: 5. Settings

        @Test("gap 6. settings.setGap saves the gap and settings.state reports it; a gap of 65 is rejected with the model's message")
        func settingsGap() async throws {
            try await withSettingsSession { session in
                #expect(try piccolo.settingsState().gap == 0)

                let state = try piccolo.settingsSetGap(20)
                #expect(state.gap == 20)
                #expect(try session.fileConfig().gap == 20)
                let saved = try session.fileBytes()

                let message = try piccolo.settingsSetGapExpectingRejection(65)
                let expected = try InterfaceTexts.current(piccolo).message(
                    for: .outOfRange(field: "gap", rule: "must be a whole number from 0 to 64"))
                #expect(message == expected, "the message is \"\(message)\", expected \"\(expected)\"")
                #expect(try session.fileBytes() == saved, "the rejected gap changed the file")
                #expect(try piccolo.settingsState().gap == 20)
            }
        }

        // MARK: 6. Gap 0

        @Test("gap 5. with gap 0 in the config leftHalf gives exactly today's frame")
        func zeroGap() async throws {
            try await withGap(0) { fixture, screen in
                let v = screen.visibleFrame
                let window = try await openFocused(fixture, id: "gap-zero", on: screen)
                let expected = Self.frame(left: v.minX, top: v.minY, right: v.minX + v.width / 2, bottom: v.maxY)
                let measured = try await place(.leftHalf, expecting: expected, window: window)
                #expect(approximatelyEqual(measured.minX, v.minX) && approximatelyEqual(measured.minY, v.minY))
                #expect(approximatelyEqual(measured.width, v.width / 2) && approximatelyEqual(measured.height, v.height))
            }
        }
    }
}
