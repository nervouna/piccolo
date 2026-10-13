import CoreGraphics
import Foundation
import Testing

/// Acceptance tests for the control channel and the window primitive: the installed Debug
/// Piccolo moves and resizes real windows of the PiccoloFixture app, and every result is
/// measured independently in the window server.
///
/// The tests share one desktop, so they run one at a time. Run them with
/// `scripts/accept.sh`, which builds and installs everything, takes the machine-wide lock
/// and cleans up.
@Suite(
    "Desktop acceptance",
    .serialized,
    .enabled(if: Acceptance.isEnabled, "set \(Acceptance.environmentVariable)=1 (scripts/accept.sh does)"),
    .piccoloRunning
)
struct DesktopAcceptanceTests {
    private let piccolo = PiccoloClient()

    @Test("1. status reports axTrusted: true")
    func statusReportsAccessibilityTrust() throws {
        let trusted = try piccolo.axTrusted()
        #expect(
            trusted,
            "Piccolo reports axTrusted: false; the installed build lost its Accessibility grant (never reset it with tccutil, install only with scripts/install.sh)"
        )
    }

    @Test("2. a fixture window opened at frame A is measured at A")
    func openedWindowIsMeasuredAtItsFrame() async throws {
        let screens = try await MainActor.run { try Layout.screens() }
        let a = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))

        try await withFixture { fixture in
            let window = try fixture.open(id: "frame-a", frame: a)
            #expect(
                framesMatch(window.frame, a),
                "the fixture reports \(describe(window.frame)) for a window opened at \(describe(a))")

            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: a)
        }
    }

    @Test("3. setFocusedFrame moves and resizes the focused window to B")
    func setFocusedFrameMovesAndResizes() async throws {
        let screens = try await MainActor.run { try Layout.screens() }
        let a = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
        let b = Layout.frame(in: screens[0], offset: CGPoint(x: 260, y: 160), size: CGSize(width: 780, height: 520))

        try await withFixture { fixture in
            let window = try fixture.open(id: "move-me", frame: a)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: a)
            try await Focus.bring(window, of: fixture)

            let response = try piccolo.setFocusedFrame(b)
            #expect(
                framesMatch(response, b),
                "setFocusedFrame answered \(describe(response)) for the request \(describe(b))")

            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: b)
        }
    }

    @Test("4. a window with a minimum size refuses to get smaller")
    func minimumSizeIsReportedAndMeasured() async throws {
        let screens = try await MainActor.run { try Layout.screens() }
        let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 800, height: 600))
        let request = Layout.frame(in: screens[0], offset: CGPoint(x: 200, y: 140), size: CGSize(width: 300, height: 200))
        let minimum = CGSize(width: 700, height: 500)

        try await withFixture { fixture in
            let window = try fixture.open(id: "min-size", frame: start, minSize: minimum)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)
            try await Focus.bring(window, of: fixture)

            let response = try piccolo.setFocusedFrame(request)
            #expect(
                sizesMatch(response.size, minimum),
                "asked for \(describe(request.size)) the window should stop at its minimum \(describe(minimum)), but setFocusedFrame answered \(describe(response.size))"
            )

            let measured = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: response)
            #expect(
                sizesMatch(measured.size, minimum),
                "the window server measures \(describe(measured.size)), the minimum is \(describe(minimum))")
        }
    }

    @Test("5. a window with resize increments ends up on the grid, not at the request")
    func resizeIncrementsSnapToTheGrid() async throws {
        let screens = try await MainActor.run { try Layout.screens() }
        let start = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 600, height: 400))
        // Off the 50 pt grid in both directions, and well away from the midpoint between two
        // grid lines, so that the outcome does not depend on how the system rounds.
        let request = Layout.frame(in: screens[0], offset: CGPoint(x: 200, y: 140), size: CGSize(width: 560, height: 440))
        let step = CGSize(width: 50, height: 50)

        try await withFixture { fixture in
            let window = try fixture.open(id: "grid", frame: start, resizeIncrements: step)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: start)
            try await Focus.bring(window, of: fixture)

            let response = try piccolo.setFocusedFrame(request)
            #expect(
                !sizesMatch(response.size, request.size),
                "the window took the requested \(describe(request.size)) although it only allows multiples of \(describe(step))"
            )
            #expect(
                isMultiple(response.width, of: step.width) && isMultiple(response.height, of: step.height),
                "setFocusedFrame answered \(describe(response.size)), which is not on the \(describe(step)) grid"
            )

            let measured = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: response)
            #expect(
                isMultiple(measured.width, of: step.width) && isMultiple(measured.height, of: step.height),
                "the window server measures \(describe(measured.size)), which is not on the \(describe(step)) grid"
            )
        }
    }

    @Test(
        "6. a window moves into the second display's visible frame",
        .enabled(if: Acceptance.displayCount >= 2, "needs two or more displays")
    )
    func windowMovesToTheSecondDisplay() async throws {
        let screens = try await MainActor.run { try Layout.screens() }
        guard let second = screens.first(where: { !$0.isPrimary }) else {
            throw AcceptanceFailure("the display list has no second display: \(screens)")
        }
        let a = Layout.frame(in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
        let size = CGSize(
            width: min(760, second.visibleFrame.width - 160),
            height: min(520, second.visibleFrame.height - 160))
        let target = Layout.frame(in: second, offset: CGPoint(x: 80, y: 80), size: size)

        try await withFixture { fixture in
            let window = try fixture.open(id: "traveller", frame: a)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: a)
            try await Focus.bring(window, of: fixture)

            let response = try piccolo.setFocusedFrame(target)
            #expect(
                framesMatch(response, target),
                "setFocusedFrame answered \(describe(response)) for the request \(describe(target)) on the second display"
            )

            let measured = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: target)
            #expect(
                second.visibleFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(measured),
                "the window is measured at \(describe(measured)), outside the second display's visible frame \(describe(second.visibleFrame))"
            )
        }
    }
}
