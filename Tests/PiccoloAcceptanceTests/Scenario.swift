import CoreGraphics
import Foundation
import PiccoloSystem

/// Runs `body` against a running fixture that starts with no windows, and closes every
/// fixture window afterwards, whether `body` succeeded or not.
func withFixture<Result>(
    _ body: (FixtureApp) async throws -> Result
) async throws -> Result {
    let fixture = try await FixtureApp.launched()
    try fixture.closeAll()
    do {
        let result = try await body(fixture)
        try? fixture.closeAll()
        return result
    } catch {
        try? fixture.closeAll()
        throw error
    }
}

/// Test frames, derived from the real displays so that they fit whatever is attached.
enum Layout {
    @MainActor
    static func screens() throws -> [ScreenInfo] {
        let screens = Screens.current()
        guard !screens.isEmpty else { throw AcceptanceFailure("no display is attached") }
        return screens
    }

    /// A frame of `size` that starts `offset` points inside the top-left corner of the
    /// display's visible frame, so that it needs no adjustment by the window system.
    static func frame(in screen: ScreenInfo, offset: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: screen.visibleFrame.minX + offset.x,
            y: screen.visibleFrame.minY + offset.y,
            width: size.width, height: size.height)
    }
}
