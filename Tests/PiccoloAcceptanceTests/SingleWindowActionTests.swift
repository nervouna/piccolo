import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for `action.run` with the single-window actions: `placeWindow` and
/// `moveToDisplay`, driven through the installed Debug Piccolo on windows of the fixture app.
///
/// Expected frames come from `PiccoloCore` (`FrameResolver`, `DisplayLayout`) applied to the real
/// displays, so these tests check the wiring: the focused window, the displays, the Accessibility
/// calls. Wherever the outcome has a shape that does not depend on how edges round (a shared edge,
/// the visible frame covered, the size kept, the window inside the display), that is asserted
/// directly as well. Every frame is measured in the window server, never taken from a response.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Single-window actions")
    struct SingleWindowActions {
        private let piccolo = PiccoloClient()

        // MARK: 1. Presets on the primary display

        @Test("actions 1. every preset on the primary display lands on its resolved frame")
        func everyPresetOnThePrimaryDisplay() async throws {
            let (screens, _) = try await loadScreens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "presets", frame: start)

                var measured: [Preset: CGRect] = [:]
                for preset in Preset.allCases {
                    measured[preset] = try await place(
                        .preset(preset), window: window, from: start, within: visible, label: preset.rawValue)
                }

                // The shape of the results, whatever the rounding.
                let maximize = try #require(measured[.maximize])
                #expect(
                    framesMatch(maximize, visible),
                    "maximize is measured at \(describe(maximize)), the visible frame is \(describe(visible))")

                let left = try #require(measured[.leftHalf])
                let right = try #require(measured[.rightHalf])
                #expect(
                    approximatelyEqual(left.maxX, right.minX),
                    "leftHalf ends at x \(left.maxX) but rightHalf starts at x \(right.minX): they should share an edge")
                #expect(
                    approximatelyEqual(left.minX, visible.minX) && approximatelyEqual(right.maxX, visible.maxX),
                    "together the halves span x \(left.minX) to \(right.maxX), the visible frame spans \(visible.minX) to \(visible.maxX)"
                )
                #expect(
                    [left, right].allSatisfy {
                        approximatelyEqual($0.minY, visible.minY) && approximatelyEqual($0.maxY, visible.maxY)
                    },
                    "the halves are \(describe(left)) and \(describe(right)), both should be as tall as the visible frame \(describe(visible))"
                )

                let center = try #require(measured[.center])
                #expect(
                    sizesMatch(center.size, start.size),
                    "center changed the size from \(describe(start.size)) to \(describe(center.size))")
                #expect(
                    approximatelyEqual(center.midX, visible.midX) && approximatelyEqual(center.midY, visible.midY),
                    "center is measured at \(describe(center)), its middle should be the visible frame's middle (\(visible.midX), \(visible.midY))"
                )
            }
        }

        // MARK: 2. Presets on the second display

        @Test(
            "actions 2. leftHalf, bottomRight and maximize on the second display keep the window on that display",
            .enabled(if: Acceptance.displayCount >= 2, "needs two or more displays")
        )
        func presetsOnTheSecondDisplay() async throws {
            let (screens, displays) = try await loadScreens()
            guard let second = screens.first(where: { !$0.isPrimary }) else {
                throw AcceptanceFailure("the display list has no second display: \(screens)")
            }
            let visible = second.visibleFrame
            let size = CGSize(
                width: min(640, visible.width - 160), height: min(420, visible.height - 160))
            let start = Layout.frame(in: second, offset: CGPoint(x: 80, y: 80), size: size)

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "second-display", frame: start)

                for preset in [Preset.leftHalf, .bottomRight, .maximize] {
                    let measured = try await place(
                        .preset(preset), window: window, from: start, within: visible, label: preset.rawValue)

                    #expect(
                        DisplayLayout.index(containing: measured, in: displays) == second.index,
                        "\(preset.rawValue) left the second display: measured \(describe(measured))")
                    #expect(
                        inside(measured, visible),
                        "\(preset.rawValue) is measured at \(describe(measured)), outside the second display's visible frame \(describe(visible))"
                    )
                }
            }
        }

        // MARK: 3. A custom frame

        @Test("actions 3. a custom frame is resolved against the visible frame")
        func customFrame() async throws {
            let (screens, _) = try await loadScreens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let rect = FractionalRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "custom", frame: start)

                let measured = try await place(
                    .custom(rect), window: window, from: start, within: visible, label: "custom")

                // The fractions of the visible frame, to within the rounding of the two edges.
                let expected = CGRect(
                    x: visible.minX + 0.25 * visible.width, y: visible.minY + 0.1 * visible.height,
                    width: 0.5 * visible.width, height: 0.8 * visible.height)
                #expect(
                    framesMatch(measured, expected, tolerance: 1.5),
                    "the custom frame is measured at \(describe(measured)), the fractions of \(describe(visible)) give \(describe(expected))"
                )
            }
        }

        // MARK: 4. moveToDisplay

        @Test(
            "actions 4. moveToDisplay next lands on the other display, previous brings the window back",
            .enabled(if: Acceptance.displayCount >= 2, "needs two or more displays")
        )
        func moveToDisplay() async throws {
            let (_, displays) = try await loadScreens()
            let sourceIndex = 0
            let source = displays[sourceIndex]
            let targetIndex = DisplayLayout.neighbor(of: sourceIndex, .next, in: displays)
            let target = displays[targetIndex]
            let original = try roundTripFrame(on: source, via: target)

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "traveller", frame: original)

                // next: the frame DisplayLayout predicts on the other display.
                let predicted = DisplayLayout.frame(moving: original, from: source, to: target)
                let next = try piccolo.runAction(.moveToDisplay(.next))
                let nextFrames = try placedFrames(next, "moveToDisplay next")
                #expect(
                    framesMatch(nextFrames.target, predicted),
                    "moveToDisplay next answered the target \(describe(nextFrames.target)), DisplayLayout predicts \(describe(predicted))"
                )
                let moved = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: predicted)
                #expect(
                    DisplayLayout.index(containing: moved, in: displays) == targetIndex,
                    "the window is measured at \(describe(moved)), not on display \(targetIndex) (\(describe(target.frame)))"
                )
                #expect(
                    inside(moved, target.visibleFrame),
                    "the window is measured at \(describe(moved)), outside the other display's visible frame \(describe(target.visibleFrame))"
                )

                // previous: back at the original frame, within the measurement tolerance.
                let previous = try piccolo.runAction(.moveToDisplay(.previous))
                _ = try placedFrames(previous, "moveToDisplay previous")
                let back = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: original)
                #expect(
                    DisplayLayout.index(containing: back, in: displays) == sourceIndex,
                    "the window is measured at \(describe(back)), not back on display \(sourceIndex)")

                // A maximized window lands exactly on the other display's visible frame.
                _ = try piccolo.setFocusedFrame(source.visibleFrame)
                _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: source.visibleFrame)
                let maximized = try piccolo.runAction(.moveToDisplay(.next))
                let maximizedFrames = try placedFrames(maximized, "moveToDisplay next (maximized)")
                #expect(
                    framesMatch(maximizedFrames.target, target.visibleFrame),
                    "the target for a maximized window is \(describe(maximizedFrames.target)), the other display's visible frame is \(describe(target.visibleFrame))"
                )
                _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: target.visibleFrame)
            }
        }

        // MARK: 5. A window that refuses to get narrower

        @Test("actions 5. a window with a minimum width wider than a third gets that width, inside the display")
        func minimumWidthWiderThanAThird() async throws {
            let (screens, _) = try await loadScreens()
            // The narrowest display is the one where a third is most likely to be under the minimum.
            let screen = narrowest(of: screens)
            let visible = screen.visibleFrame
            // 900 × 600, or a little more than a third where a third is already wider than that.
            let minimum = CGSize(width: max(900, (visible.width / 3).rounded(.up) + 100), height: 600)
            let start = try startFrame(for: minimum, on: screen)

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "min-third", frame: start, minSize: minimum)

                let result = try piccolo.runAction(.placeWindow(.preset(.leftThird)))
                let frames = try placedFrames(result, "leftThird")
                let wanted = FrameResolver.frame(
                    for: .preset(.leftThird), visibleFrame: visible, currentFrame: start)

                #expect(
                    framesMatch(frames.target, wanted),
                    "the response targets \(describe(frames.target)), a third of the visible frame is \(describe(wanted))"
                )
                #expect(
                    wanted.width < minimum.width,
                    "this test needs a third (\(wanted.width) wide) narrower than the minimum (\(minimum.width))")
                #expect(
                    approximatelyEqual(frames.achieved.width, minimum.width),
                    "the response reports the achieved width \(frames.achieved.width), the window's minimum is \(minimum.width)"
                )

                let measured = try await Measure.waitForFrame(
                    ofWindow: window.windowNumber, matching: frames.achieved)
                #expect(
                    approximatelyEqual(measured.width, minimum.width),
                    "the window is measured \(describe(measured.size)) wide, its minimum is \(describe(minimum))")
                #expect(
                    inside(measured, visible),
                    "the window is measured at \(describe(measured)), outside the visible frame \(describe(visible))"
                )
            }
        }

        // MARK: 6. A window that would stick out of the display

        @Test("actions 6. a window with a minimum width wider than a half is shifted left to lie inside the display")
        func minimumWidthWiderThanAHalf() async throws {
            let (screens, _) = try await loadScreens()
            let screen = narrowest(of: screens)
            let visible = screen.visibleFrame
            let minimum = CGSize(width: max(900, (visible.width / 2).rounded(.up) + 100), height: 600)
            let start = try startFrame(for: minimum, on: screen)

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "min-half", frame: start, minSize: minimum)

                let result = try piccolo.runAction(.placeWindow(.preset(.rightHalf)))
                let frames = try placedFrames(result, "rightHalf")
                let wanted = FrameResolver.frame(
                    for: .preset(.rightHalf), visibleFrame: visible, currentFrame: start)

                #expect(
                    framesMatch(frames.target, wanted),
                    "the response targets \(describe(frames.target)), the right half of the visible frame is \(describe(wanted))"
                )
                #expect(
                    wanted.width < minimum.width,
                    "this test needs a half (\(wanted.width) wide) narrower than the minimum (\(minimum.width))")
                #expect(
                    approximatelyEqual(frames.achieved.width, minimum.width),
                    "the response reports the achieved width \(frames.achieved.width), the window's minimum is \(minimum.width)"
                )
                #expect(
                    frames.achieved.minX < frames.target.minX,
                    "the window was not shifted left: the target starts at x \(frames.target.minX), the response reports \(describe(frames.achieved))"
                )

                let measured = try await Measure.waitForFrame(
                    ofWindow: window.windowNumber, matching: frames.achieved)
                #expect(
                    inside(measured, visible),
                    "the window is measured at \(describe(measured)), outside the visible frame \(describe(visible))"
                )
                #expect(
                    approximatelyEqual(measured.maxX, visible.maxX),
                    "the window ends at x \(measured.maxX), flush with the right edge of the visible frame means \(visible.maxX)"
                )
            }
        }

        // MARK: 7. A fixed-size window

        @Test("actions 7. a window that cannot be resized is moved and keeps its size")
        func fixedSizeWindow() async throws {
            let (screens, _) = try await loadScreens()
            let visible = screens[0].visibleFrame
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "fixed", frame: start, resizable: false)

                // center: centred, size unchanged.
                let centered = FrameResolver.frame(
                    for: .preset(.center), visibleFrame: visible, currentFrame: start)
                let center = try piccolo.runAction(.placeWindow(.preset(.center)))
                let centerFrames = try placedFrames(center, "center")
                #expect(
                    framesMatch(centerFrames.target, centered) && framesMatch(centerFrames.achieved, centered),
                    "center answered target \(describe(centerFrames.target)) and achieved \(describe(centerFrames.achieved)), expected \(describe(centered))"
                )
                let measuredCenter = try await Measure.waitForFrame(
                    ofWindow: window.windowNumber, matching: centered)
                #expect(
                    sizesMatch(measuredCenter.size, start.size),
                    "center changed the fixed size from \(describe(start.size)) to \(describe(measuredCenter.size))")
                #expect(
                    approximatelyEqual(measuredCenter.midX, visible.midX)
                        && approximatelyEqual(measuredCenter.midY, visible.midY),
                    "the window is centred at (\(measuredCenter.midX), \(measuredCenter.midY)), the visible frame's middle is (\(visible.midX), \(visible.midY))"
                )

                // leftHalf: the origin of the half, the window's own size.
                let half = FrameResolver.frame(
                    for: .preset(.leftHalf), visibleFrame: visible, currentFrame: centered)
                let expected = CGRect(origin: half.origin, size: start.size)
                let left = try piccolo.runAction(.placeWindow(.preset(.leftHalf)))
                let leftFrames = try placedFrames(left, "leftHalf")
                #expect(
                    framesMatch(leftFrames.target, half),
                    "leftHalf targets \(describe(leftFrames.target)), the resolved frame is \(describe(half))")
                #expect(
                    framesMatch(leftFrames.achieved, expected),
                    "leftHalf achieved \(describe(leftFrames.achieved)), a fixed-size window should end up at \(describe(expected))"
                )
                let measuredLeft = try await Measure.waitForFrame(
                    ofWindow: window.windowNumber, matching: expected)
                #expect(
                    sizesMatch(measuredLeft.size, start.size),
                    "leftHalf changed the fixed size from \(describe(start.size)) to \(describe(measuredLeft.size))")
            }
        }

        // MARK: 8. Actions that are refused

        @Test("actions 8. arrangeGrid and malformed params are refused, and the window stays put")
        func refusedActions() async throws {
            let (screens, _) = try await loadScreens()
            let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))

            // Each request, the words its refusal must contain.
            let requests: [(name: String, params: [String: JSONValue], words: [String])] = [
                (
                    "arrangeGrid",
                    ["type": "arrangeGrid", "count": 4, "rows": 2, "columns": 2],
                    ["not implemented"]
                ),
                (
                    "moveDivider",
                    ["type": "moveDivider", "direction": "left"],
                    ["not implemented"]
                ),
                ("no type", [:], ["type"]),
                ("unknown type", ["type": "teleport"], ["teleport"]),
                ("no frame", ["type": "placeWindow"], ["frame"]),
                (
                    "unknown preset",
                    ["type": "placeWindow", "frame": ["preset": "diagonal"]],
                    ["diagonal"]
                ),
                (
                    "wrong type of a field",
                    ["type": "arrangeGrid", "count": "four", "rows": 2, "columns": 2],
                    ["count"]
                ),
                (
                    "custom frame off the screen",
                    ["type": "placeWindow", "frame": ["custom": ["x": 0.5, "y": 0, "width": 0.75, "height": 1]]],
                    ["x + width"]
                ),
            ]

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "stay-put", frame: start)

                for request in requests {
                    let message = try piccolo.runActionExpectingRefusal(params: request.params)
                    for word in request.words {
                        #expect(
                            message.contains(word),
                            "the refusal of '\(request.name)' is \"\(message)\", it should mention \"\(word)\"")
                    }

                    // The answer comes after the action ran (or did not), so one look is enough.
                    let measured = Measure.frame(ofWindow: window.windowNumber)
                    #expect(
                        measured.map { framesMatch($0, start) } == true,
                        "after the refused '\(request.name)' the window is measured at \(measured.map { describe($0) } ?? "nowhere"), it should still be at \(describe(start))"
                    )
                    let seen = try piccolo.focusedWindow().frame
                    #expect(
                        framesMatch(seen, start),
                        "after the refused '\(request.name)' Piccolo sees the focused window at \(describe(seen)), it should still be at \(describe(start))"
                    )
                }
            }
        }

        // MARK: Helpers

        private func loadScreens() async throws -> (screens: [ScreenInfo], displays: [Display]) {
            let screens = try await MainActor.run { try Layout.screens() }
            return (screens, Screens.displays(from: screens))
        }

        /// Opens a window at `frame`, waits until it is there and brings it into focus, which is
        /// what a Piccolo action acts on.
        private func openFocused(
            _ fixture: FixtureApp, id: String, frame: CGRect, minSize: CGSize? = nil, resizable: Bool? = nil
        ) async throws -> FixtureWindow {
            let window = try fixture.open(id: id, frame: frame, minSize: minSize, resizable: resizable)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
            try await Focus.bring(window, of: fixture)
            return window
        }

        /// Puts the window back at `start`, places it with `spec` and checks the response against
        /// the frame `FrameResolver` computes for the same inputs. Returns the measured frame.
        private func place(
            _ spec: FrameSpec, window: FixtureWindow, from start: CGRect, within visible: CGRect, label: String
        ) async throws -> CGRect {
            do {
                // Every placement starts from the same frame, so that `center` has a known size.
                _ = try piccolo.setFocusedFrame(start)
                _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)

                let expected = FrameResolver.frame(for: spec, visibleFrame: visible, currentFrame: start)
                let result = try piccolo.runAction(.placeWindow(spec))
                let frames = try placedFrames(result, label)
                #expect(
                    framesMatch(frames.target, expected),
                    "\(label): the response targets \(describe(frames.target)), FrameResolver gives \(describe(expected))"
                )
                #expect(
                    framesMatch(frames.achieved, expected),
                    "\(label): the response reports \(describe(frames.achieved)) as achieved, expected \(describe(expected))"
                )
                return try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: expected)
            } catch let failure as AcceptanceFailure {
                throw AcceptanceFailure("\(label): \(failure.message)", isRetryable: failure.isRetryable)
            }
        }

        private func placedFrames(
            _ result: PiccoloClient.ActionResult, _ label: String
        ) throws -> (target: CGRect, achieved: CGRect) {
            guard case .placed(let target, let achieved) = result else {
                throw AcceptanceFailure("\(label) answered \(result), expected a target and an achieved frame")
            }
            return (target, achieved)
        }

        /// Whether `frame` lies inside `visible`, within the measurement tolerance.
        private func inside(_ frame: CGRect, _ visible: CGRect) -> Bool {
            visible.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
        }

        private func narrowest(of screens: [ScreenInfo]) -> ScreenInfo {
            screens.min { $0.visibleFrame.width < $1.visibleFrame.width } ?? screens[0]
        }

        /// A frame for a window that is at least `minimum` large, inside the display with some room
        /// around it. Skips the test when the display is too small to hold such a window.
        private func startFrame(for minimum: CGSize, on screen: ScreenInfo) throws -> CGRect {
            let margin: CGFloat = 40
            guard screen.visibleFrame.width >= minimum.width + 2 * margin,
                screen.visibleFrame.height >= minimum.height + 2 * margin
            else {
                try Test.cancel(
                    "the narrowest display (\(describe(screen.visibleFrame.size))) is too small for a window of \(describe(minimum))"
                )
            }
            return Layout.frame(in: screen, offset: CGPoint(x: margin, y: margin), size: minimum)
        }

        /// A window frame on `source` that returns to itself, within the measurement tolerance,
        /// after moving to `other` and back. Both moves round to whole points, so on displays of
        /// different sizes only some frames survive the round trip within one point; this picks the
        /// first one from a range of ordinary window sizes and places.
        private func roundTripFrame(on source: Display, via other: Display) throws -> CGRect {
            let visible = source.visibleFrame
            for width in stride(from: CGFloat(640), through: 760, by: 10) {
                for height in stride(from: CGFloat(420), through: 520, by: 10) {
                    for dx in 100...160 {
                        for dy in 60...120 {
                            let frame = CGRect(
                                x: visible.minX + CGFloat(dx), y: visible.minY + CGFloat(dy),
                                width: width, height: height)
                            guard visible.contains(frame) else { continue }
                            let there = DisplayLayout.frame(moving: frame, from: source, to: other)
                            let back = DisplayLayout.frame(moving: there, from: other, to: source)
                            if other.visibleFrame.contains(there), framesMatch(back, frame) {
                                return frame
                            }
                        }
                    }
                }
            }
            throw AcceptanceFailure(
                "no window frame on \(describe(visible)) survives a round trip to \(describe(other.visibleFrame)) within \(frameTolerance) pt"
            )
        }
    }
}
