import Foundation

/// The reasons a shortcut that fired could not act and the user is told about, with a short notice
/// in the middle of the display.
///
/// The raw value is the stable, config-style name of the notice (used by the debug control channel).
/// What produces each notice is decided where the outcomes live: ``init(arrangePlannerError:)`` here,
/// and `FailureNotice.init(error:)` and `FailureNotice.init(outcome:for:)` in `PiccoloSystem`.
public enum FailureNotice: String, CaseIterable, Equatable, Sendable {
    /// Piccolo has no Accessibility permission.
    case accessibilityNotGranted
    /// No window has the focus, or no application is frontmost.
    case noWindow
    /// Piccolo's own window is in front, and Piccolo never moves its own windows.
    case ownWindow
    /// The window could not be changed: it is gone, refuses the change, or an Accessibility call failed.
    case windowNotChangeable
    /// `moveToDisplay` with no display to go to (in that direction).
    case noOtherDisplay
    /// `arrangeGrid` with no window to arrange.
    case nothingToArrange
    /// The grid does not fit the display.
    case gridDoesNotFit
    /// `moveDivider` on a window that is not in an arrangement made by Piccolo.
    case noGroup
    /// `moveDivider` on a group that no longer held, and was dissolved.
    case dissolved
    /// `moveDivider` where the divider cannot move further.
    case cannotMove
    /// `restoreWindow` on a window Piccolo did not move, or that has been moved since.
    case nothingToRestore

    /// The notice for a grid that cannot be planned. Every ``ArrangePlannerError`` means that the
    /// arrangement does not fit.
    public init(arrangePlannerError _: ArrangePlannerError) {
        self = .gridDoesNotFit
    }
}
