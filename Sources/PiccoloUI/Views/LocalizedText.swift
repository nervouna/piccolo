import SwiftUI

extension Text {
    /// A text of the window, looked up in PiccoloUI's string catalog.
    ///
    /// SwiftUI looks the literal of `Text("…")`, `Button("…")`, `Toggle("…")` and the like up in the
    /// main bundle, which in an app that uses this package is the app's, not PiccoloUI's. Every
    /// text of the window goes through here, or through `String(localized:bundle:)` with
    /// `bundle: .module` where a control wants a `String`, so that none is looked up in the wrong
    /// place. The text is shown as it is: SwiftUI does not look it up again.
    init(localized value: String.LocalizationValue) {
        self.init(verbatim: String(localized: value, bundle: .module))
    }
}
