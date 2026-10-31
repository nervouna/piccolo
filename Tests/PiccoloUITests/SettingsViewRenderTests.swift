import AppKit
import SwiftUI
import Testing

import PiccoloCore

@testable import PiccoloUI

/// Draws the Settings views into bitmaps, as a smoke test that every state of the window can be built and
/// laid out. Nothing is shown and no permission is involved: the views draw themselves into a bitmap of their
/// own hosting view. The windows whose bitmaps are compared are ordered front invisibly (`orderFrontInvisibly`),
/// because a window that is not on screen can have an incomplete first layout.
///
/// Set `PICCOLO_RENDER_DIR` to a folder to keep the images, for example to look at the layout in
/// light and dark appearance.
@MainActor
@Suite("Settings views render")
struct SettingsViewRenderTests {
    private static let size = NSSize(width: 640, height: 820)

    private let host = SettingsHost(
        isAccessibilityTrusted: { true },
        openAccessibilitySettings: {},
        revealConfigInFinder: {},
        appVersion: "0.1.0 (1)")

    private func model(
        _ bindings: [KeyBinding], issues: [String] = [], loginItem: FakeLoginItem = FakeLoginItem(),
        language: FakeLanguage = FakeLanguage()
    ) -> SettingsModel {
        let backend = InMemorySettingsBackend(config: Config(bindings: bindings), issues: issues)
        return SettingsModel(backend: backend, loginItem: loginItem, language: language) { code in ["0": "a", "11": "b"][String(code)] }
    }

    /// Orders `window` front with alpha 0 and no mouse events, as `SettingsWindowTabsTests.generalFollowsItsContent`
    /// does: the window is laid out as one on screen, and nothing is shown or clicked. The caller orders it out.
    private func orderFrontInvisibly(_ window: NSWindow) {
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderFront(nil)
    }

    /// Renders `view` at `size` with the given appearance and returns the bitmap. The window is ordered front
    /// invisibly while the bitmap is taken, and out again after.
    private func render<Content: View>(
        _ view: Content, size: NSSize = SettingsViewRenderTests.size, dark: Bool = false
    ) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        orderFrontInvisibly(window)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    /// Makes the Settings window for `model`, off screen, with a screen of its own so that the machine's
    /// does not matter. Keep the controller as long as the window is used.
    private func makeWindow(_ model: SettingsModel) -> (controller: SettingsWindowController, window: NSWindow) {
        let controller = SettingsWindowController(
            model: model, host: host, frameName: "PiccoloSettingsTests.\(UUID().uuidString)")
        controller.visibleFrameProvider = { _ in CGRect(x: 0, y: 0, width: 2000, height: 1600) }
        return (controller, controller.ensureWindow())
    }

    /// What the window shows in its content area, with the given appearance.
    private func renderContent(of window: NSWindow, dark: Bool = false) throws -> NSBitmapImageRep {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    /// What the window shows once the layout has settled: renders again and again, 20 ms apart, until two in
    /// a row are the same, and returns the last. The first layout of a tab can differ from the next one (a
    /// scroll view's content is laid out against its scroller only on a later pass), so a single render is
    /// not a fair picture of the tab. At most 250 polls: a layout that never settles gives the last render. The
    /// budget counts polls that ran, not seconds, because a full test run can block the main thread for seconds
    /// at a time; the wall-clock limit of 120 s only stops a hang.
    private func settledContent(of window: NSWindow, dark: Bool = false) async throws -> NSBitmapImageRep {
        let limit = ContinuousClock.now.advanced(by: .seconds(120))
        var previous = try renderContent(of: window, dark: dark)
        for _ in 0..<250 {
            guard ContinuousClock.now < limit else { break }
            try await Task.sleep(for: .milliseconds(20))
            let next = try renderContent(of: window, dark: dark)
            if png(next) == png(previous) { return next }
            previous = next
        }
        return previous
    }

    /// Waits, on the main actor, until `reached` holds and the window's frame has stayed the same for three
    /// polls in a row: a poll every 20 ms, and at most 250 polls. The window follows the model's tab on a later
    /// turn of the main queue and resizes in an animation, which when the machine is busy can take longer
    /// than any fixed pause. The budget counts the polls that ran, not seconds: a full test run can block the
    /// main thread for seconds at a time, and the time spent blocked must not use the budget up. A window that
    /// never gets there does not fail the wait: the expectations after it do, and say what the window is. The
    /// wall-clock limit of 120 s only stops a hang.
    private func waitUntilSettled(_ window: NSWindow, reached: () -> Bool) async throws {
        let limit = ContinuousClock.now.advanced(by: .seconds(120))
        var previous: CGRect?
        var steady = 0
        for _ in 0..<250 {
            guard ContinuousClock.now < limit else { return }
            let frame = window.frame
            steady = (frame == previous && reached()) ? steady + 1 : 0
            previous = frame
            if steady == 3 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Whether the General tab is the one shown and the window is as tall as the tab asks to be. False until
    /// the tab has been laid out and its height reported.
    private func isGeneralFitted(_ controller: SettingsWindowController, _ window: NSWindow) -> Bool {
        guard let content = controller.content, content.tab == .general else { return false }
        let asked = content.generalFittingHeight
        guard asked > 0 else { return false }
        return abs(window.contentRect(forFrameRect: window.frame).size.height - asked) < 1
    }

    /// Whether the bitmap shows more than one colour, which a view that failed to draw does not.
    private func hasContent(_ bitmap: NSBitmapImageRep) -> Bool {
        guard let first = bitmap.colorAt(x: 0, y: 0) else { return false }
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                if let color = bitmap.colorAt(x: x, y: y), color != first { return true }
            }
        }
        return false
    }

    /// The bitmap as PNG data, to compare two renderings.
    private func png(_ bitmap: NSBitmapImageRep) -> Data? {
        bitmap.representation(using: .png, properties: [:])
    }

    private func keep(_ bitmap: NSBitmapImageRep, as name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PICCOLO_RENDER_DIR"],
            let data = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: directory).appending(path: "\(name).png"))
    }

    // MARK: The window

    private static let leftHalf = KeyBinding(
        id: UIFixture.idA, action: .placeWindow(.preset(.leftHalf)), shortcut: UIFixture.f13)
    private static let custom = KeyBinding(
        id: UIFixture.idB,
        action: .placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1))))
    private static let grid = KeyBinding(
        id: UIFixture.idC, action: .arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2)),
        shortcut: Shortcut(keyCode: 0, modifiers: [.control, .option]))
    private static let display = KeyBinding(action: .moveToDisplay(.next))
    private static let divider = KeyBinding(action: .moveDivider(.left))
    private static let swap = KeyBinding(action: .swapWindow(.right))

    @Test("the whole window renders in light and dark appearance, on both tabs, with every kind of binding")
    func wholeWindow() async throws {
        let all = [Self.leftHalf, Self.custom, Self.grid, Self.display, Self.divider, Self.swap]
        for (name, dark) in [("light", false), ("dark", true)] {
            let model = model(all, issues: ["bindings[4] shortcut was refused: taken by the system"])
            let (controller, window) = makeWindow(model)
            try await waitUntilSettled(window) { controller.content?.tab == .shortcuts }
            let shortcutsFrame = window.frame
            for tab in SettingsTab.allCases {
                model.tab = tab
                // The tab is shown before its window has the size it needs: wait for that size too.
                switch tab {
                case .shortcuts:
                    try await waitUntilSettled(window) {
                        controller.content?.tab == .shortcuts && window.frame == shortcutsFrame
                    }
                case .general:
                    try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
                }
                let bitmap = try renderContent(of: window, dark: dark)
                #expect(hasContent(bitmap), "the \(tab) tab is blank in \(name) appearance")
                keep(bitmap, as: "window-\(tab)-\(name)")
            }
            withExtendedLifetime(controller) {}
        }
    }

    @Test("the window shows the tab the model names")
    func followsTheModel() async throws {
        let model = model([Self.leftHalf, Self.custom])
        let (controller, window) = makeWindow(model)
        orderFrontInvisibly(window)
        defer {
            window.orderOut(nil)
            withExtendedLifetime(controller) {}
        }
        try await waitUntilSettled(window) { controller.content?.tab == .shortcuts }
        let shortcutsFrame = window.frame
        let shortcuts = try await settledContent(of: window)

        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
        let general = try await settledContent(of: window)
        #expect(png(shortcuts) != png(general), "the window looks the same on the General tab as on the Shortcuts tab")

        model.tab = .shortcuts
        try await waitUntilSettled(window) {
            controller.content?.tab == .shortcuts && window.frame == shortcutsFrame
        }
        let again = try await settledContent(of: window)
        #expect(png(again) == png(shortcuts), "going back to the Shortcuts tab did not bring the same window back")
    }

    @Test("the General tab renders, with and without Accessibility")
    func generalTab() throws {
        let granted = try render(GeneralTab(model: model([]), host: host))
        #expect(hasContent(granted))
        keep(granted, as: "general-granted")

        var missing = host
        missing.isAccessibilityTrusted = { false }
        let missingModel = model([])
        missingModel.setResizeStep(0.9)
        let notGranted = try render(GeneralTab(model: missingModel, host: missing), dark: true)
        #expect(hasContent(notGranted))
        keep(notGranted, as: "general-not-granted-dark")
    }

    @Test("the General tab renders the language picker, with the restart note and the button when a restart is needed")
    func generalTabLanguage() throws {
        // The app runs in English, and the system's language is English too.
        let language = FakeLanguage(stored: .system, running: .en, system: .en)
        let model = model([], language: language)
        let plain = try render(GeneralTab(model: model, host: host))
        #expect(hasContent(plain))
        #expect(!model.restartRequired)
        keep(plain, as: "general-language")

        model.setLanguage(.zhHans)
        #expect(model.restartRequired)
        let restart = try render(GeneralTab(model: model, host: host))
        #expect(hasContent(restart))
        #expect(png(restart) != png(plain), "the tab looks the same with and without the restart note and button")
        keep(restart, as: "general-language-restart")

        // Back to the language the app runs in: the note and the button go.
        model.setLanguage(.en)
        #expect(png(try render(GeneralTab(model: model, host: host))) != png(restart))

        // A restart that cannot be arranged says so under the button.
        model.setLanguage(.zhHans)
        language.restartFailure = RestartError(message: "no helper")
        model.restartNow()
        let failed = try render(GeneralTab(model: model, host: host))
        #expect(png(failed) != png(restart), "the failed restart shows no message")
        keep(failed, as: "general-language-restart-error")
    }

    @Test("the General tab fits its window without scrolling in every state: plain, a restart row, a login item to approve, problems with the config")
    func generalTabFits() async throws {
        let states: [(String, SettingsModel)] = [
            ("plain", model([])),
            ("restart", {
                let model = model([], language: FakeLanguage(stored: .system, running: .en, system: .en))
                model.setLanguage(.zhHans)
                return model
            }()),
            ("approval", model([], loginItem: FakeLoginItem(status: .requiresApproval))),
            ("problems", model([], issues: ["bindings[1] shortcut was refused: taken by the system"])),
        ]
        var heights: [String: CGFloat] = [:]
        for (name, model) in states {
            model.tab = .general
            let (controller, window) = makeWindow(model)
            try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
            let content = try #require(controller.content)
            let height = window.contentRect(forFrameRect: window.frame).size.height
            heights[name] = height
            #expect(content.contentFits, "the General tab scrolls in a window as tall as it asks for, state \(name)")
            #expect(abs(height - content.generalFittingHeight) < 1, "state \(name): window \(height) pt, tab \(content.generalFittingHeight) pt")
        }
        let plain = try #require(heights["plain"])
        #expect(try #require(heights["restart"]) > plain, "the restart row does not make the tab taller")
        #expect(try #require(heights["approval"]) > plain, "the approval note does not make the tab taller")
    }

    @Test("the General tab renders every login item status, and the approval note and the error change what it shows")
    func generalTabLoginItem() throws {
        var images: [LoginItemStatus: Data] = [:]
        for status in LoginItemStatus.allCases {
            let model = model([], loginItem: FakeLoginItem(status: status))
            for dark in [false, true] {
                let bitmap = try render(GeneralTab(model: model, host: host), dark: dark)
                #expect(hasContent(bitmap), "the General tab is blank with the status \(status)")
                keep(bitmap, as: "general-login-\(status.rawValue)\(dark ? "-dark" : "")")
                if !dark { images[status] = png(bitmap) }
            }
        }
        #expect(images[.enabled] != images[.notRegistered], "the switch looks the same on and off")
        #expect(
            images[.requiresApproval] != images[.enabled],
            "requires approval looks like enabled: the note and the button are missing")
        #expect(images[.notRegistered] == images[.notFound], "not found changes the tab although it has no note")

        // A refused change shows its message under the switch and puts the switch back.
        let refusing = FakeLoginItem(status: .notRegistered)
        refusing.failure = LoginItemError(message: "Operation not permitted")
        let failing = model([], loginItem: refusing)
        failing.setLaunchAtLogin(true)
        #expect(failing.loginItemError != nil)
        let failed = try render(GeneralTab(model: failing, host: host))
        #expect(hasContent(failed))
        keep(failed, as: "general-login-error")
        #expect(png(failed) != images[.notRegistered], "the failed change does not show its message")
    }
}
