import AppKit
import PiccoloCore
import Testing

@testable import PiccoloUI

/// The Settings window follows the height the General tab asks for, also when a new height arrives while the
/// window is still animating to an earlier one. These tests drive the heights themselves
/// (`GeneralHeight.report` and `generalFittingHeightChanged()`, in one stretch of the main actor, so that
/// nothing else runs in between) and wait for the end of the animation, not for a time: whatever the load of
/// the machine, the window has to end at the last height asked for.
@MainActor
@Suite("Settings window resize")
struct SettingsWindowResizeTests {
    private static let screen = CGRect(x: 0, y: 0, width: 2000, height: 1600)

    private let host = SettingsHost(
        isAccessibilityTrusted: { true },
        openAccessibilitySettings: {},
        revealConfigInFinder: {},
        appVersion: "0.1.0 (1)")

    /// A window on the General tab, on screen but invisible (it takes no focus and no clicks), that animates
    /// its resizes whatever the machine's setting for reduced motion is. It starts at the height `start`, in
    /// content points; later heights are asked for with ``ask(_:of:in:)``.
    private func makeWindow(startingAt start: CGFloat = 700) async throws -> (
        controller: SettingsWindowController, window: NSWindow, content: SettingsContentController
    ) {
        let model = SettingsModel(
            backend: InMemorySettingsBackend(config: Config(bindings: [])), loginItem: FakeLoginItem(),
            language: FakeLanguage())
        model.tab = .general
        let controller = SettingsWindowController(
            model: model, host: host, frameName: "PiccoloSettingsTests.\(UUID().uuidString)")
        controller.visibleFrameProvider = { _ in Self.screen }
        controller.reducesMotion = { false }
        controller.animatesFrameChanges = false
        let window = controller.ensureWindow()
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderFront(nil)
        window.setFrameTopLeftPoint(CGPoint(x: 300, y: 1400))
        let content = try #require(controller.content)
        #expect(content.tab == .general)
        // The heights the tab itself reported while it was laid out are on their way to the window: let them
        // arrive before the test takes over.
        await mainQueueTurn()
        content.generalHeight.report(start)
        controller.generalFittingHeightChanged()
        controller.animatesFrameChanges = true
        return (controller, window, content)
    }

    /// Lets everything that is queued on the main queue run.
    private func mainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// The General tab asks for `height` and the window is told so, as the tab's own report and the hop
    /// that follows it would.
    private func ask(_ height: CGFloat, of content: SettingsContentController, in controller: SettingsWindowController) {
        content.generalHeight.report(height)
        controller.generalFittingHeightChanged()
    }

    /// Waits until the controller has no resize animation under way. There is no deadline: a resize that never
    /// ends is stopped by the time limit of the test.
    private func resizeEnd(_ controller: SettingsWindowController) async {
        guard controller.isResizing else { return }
        await withCheckedContinuation { continuation in
            controller.onResizeEnd = { continuation.resume() }
        }
    }

    private func contentHeight(of window: NSWindow) -> CGFloat {
        window.contentRect(forFrameRect: window.frame).height
    }

    @Test(
        "a height that goes back before the window has moved to the one in between ends with the window at it",
        .timeLimit(.minutes(1)))
    func heightGoesBackBeforeTheWindowMoved() async throws {
        let (controller, window, content) = try await makeWindow()
        let start = window.frame
        let height = contentHeight(of: window)

        ask(height + 80, of: content, in: controller)
        #expect(controller.isResizing, "no animation to the taller height has started")
        #expect(window.frame == start, "the window already moved: the test no longer tests a window that has not")

        ask(height, of: content, in: controller)
        await resizeEnd(controller)

        #expect(content.generalFittingHeight == height)
        #expect(
            abs(contentHeight(of: window) - height) < 1,
            "the tab asks for \(height) pt, the window ended \(contentHeight(of: window)) pt high")
        #expect(window.frame.maxY == start.maxY, "the top edge moved")
        withExtendedLifetime(controller) {}
    }

    @Test(
        "a window fitted at once while an animation is under way ends at that fit, not where the animation was going",
        .timeLimit(.minutes(1)))
    func fitAtOnceDuringAnimation() async throws {
        let (controller, window, content) = try await makeWindow()
        let height = contentHeight(of: window)

        ask(height + 80, of: content, in: controller)
        #expect(controller.isResizing, "no animation to the taller height has started")
        // The window is fitted without animation now: the window not being on screen any more, a screen
        // change, or Reduce Motion turned on while the animation runs.
        controller.animatesFrameChanges = false
        ask(height + 40, of: content, in: controller)
        await resizeEnd(controller)

        #expect(
            abs(contentHeight(of: window) - (height + 40)) < 1,
            "the tab asks for \(height + 40) pt, the window ended \(contentHeight(of: window)) pt high")
        withExtendedLifetime(controller) {}
    }

    @Test(
        "heights that keep changing while the window animates end with the window at the last one, and nothing is left counted",
        .timeLimit(.minutes(1)))
    func severalHeightsDuringAnimation() async throws {
        let (controller, window, content) = try await makeWindow()
        let height = contentHeight(of: window)

        ask(height + 80, of: content, in: controller)
        await mainQueueTurn()
        ask(height + 30, of: content, in: controller)
        ask(height + 120, of: content, in: controller)
        await mainQueueTurn()
        ask(height - 40, of: content, in: controller)
        ask(height + 60, of: content, in: controller)
        await resizeEnd(controller)

        #expect(
            abs(contentHeight(of: window) - (height + 60)) < 1,
            "the tab asks for \(height + 60) pt, the window ended \(contentHeight(of: window)) pt high")
        #expect(!controller.isResizing, "a resize animation is still counted")
        withExtendedLifetime(controller) {}
    }

    @Test("a height that arrives when no animation is under way is followed, up and down, with the top edge kept", .timeLimit(.minutes(1)))
    func heightFollowedWhenIdle() async throws {
        let (controller, window, content) = try await makeWindow()
        let start = window.frame
        let height = contentHeight(of: window)

        ask(height + 80, of: content, in: controller)
        await resizeEnd(controller)
        #expect(abs(contentHeight(of: window) - (height + 80)) < 1)

        ask(height, of: content, in: controller)
        await resizeEnd(controller)
        #expect(abs(contentHeight(of: window) - height) < 1)
        #expect(window.frame.maxY == start.maxY, "the top edge moved")
        withExtendedLifetime(controller) {}
    }
}
