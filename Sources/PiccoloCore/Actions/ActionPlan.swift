import CoreGraphics
import Foundation

/// What a single-window action asks of the focused window.
public enum ActionPlan: Equatable, Sendable {
    /// Move and resize the window to `target`.
    ///
    /// `visibleFrame` is the visible frame of the display the window is meant to end up on. A window
    /// that refuses the target size is shifted so that it lies inside it where possible.
    case place(target: CGRect, visibleFrame: CGRect)
    /// The action is satisfied as things are, for example `moveToDisplay` with a single display.
    case nothingToDo
}

/// Why an action cannot be planned.
public enum ActionPlanningError: Error, Equatable, Sendable, LocalizedError {
    /// The action is not `placeWindow` or `moveToDisplay`.
    case notSingleWindowAction
    /// There is no display to plan against.
    case noDisplays
    /// A display's visible frame has no area, so fractions of it mean nothing.
    case emptyVisibleFrame
    /// The action itself breaks a rule of the configuration model (for example a custom frame
    /// outside the screen).
    case invalidAction(ValidationError)

    public var errorDescription: String? {
        switch self {
        case .notSingleWindowAction:
            return "not a single-window action"
        case .noDisplays:
            return "no display is attached"
        case .emptyVisibleFrame:
            return "the display has an empty visible frame"
        case .invalidAction(let error):
            return "invalid action: \(error)"
        }
    }
}

/// Computes what a single-window action does to a window.
public enum ActionPlanner {
    /// Plans `action` for a window at `windowFrame` on `displays`, all in the canonical space.
    ///
    /// - `placeWindow`: the display is the one containing the window
    ///   (``DisplayLayout/index(containing:in:)``); the target is the spec resolved against that
    ///   display's visible frame (``FrameResolver``).
    /// - `moveToDisplay`: from the containing display to its neighbour in the given direction
    ///   (``DisplayLayout/neighbor(of:_:in:)``); the target keeps the window's relative frame
    ///   (``DisplayLayout/frame(moving:from:to:)``). With a single display, or with no display in a
    ///   geometric direction (`left`, `right`, `up`, `down`), there is nothing to do.
    /// - Anything else is not a single-window action.
    public static func plan(
        _ action: Action,
        windowFrame: CGRect,
        displays: [Display]
    ) throws(ActionPlanningError) -> ActionPlan {
        switch action {
        case .placeWindow(let spec):
            do {
                try action.validate()
            } catch {
                throw .invalidAction(error)
            }
            guard let index = DisplayLayout.index(containing: windowFrame, in: displays) else {
                throw .noDisplays
            }
            let visibleFrame = displays[index].visibleFrame
            guard hasArea(visibleFrame) else { throw .emptyVisibleFrame }
            let target = FrameResolver.frame(
                for: spec, visibleFrame: visibleFrame, currentFrame: windowFrame)
            return .place(target: target, visibleFrame: visibleFrame)

        case .moveToDisplay(let direction):
            guard let source = DisplayLayout.index(containing: windowFrame, in: displays) else {
                throw .noDisplays
            }
            let destination = DisplayLayout.neighbor(of: source, direction, in: displays)
            guard destination != source else { return .nothingToDo }
            guard hasArea(displays[source].visibleFrame), hasArea(displays[destination].visibleFrame) else {
                throw .emptyVisibleFrame
            }
            let target = DisplayLayout.frame(
                moving: windowFrame, from: displays[source], to: displays[destination])
            return .place(target: target, visibleFrame: displays[destination].visibleFrame)

        case .arrangeGrid, .moveDivider:
            throw .notSingleWindowAction
        }
    }

    private static func hasArea(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0
    }
}
