import CoreGraphics
import Testing

@testable import PiccoloCore

/// Two displays like a laptop with a smaller screen to its left: the primary at the origin, the
/// secondary at negative x and shifted down. Every expectation is computed with `FrameResolver` and
/// `DisplayLayout`, never written down as numbers, so that these tests do not depend on how edges round.
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
}

@Suite("ActionPlanner: placeWindow")
struct PlaceWindowPlanTests {
    @Test("a preset resolves against the visible frame of the display the window is on", arguments: Preset.allCases)
    func presetOnPrimary(preset: Preset) throws {
        let plan = try ActionPlanner.plan(
            .placeWindow(.preset(preset)), windowFrame: Rig.onPrimary, displays: Rig.both)

        let expected = FrameResolver.frame(
            for: .preset(preset), visibleFrame: Rig.primary.visibleFrame, currentFrame: Rig.onPrimary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.primary.visibleFrame))
    }

    @Test("a window on the secondary display is placed on the secondary display", arguments: Preset.allCases)
    func presetOnSecondary(preset: Preset) throws {
        let plan = try ActionPlanner.plan(
            .placeWindow(.preset(preset)), windowFrame: Rig.onSecondary, displays: Rig.both)

        let expected = FrameResolver.frame(
            for: .preset(preset), visibleFrame: Rig.secondary.visibleFrame, currentFrame: Rig.onSecondary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.secondary.visibleFrame))
    }

    @Test("a custom frame resolves against the display's visible frame")
    func customFrame() throws {
        let rect = FractionalRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        let plan = try ActionPlanner.plan(
            .placeWindow(.custom(rect)), windowFrame: Rig.onSecondary, displays: Rig.both)

        let expected = FrameResolver.frame(
            for: .custom(rect), visibleFrame: Rig.secondary.visibleFrame, currentFrame: Rig.onSecondary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.secondary.visibleFrame))
    }

    @Test("center keeps the window's size")
    func centerKeepsSize() throws {
        let plan = try ActionPlanner.plan(
            .placeWindow(.preset(.center)), windowFrame: Rig.onPrimary, displays: Rig.both)

        guard case .place(let target, _) = plan else {
            Issue.record("expected a placement, got \(plan)")
            return
        }
        #expect(target.size == Rig.onPrimary.size)
        #expect(Rig.primary.visibleFrame.contains(target))
    }

    @Test("a window straddling two displays is placed on the display holding the larger part")
    func straddling() throws {
        // 300 pt on the secondary (x -300..0), 100 pt on the primary (x 0..100).
        let window = CGRect(x: -300, y: 300, width: 400, height: 300)
        #expect(DisplayLayout.index(containing: window, in: Rig.both) == 1)

        let plan = try ActionPlanner.plan(.placeWindow(.preset(.leftHalf)), windowFrame: window, displays: Rig.both)

        let expected = FrameResolver.frame(
            for: .preset(.leftHalf), visibleFrame: Rig.secondary.visibleFrame, currentFrame: window)
        #expect(plan == .place(target: expected, visibleFrame: Rig.secondary.visibleFrame))

        // 100 pt on the secondary (x -100..0), 300 pt on the primary (x 0..300).
        let mirrored = CGRect(x: -100, y: 300, width: 400, height: 300)
        #expect(DisplayLayout.index(containing: mirrored, in: Rig.both) == 0)

        let mirroredPlan = try ActionPlanner.plan(
            .placeWindow(.preset(.leftHalf)), windowFrame: mirrored, displays: Rig.both)

        let mirroredExpected = FrameResolver.frame(
            for: .preset(.leftHalf), visibleFrame: Rig.primary.visibleFrame, currentFrame: mirrored)
        #expect(mirroredPlan == .place(target: mirroredExpected, visibleFrame: Rig.primary.visibleFrame))
    }

    @Test("a window outside every display is placed on the nearest one")
    func offScreen() throws {
        let window = CGRect(x: -3000, y: 300, width: 400, height: 300)
        let plan = try ActionPlanner.plan(.placeWindow(.preset(.maximize)), windowFrame: window, displays: Rig.both)

        #expect(plan == .place(target: Rig.secondary.visibleFrame, visibleFrame: Rig.secondary.visibleFrame))
    }

    @Test("with a single display the window is placed on it")
    func singleDisplay() throws {
        let plan = try ActionPlanner.plan(
            .placeWindow(.preset(.maximize)), windowFrame: Rig.onPrimary, displays: [Rig.primary])

        #expect(plan == .place(target: Rig.primary.visibleFrame, visibleFrame: Rig.primary.visibleFrame))
    }

    @Test("a custom frame outside the screen is invalid")
    func invalidCustomFrame() {
        let rect = FractionalRect(x: 0.5, y: 0, width: 0.75, height: 1)
        #expect(throws: ActionPlanningError.invalidAction(.outOfRange(field: "x + width", rule: "must be <= 1"))) {
            try ActionPlanner.plan(.placeWindow(.custom(rect)), windowFrame: Rig.onPrimary, displays: Rig.both)
        }
    }

    @Test("a custom frame that is not finite is invalid")
    func notFiniteCustomFrame() {
        let rect = FractionalRect(x: .nan, y: 0, width: 0.5, height: 1)
        #expect(throws: ActionPlanningError.invalidAction(.notFinite(field: "x"))) {
            try ActionPlanner.plan(.placeWindow(.custom(rect)), windowFrame: Rig.onPrimary, displays: Rig.both)
        }
    }

    @Test("no displays is an error")
    func noDisplays() {
        #expect(throws: ActionPlanningError.noDisplays) {
            try ActionPlanner.plan(.placeWindow(.preset(.leftHalf)), windowFrame: Rig.onPrimary, displays: [])
        }
    }

    @Test("a display without a visible area is an error")
    func emptyVisibleFrame() {
        let flat = Display(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: 0, y: 600, width: 800, height: 0))
        #expect(throws: ActionPlanningError.emptyVisibleFrame) {
            try ActionPlanner.plan(.placeWindow(.preset(.leftHalf)), windowFrame: Rig.onPrimary, displays: [flat])
        }
    }
}

@Suite("ActionPlanner: moveToDisplay")
struct MoveToDisplayPlanTests {
    @Test("next from the primary display wraps around to the display on its left")
    func nextFromPrimary() throws {
        // Displays are ordered by x: secondary, primary. `next` from the last one wraps to the first.
        let plan = try ActionPlanner.plan(.moveToDisplay(.next), windowFrame: Rig.onPrimary, displays: Rig.both)

        let expected = DisplayLayout.frame(moving: Rig.onPrimary, from: Rig.primary, to: Rig.secondary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.secondary.visibleFrame))
        #expect(Rig.secondary.visibleFrame.contains(expected))
    }

    @Test("previous from the secondary display wraps around to the primary display")
    func previousFromSecondary() throws {
        let plan = try ActionPlanner.plan(.moveToDisplay(.previous), windowFrame: Rig.onSecondary, displays: Rig.both)

        let expected = DisplayLayout.frame(moving: Rig.onSecondary, from: Rig.secondary, to: Rig.primary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.primary.visibleFrame))
    }

    @Test("next from the secondary display goes to the primary display")
    func nextFromSecondary() throws {
        let plan = try ActionPlanner.plan(.moveToDisplay(.next), windowFrame: Rig.onSecondary, displays: Rig.both)

        let expected = DisplayLayout.frame(moving: Rig.onSecondary, from: Rig.secondary, to: Rig.primary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.primary.visibleFrame))
    }

    @Test("a maximized window lands exactly on the other display's visible frame")
    func maximized() throws {
        let plan = try ActionPlanner.plan(
            .moveToDisplay(.next), windowFrame: Rig.primary.visibleFrame, displays: Rig.both)

        #expect(plan == .place(target: Rig.secondary.visibleFrame, visibleFrame: Rig.secondary.visibleFrame))
    }

    @Test("the neighbour follows the displays' layout order, not the list's order")
    func followsLayoutOrder() throws {
        let displays = [Rig.primary, Rig.secondary]
        let reversed = [Rig.secondary, Rig.primary]
        let plan = try ActionPlanner.plan(.moveToDisplay(.next), windowFrame: Rig.onSecondary, displays: displays)
        let reversedPlan = try ActionPlanner.plan(
            .moveToDisplay(.next), windowFrame: Rig.onSecondary, displays: reversed)

        #expect(plan == reversedPlan)
    }

    @Test("a window straddling two displays moves from the display holding the larger part")
    func straddling() throws {
        // 300 pt on the secondary (x -300..0), 100 pt on the primary (x 0..100).
        let window = CGRect(x: -300, y: 300, width: 400, height: 300)
        let plan = try ActionPlanner.plan(.moveToDisplay(.next), windowFrame: window, displays: Rig.both)

        // It belongs to the secondary display, whose `next` is the primary.
        let expected = DisplayLayout.frame(moving: window, from: Rig.secondary, to: Rig.primary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.primary.visibleFrame))
    }

    @Test("with a single display there is nothing to do", arguments: DisplayDirection.allCases)
    func singleDisplay(direction: DisplayDirection) throws {
        let plan = try ActionPlanner.plan(
            .moveToDisplay(direction), windowFrame: Rig.onPrimary, displays: [Rig.primary])

        #expect(plan == .nothingToDo)
    }

    @Test("no displays is an error")
    func noDisplays() {
        #expect(throws: ActionPlanningError.noDisplays) {
            try ActionPlanner.plan(.moveToDisplay(.next), windowFrame: Rig.onPrimary, displays: [])
        }
    }

    @Test("a display without a visible area is an error")
    func emptyVisibleFrame() {
        let flat = Display(
            frame: CGRect(x: 2000, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: 2000, y: 600, width: 800, height: 0))
        #expect(throws: ActionPlanningError.emptyVisibleFrame) {
            try ActionPlanner.plan(.moveToDisplay(.next), windowFrame: Rig.onPrimary, displays: [Rig.primary, flat])
        }
    }
}

@Suite("ActionPlanner: moveToDisplay in a direction")
struct MoveToDisplayDirectionPlanTests {
    /// The secondary is to the left of the primary, so `left` from the primary leads to it.
    @Test("left from the primary goes to the display on its left, keeping the relative frame")
    func leftFromPrimary() throws {
        let plan = try ActionPlanner.plan(.moveToDisplay(.left), windowFrame: Rig.onPrimary, displays: Rig.both)

        let expected = DisplayLayout.frame(moving: Rig.onPrimary, from: Rig.primary, to: Rig.secondary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.secondary.visibleFrame))
        #expect(Rig.secondary.visibleFrame.contains(expected))
    }

    @Test("right from the secondary goes back to the primary, and so does a maximized window")
    func rightFromSecondary() throws {
        let plan = try ActionPlanner.plan(.moveToDisplay(.right), windowFrame: Rig.onSecondary, displays: Rig.both)

        let expected = DisplayLayout.frame(moving: Rig.onSecondary, from: Rig.secondary, to: Rig.primary)
        #expect(plan == .place(target: expected, visibleFrame: Rig.primary.visibleFrame))

        let maximized = try ActionPlanner.plan(
            .moveToDisplay(.right), windowFrame: Rig.secondary.visibleFrame, displays: Rig.both)
        #expect(maximized == .place(target: Rig.primary.visibleFrame, visibleFrame: Rig.primary.visibleFrame))
    }

    @Test("right from the primary, with no display on its right, is nothing to do, and nothing wraps around")
    func noCandidate() throws {
        let plan = try ActionPlanner.plan(.moveToDisplay(.right), windowFrame: Rig.onPrimary, displays: Rig.both)

        #expect(plan == .nothingToDo)
    }

    @Test("up and down with displays side by side are nothing to do")
    func verticalWithoutDisplays() throws {
        #expect(try ActionPlanner.plan(.moveToDisplay(.up), windowFrame: Rig.onPrimary, displays: Rig.both) == .nothingToDo)
        #expect(try ActionPlanner.plan(.moveToDisplay(.down), windowFrame: Rig.onPrimary, displays: Rig.both) == .nothingToDo)
    }

    @Test("up from the primary goes to the display above it, which has its own visible frame")
    func up() throws {
        let above = Display(
            frame: CGRect(x: 0, y: -900, width: 1600, height: 900),
            visibleFrame: CGRect(x: 0, y: -900, width: 1600, height: 880))
        let displays = [Rig.primary, above]
        let plan = try ActionPlanner.plan(.moveToDisplay(.up), windowFrame: Rig.onPrimary, displays: displays)

        let expected = DisplayLayout.frame(moving: Rig.onPrimary, from: Rig.primary, to: above)
        #expect(plan == .place(target: expected, visibleFrame: above.visibleFrame))
        #expect(above.visibleFrame.contains(expected))

        let back = try ActionPlanner.plan(.moveToDisplay(.down), windowFrame: expected, displays: displays)
        let backExpected = DisplayLayout.frame(moving: expected, from: above, to: Rig.primary)
        #expect(back == .place(target: backExpected, visibleFrame: Rig.primary.visibleFrame))
    }

    @Test("with a single display every direction is nothing to do", arguments: DisplayDirection.allCases)
    func singleDisplay(direction: DisplayDirection) throws {
        let plan = try ActionPlanner.plan(
            .moveToDisplay(direction), windowFrame: Rig.onPrimary, displays: [Rig.primary])

        #expect(plan == .nothingToDo)
    }
}

@Suite("ActionPlanner: other actions")
struct OtherActionPlanTests {
    @Test("arrangeGrid is not a single-window action")
    func arrangeGrid() {
        #expect(throws: ActionPlanningError.notSingleWindowAction) {
            try ActionPlanner.plan(
                .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)),
                windowFrame: Rig.onPrimary, displays: Rig.both)
        }
    }

    @Test("moveDivider is not a single-window action", arguments: Direction.allCases)
    func moveDivider(direction: Direction) {
        #expect(throws: ActionPlanningError.notSingleWindowAction) {
            try ActionPlanner.plan(.moveDivider(direction), windowFrame: Rig.onPrimary, displays: Rig.both)
        }
    }

    @Test("swapWindow is not a single-window action", arguments: Direction.allCases)
    func swapWindow(direction: Direction) {
        #expect(throws: ActionPlanningError.notSingleWindowAction) {
            try ActionPlanner.plan(.swapWindow(direction), windowFrame: Rig.onPrimary, displays: Rig.both)
        }
    }

    @Test("errors read as plain sentences")
    func descriptions() {
        #expect(ActionPlanningError.notSingleWindowAction.errorDescription == "not a single-window action")
        #expect(ActionPlanningError.noDisplays.errorDescription == "no display is attached")
        #expect(
            ActionPlanningError.invalidAction(.notFinite(field: "x")).errorDescription
                == "invalid action: x must be a finite number")
    }
}
