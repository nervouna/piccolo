import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for pressing a half again (1/2, 2/3, 1/3) and for Restore Window, driven through
/// the installed Debug Piccolo on windows of the fixture app. Frames are measured in the window
/// server; the expected ones come from `PresetCycle` applied to the real displays.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Cycle and restore")
    struct CycleRestore {
        private let piccolo = PiccoloClient()

        // MARK: 1. Cycling

        @Test("cycle 1. leftHalf, run three times, reaches 1/2, 2/3 and 1/3 of the width, and a fourth run is back at 1/2")
        func leftHalfCycles() async throws {
            try await expectCycle(of: .leftHalf, alongWidth: true)
        }

        @Test("cycle 2. bottomHalf, run three times, reaches 1/2, 2/3 and 1/3 of the height, and a fourth run is back at 1/2")
        func bottomHalfCycles() async throws {
            try await expectCycle(of: .bottomHalf, alongWidth: false)
        }

        // MARK: 2. Restore

        @Test("restore 1. leftHalf, maximize, then restoreWindow puts the window back at its known frame and forgets it")
        func restoreAfterTwoActions() async throws {
            let screens = try Layout.screens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "restore", frame: start)
                let number = window.windowNumber

                let left = try #require(PresetCycle.frame(of: .leftHalf, step: 0, in: visible))
                _ = try piccolo.runAction(.placeWindow(.preset(.leftHalf)))
                _ = try await Measure.waitForFrame(ofWindow: number, matching: left)

                let maximize = FrameResolver.frame(for: .preset(.maximize), visibleFrame: visible, currentFrame: left)
                _ = try piccolo.runAction(.placeWindow(.preset(.maximize)))
                _ = try await Measure.waitForFrame(ofWindow: number, matching: maximize)

                let record = try #require(try history().first { $0.window == number })
                #expect(
                    framesMatch(record.origin, start),
                    "the record's origin is \(describe(record.origin)), the window started at \(describe(start))")
                #expect(framesMatch(record.lastAchieved, maximize))

                let result = try piccolo.runAction(.restoreWindow)
                guard case .placed = result else {
                    throw AcceptanceFailure("restoreWindow answered \(result), expected a placement")
                }
                _ = try await Measure.waitForFrame(ofWindow: number, matching: start)
                let remaining = try history().map(\.window)
                #expect(!remaining.contains(number), "history.list still lists window \(number): \(remaining)")
            }
        }

        @Test("restore 2. a window the user moved after Piccolo placed it has nothing to restore and stays where it is")
        func movedWindowHasNothingToRestore() async throws {
            let screens = try Layout.screens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let byHand = Layout.frame(in: screens[0], offset: CGPoint(x: 300, y: 200), size: CGSize(width: 500, height: 350))

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "restore-moved", frame: start)
                let number = window.windowNumber

                let left = try #require(PresetCycle.frame(of: .leftHalf, step: 0, in: visible))
                _ = try piccolo.runAction(.placeWindow(.preset(.leftHalf)))
                _ = try await Measure.waitForFrame(ofWindow: number, matching: left)

                _ = try piccolo.setFocusedFrame(byHand)
                _ = try await Measure.waitForFrame(ofWindow: number, matching: byHand)

                let result = try piccolo.runAction(.restoreWindow)
                #expect(result == .nothingToDo, "restoreWindow answered \(result)")
                _ = try await Measure.waitForFrame(ofWindow: number, matching: byHand)
                let remaining = try history().map(\.window)
                #expect(!remaining.contains(number), "the stale record of window \(number) is still listed")
            }
        }

        // MARK: 3. The destination preview shows the next step

        @Test("cycle 3. holding leftHalf over a window at the left half shows the highlight at 2/3 of the width, and the release moves it there")
        func previewShowsNextStep() async throws {
            let screens = try Layout.screens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let step0 = try #require(PresetCycle.frame(of: .leftHalf, step: 0, in: visible))
            let step1 = try #require(PresetCycle.frame(of: .leftHalf, step: 1, in: visible))
            let leftHalf = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: TestShortcut.f13)

            try await withConfigDirectory { config in
                try piccolo.loadConfig(at: try config.write([leftHalf]))
                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "cycle-preview", frame: start)
                    _ = try piccolo.setFocusedFrame(step0)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: step0)

                    try piccolo.pressHotkey(leftHalf.id)

                    let state = try await eventually(
                        "preview.state to be visible at 2/3 of the width \(describe(step1))", timeout: 5
                    ) { () -> Observation<PiccoloClient.PreviewState> in
                        let state = try piccolo.previewState()
                        guard state.visible, state.frames.count == 1, framesMatch(state.frames[0], step1) else {
                            return .unsatisfied(
                                "visible: \(state.visible), frames: \(state.frames.map(describe)), planning error: \(state.planningError ?? "none")"
                            )
                        }
                        return .satisfied(state)
                    }
                    #expect(
                        approximatelyEqual(state.frames[0].width, visible.width * 2 / 3),
                        "the highlight is \(state.frames[0].width) wide, 2/3 of \(visible.width) is \(visible.width * 2 / 3)")
                    let held = Measure.frame(ofWindow: window.windowNumber)
                    #expect(
                        held.map { framesMatch($0, step0) } == true,
                        "the window moved to \(held.map { describe($0) } ?? "nowhere") while the shortcut was held")

                    try piccolo.releaseHotkey(leftHalf.id)

                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: step1)
                }
            }
        }

        // MARK: Helpers

        /// Runs `preset` four times on a fixture window and checks that it reaches 1/2, 2/3, 1/3 and 1/2
        /// of the visible frame along its axis.
        private func expectCycle(of preset: Preset, alongWidth: Bool) async throws {
            let screens = try Layout.screens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3, 1.0 / 2]
            let full = alongWidth ? visible.width : visible.height

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "cycle-\(preset.rawValue)", frame: start)

                for (round, fraction) in fractions.enumerated() {
                    let expected = try #require(PresetCycle.frame(of: preset, step: round % 3, in: visible))
                    let result = try piccolo.runAction(.placeWindow(.preset(preset)))
                    guard case .placed = result else {
                        throw AcceptanceFailure("run \(round + 1) of \(preset.rawValue) answered \(result)")
                    }
                    let measured = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
                    let along = alongWidth ? measured.width : measured.height
                    #expect(
                        approximatelyEqual(along, full * fraction),
                        "run \(round + 1) of \(preset.rawValue): \(alongWidth ? "width" : "height") is \(along), \(fraction) of \(full) is \(full * fraction)"
                    )
                }
            }
        }

        private struct HistoryEntry {
            var window: Int
            var origin: CGRect
            var lastAchieved: CGRect
        }

        /// `history.list`: the window records Piccolo holds.
        private func history() throws -> [HistoryEntry] {
            let result = try piccolo.send("history.list")
            guard let entries = result.arrayValue else {
                throw AcceptanceFailure("Piccolo's history.list answer is not a list: \(result)")
            }
            return try entries.map { entry in
                guard let window = entry["window"]?.intValue, let origin = entry["origin"]?.rectValue,
                    let achieved = entry["lastAchieved"]?.rectValue
                else {
                    throw AcceptanceFailure("a history.list entry is malformed: \(entry)")
                }
                return HistoryEntry(window: window, origin: origin, lastAchieved: achieved)
            }
        }

        /// Opens a window at `frame`, waits until it is there and brings it into focus, which is what an
        /// action acts on.
        private func openFocused(_ fixture: FixtureApp, id: String, frame: CGRect) async throws -> FixtureWindow {
            let window = try fixture.open(id: id, frame: frame)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
            try await Focus.bring(window, of: fixture)
            return window
        }
    }
}
