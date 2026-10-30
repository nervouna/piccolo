import Foundation
import PiccoloCore

/// The text and the symbol of each failure notice (see ``FailureNotice``).
public enum FailureNoticeText {
    /// The one-line text of `notice`, in the language of `bundle` (default: the running app's).
    public static func text(for notice: FailureNotice, bundle: Bundle = AppLanguage.currentTextBundle) -> String {
        switch notice {
        case .accessibilityNotGranted: String(localized: "Accessibility access is not granted", bundle: bundle)
        case .noWindow: String(localized: "No window to act on", bundle: bundle)
        case .ownWindow: String(localized: "Piccolo does not move its own windows", bundle: bundle)
        case .windowNotChangeable: String(localized: "This window cannot be moved or resized", bundle: bundle)
        case .noOtherDisplay: String(localized: "No display in that direction", bundle: bundle)
        case .nothingToArrange: String(localized: "No windows to arrange", bundle: bundle)
        case .gridDoesNotFit: String(localized: "The grid does not fit this display", bundle: bundle)
        case .noGroup: String(localized: "This window was not arranged by Piccolo", bundle: bundle)
        case .dissolved: String(localized: "The windows have changed. Arrange again", bundle: bundle)
        case .cannotMove: String(localized: "The divider cannot move further", bundle: bundle)
        }
    }

    /// The SF Symbol drawn before the text.
    public static func symbolName(for notice: FailureNotice) -> String {
        switch notice {
        case .accessibilityNotGranted: "hand.raised"
        case .noWindow, .ownWindow: "macwindow"
        case .windowNotChangeable: "exclamationmark.triangle"
        case .noOtherDisplay: "display"
        case .nothingToArrange, .gridDoesNotFit: "rectangle.grid.2x2"
        case .noGroup, .dissolved, .cannotMove: "rectangle.split.2x1"
        }
    }
}
