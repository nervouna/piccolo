import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// The executor against a fake window and fake displays: two displays, the secondary to the left of
/// the primary and smaller. Expected frames are computed with `PiccoloCore`, not written down, so that
/// the tests do not depend on how edges round.
private enum Rig {
    static let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 0, y: 30, width: 1550, height: 970))
    static let secondary = Display(
        frame: CGRect(x: -1200, y: 200, width: 1200, height: 800),
        visibleFrame: CGRect(x: -1200, y: 230, width: 1200, height: 770))
    static let both = [primary, secondary]

    static let onPrimary = CGRect(x: 100, y: 100, width: 600, height: 400)
    static let onSecondary = CGRect(x: -1100, y: 300, width: 500, height: 300)

    static func window(at frame: CGRect) -> FakeWindow {
        FakeWindow(frame: frame, displays: both.map(\.frame))
    }
}

/// Counts how often the executor asks for a window or for the displays.
private final class Calls: @unchecked Sendable {
    var windows = 0
    var displays = 0
}

private func executor(
    window: FakeWindow, displays: [Display] = Rig.both, calls: Calls = Calls()
) -> ActionExecutor {
    ActionExecutor(
        window: {
            calls.windows += 1
            return window
        },
        displays: {
            calls.displays += 1
            return displays
        })
}

@Suite("ActionExecutor: placeWindow")
struct ExecutorPlaceWindowTests {
    @Test("a preset moves the window to the resolved frame and reports target and achieved", arguments: Preset.allCases)
    func presets(preset: Preset) throws {
        let window = Rig.window(at: Rig.onPrimary)

        let outcome = try executor(window: window).run(.placeWindow(.preset(preset)))

        let expected = FrameResolver.frame(
            for: .preset(preset), visibleFrame: Rig.primary.visibleFrame, currentFrame: Rig.onPrimary)
        #expect(outcome == .placed(target: expected, achieved: expected))
        #expect(try window.frame() == expected)
    }

    @Test("a custom frame is resolved against the display the window is on")
    func customFrame() throws {
        let window = Rig.window(at: Rig.onSecondary)
        let rect = FractionalRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)

        let outcome = try executor(window: window).run(.placeWindow(.custom(rect)))

        let expected = FrameResolver.frame(
            for: .custom(rect), visibleFrame: Rig.secondary.visibleFrame, currentFrame: Rig.onSecondary)
        #expect(outcome == .placed(target: expected, achieved: expected))
        #expect(try window.frame() == expected)
    }

    @Test("a window that refuses the size is reported with what it achieved, shifted inside the display")
    func minimumSizeShiftedInside() throws {
        // A third of the secondary display is 400 pt wide; this window is at least 700 pt wide.
        let window = Rig.window(at: Rig.onSecondary)
        window.minimumSize = CGSize(width: 700, height: 400)

        let outcome = try executor(window: window).run(.placeWindow(.preset(.rightThird)))

        let target = FrameResolver.frame(
            for: .preset(.rightThird), visibleFrame: Rig.secondary.visibleFrame, currentFrame: Rig.onSecondary)
        guard case .placed(let reportedTarget, let achieved) = outcome else {
            Issue.record("expected a placement, got \(outcome)")
            return
        }
        #expect(reportedTarget == target)
        #expect(achieved.width == 700)
        #expect(achieved.height == target.height)
        #expect(Rig.secondary.visibleFrame.contains(achieved))
        #expect(achieved.maxX == Rig.secondary.visibleFrame.maxX)
        #expect(try window.frame() == achieved)
    }

    @Test("a fixed-size window is moved with its size unchanged")
    func fixedSize() throws {
        let window = Rig.window(at: Rig.onPrimary)
        window.isFixedSize = true

        let center = try executor(window: window).run(.placeWindow(.preset(.center)))
        let centered = FrameResolver.frame(
            for: .preset(.center), visibleFrame: Rig.primary.visibleFrame, currentFrame: Rig.onPrimary)
        #expect(center == .placed(target: centered, achieved: centered))
        #expect(try window.frame().size == Rig.onPrimary.size)

        let left = try executor(window: window).run(.placeWindow(.preset(.leftHalf)))
        let target = FrameResolver.frame(
            for: .preset(.leftHalf), visibleFrame: Rig.primary.visibleFrame, currentFrame: centered)
        #expect(
            left
                == .placed(
                    target: target,
                    achieved: CGRect(origin: target.origin, size: Rig.onPrimary.size)))
    }

    @Test("an invalid custom frame is rejected before the window is touched")
    func invalidCustomFrame() {
        let window = Rig.window(at: Rig.onPrimary)
        let rect = FractionalRect(x: 0, y: 0, width: 0, height: 1)

        #expect(throws: ActionPlanningError.invalidAction(.outOfRange(field: "width", rule: "must be > 0"))) {
            try executor(window: window).run(.placeWindow(.custom(rect)))
        }
        #expect(window.calls.isEmpty)
    }
}

@Suite("ActionExecutor: moveToDisplay")
struct ExecutorMoveToDisplayTests {
    @Test("next moves the window to the neighbouring display at the predicted frame")
    func next() throws {
        let window = Rig.window(at: Rig.onPrimary)

        let outcome = try executor(window: window).run(.moveToDisplay(.next))

        let expected = DisplayLayout.frame(moving: Rig.onPrimary, from: Rig.primary, to: Rig.secondary)
        #expect(outcome == .placed(target: expected, achieved: expected))
        #expect(try window.frame() == expected)
        #expect(Rig.secondary.visibleFrame.contains(expected))
    }

    @Test("previous brings the window back")
    func previous() throws {
        let window = Rig.window(at: Rig.onPrimary)
        let run = executor(window: window)

        _ = try run.run(.moveToDisplay(.next))
        let outcome = try run.run(.moveToDisplay(.previous))

        guard case .placed(_, let achieved) = outcome else {
            Issue.record("expected a placement, got \(outcome)")
            return
        }
        #expect(Rig.primary.visibleFrame.contains(achieved))
        // Rounding on the way there and back costs a few points at most.
        #expect(abs(achieved.minX - Rig.onPrimary.minX) <= 3)
        #expect(abs(achieved.minY - Rig.onPrimary.minY) <= 3)
        #expect(abs(achieved.width - Rig.onPrimary.width) <= 3)
        #expect(abs(achieved.height - Rig.onPrimary.height) <= 3)
    }

    @Test("a maximized window lands exactly on the other display's visible frame")
    func maximized() throws {
        let window = Rig.window(at: Rig.primary.visibleFrame)

        let outcome = try executor(window: window).run(.moveToDisplay(.next))

        #expect(
            outcome
                == .placed(target: Rig.secondary.visibleFrame, achieved: Rig.secondary.visibleFrame))
    }

    @Test("a window that cannot take the target size is shifted inside the target display")
    func shiftedInsideTarget() throws {
        // A window at the right edge of the primary display, at least 500 pt wide, moves to the
        // 1200 pt wide secondary display.
        let start = CGRect(x: 1050, y: 100, width: 500, height: 400)
        let window = Rig.window(at: start)
        window.minimumSize = CGSize(width: 500, height: 400)

        let outcome = try executor(window: window).run(.moveToDisplay(.next))

        guard case .placed(_, let achieved) = outcome else {
            Issue.record("expected a placement, got \(outcome)")
            return
        }
        #expect(Rig.secondary.visibleFrame.contains(achieved))
    }

    @Test("with a single display there is nothing to do and the window is not changed")
    func singleDisplay() throws {
        let window = Rig.window(at: Rig.onPrimary)

        for direction in DisplayDirection.allCases {
            let outcome = try executor(window: window, displays: [Rig.primary]).run(.moveToDisplay(direction))
            #expect(outcome == .nothingToDo)
        }
        #expect(window.calls.isEmpty)
        #expect(try window.frame() == Rig.onPrimary)
    }
}

@Suite("ActionExecutor: errors")
struct ExecutorErrorTests {
    @Test("arrangeGrid is not implemented, and nothing is looked up or changed")
    func arrangeGrid() {
        let window = Rig.window(at: Rig.onPrimary)
        let calls = Calls()

        #expect(throws: ActionExecutionError.notImplemented(actionType: "arrangeGrid")) {
            try executor(window: window, calls: calls)
                .run(.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))
        }
        #expect(window.calls.isEmpty)
        #expect(calls.windows == 0 && calls.displays == 0)
    }

    @Test("moveDivider is not implemented, and nothing is looked up or changed", arguments: Direction.allCases)
    func moveDivider(direction: Direction) {
        let window = Rig.window(at: Rig.onPrimary)
        let calls = Calls()

        #expect(throws: ActionExecutionError.notImplemented(actionType: "moveDivider")) {
            try executor(window: window, calls: calls).run(.moveDivider(direction))
        }
        #expect(window.calls.isEmpty)
        #expect(calls.windows == 0 && calls.displays == 0)
    }

    @Test("the not implemented error says so in words")
    func notImplementedMessage() {
        let error = ActionExecutionError.notImplemented(actionType: "arrangeGrid")
        #expect(error.errorDescription == "the arrangeGrid action is not implemented yet")
    }

    @Test("a missing focused window is passed through unchanged", arguments: [
        WindowError.noFocusedWindow, .noFrontmostApplication, .notTrusted,
    ])
    func noWindow(error: WindowError) {
        let run = ActionExecutor(window: { throw error }, displays: { Rig.both })

        #expect(throws: error) {
            try run.run(.placeWindow(.preset(.leftHalf)))
        }
    }

    @Test("a window that cannot be read is passed through unchanged")
    func unreadableWindow() {
        let window = Rig.window(at: Rig.onPrimary)
        window.failFrameWith = .accessibility(operation: "read AXPosition", code: -25204)

        #expect(throws: WindowError.accessibility(operation: "read AXPosition", code: -25204)) {
            try executor(window: window).run(.moveToDisplay(.next))
        }
    }

    @Test("a window that cannot be moved is passed through unchanged")
    func unmovableWindow() {
        let window = Rig.window(at: Rig.onPrimary)
        window.failPositionWith = .attributeNotSettable("AXPosition")

        #expect(throws: WindowError.attributeNotSettable("AXPosition")) {
            try executor(window: window).run(.placeWindow(.preset(.leftHalf)))
        }
    }

    @Test("no displays is a planning error, and the window is not changed")
    func noDisplays() {
        let window = Rig.window(at: Rig.onPrimary)

        #expect(throws: ActionPlanningError.noDisplays) {
            try executor(window: window, displays: []).run(.placeWindow(.preset(.leftHalf)))
        }
        #expect(window.calls.isEmpty)
    }

    @Test("a failing display lookup is passed through")
    func displayLookupFails() {
        struct Failure: Error, Equatable {}
        let window = Rig.window(at: Rig.onPrimary)
        let run = ActionExecutor(window: { window }, displays: { throw Failure() })

        #expect(throws: Failure()) {
            try run.run(.moveToDisplay(.next))
        }
        #expect(window.calls.isEmpty)
    }

    @Test("every error carries a message for the control channel")
    func messages() {
        let errors: [any Error] = [
            ActionExecutionError.notImplemented(actionType: "moveDivider"),
            ActionPlanningError.noDisplays,
            WindowError.noFocusedWindow,
        ]
        for error in errors {
            let message = (error as? any LocalizedError)?.errorDescription
            #expect(message?.isEmpty == false, "\(error) has no description")
        }
    }
}
