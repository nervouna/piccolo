import AppKit
import PiccoloCore
import Testing

@testable import PiccoloUI

/// The Settings window's toolbar tabs, the size of each tab and the focus, with the real window and
/// its views but off screen: the window is never ordered front, so nothing is shown and no
/// permission is involved. The screen is a fixed visible frame, so that the machine's does not matter.
@MainActor
@Suite("Settings window tabs")
struct SettingsWindowTabsTests {
    private static let bigScreen = CGRect(x: 0, y: 0, width: 2000, height: 1600)

    private let host = SettingsHost(
        isAccessibilityTrusted: { true },
        openAccessibilitySettings: {},
        revealConfigInFinder: {},
        appVersion: "0.1.0 (1)")

    /// The controllers the tests made: a controller follows its model only while it lives, and a test
    /// that does not use its controller would let it go.
    private static var made: [SettingsWindowController] = []

    /// A window controller over a model with a few bindings, saving its frame under a name of its own.
    private func makeController(
        language: FakeLanguage = FakeLanguage(), screen: CGRect = SettingsWindowTabsTests.bigScreen,
        frameName: String = "PiccoloSettingsTests.\(UUID().uuidString)"
    ) -> (controller: SettingsWindowController, model: SettingsModel, window: NSWindow) {
        let bindings = [
            KeyBinding(
                id: UIFixture.idA, action: .placeWindow(.preset(.leftHalf)), shortcut: UIFixture.f13),
            KeyBinding(id: UIFixture.idB, action: .placeWindow(.preset(.rightHalf))),
        ]
        let model = SettingsModel(
            backend: InMemorySettingsBackend(config: Config(bindings: bindings)), loginItem: FakeLoginItem(),
            language: language)
        let controller = SettingsWindowController(model: model, host: host, frameName: frameName)
        controller.visibleFrameProvider = { _ in screen }
        // A window that is not on screen does not animate: the frames are the ones asked for at once.
        controller.animatesFrameChanges = false
        let window = controller.ensureWindow()
        Self.made.append(controller)
        return (controller, model, window)
    }

    /// Waits, on the main actor, until `reached` holds and the window's frame has stayed the same for three
    /// polls in a row: a poll every 20 ms, and at most 250 polls. The view of a tab is laid out and its size
    /// reported on later turns of the main queue, so the window moves after the change that asked for it,
    /// and when the machine is busy that can take longer than any fixed pause. The budget counts the polls that
    /// ran, not seconds: a full test run can block the main thread for seconds at a time, and the time spent
    /// blocked must not use the budget up. A window that never gets there does not fail the wait: the
    /// expectations after it do, and say what the window is. The wall-clock limit of 120 s only stops a hang.
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

    /// Whether the General tab is the one shown and the window is as tall as the tab asks to be, or as tall
    /// as `screen` allows when that is less. False until the tab has been laid out and its height reported.
    private func isGeneralFitted(
        _ controller: SettingsWindowController, _ window: NSWindow,
        screen: CGRect = SettingsWindowTabsTests.bigScreen
    ) -> Bool {
        guard let content = controller.content, content.tab == .general else { return false }
        let asked = content.generalFittingHeight
        guard asked > 0 else { return false }
        let room = window.contentRect(forFrameRect: screen).height
        return abs(contentSize(of: window).height - min(asked, room)) < 1
    }

    private func contentSize(of window: NSWindow) -> CGSize {
        window.contentRect(forFrameRect: window.frame).size
    }

    // MARK: Toolbar

    @Test("the toolbar has Shortcuts with the keyboard symbol and General with the gear, labelled, in the preference style")
    func toolbarItems() throws {
        let (controller, _, window) = makeController()
        #expect(window.toolbarStyle == .preference)
        let toolbar = try #require(window.toolbar)
        #expect(toolbar.allowsUserCustomization == false)
        #expect(toolbar.displayMode == .iconAndLabel)

        let identifiers = controller.toolbarDefaultItemIdentifiers(toolbar)
        #expect(identifiers.map(\.rawValue) == ["shortcuts", "general"])
        #expect(controller.toolbarSelectableItemIdentifiers(toolbar) == identifiers)
        #expect(toolbar.centeredItemIdentifiers == Set(identifiers))

        let expected: [(SettingsTab, String)] = [(.shortcuts, "keyboard"), (.general, "gearshape")]
        for (identifier, (tab, symbol)) in zip(identifiers, expected) {
            let item = try #require(
                controller.toolbar(toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: true))
            #expect(item.label == SettingsTabText.title(of: tab))
            #expect(item.image != nil, "\(tab) has no image")
            #expect(SettingsTabText.symbolName(of: tab) == symbol)
        }
        #expect(SettingsTabText.title(of: .shortcuts) == "Shortcuts")
        #expect(SettingsTabText.title(of: .general) == "General")
    }

    @Test("the window title is the selected tab's name and the tab's toolbar item is selected, following the model both ways")
    func titleFollowsTheTab() async throws {
        let (controller, model, window) = makeController()
        let toolbar = try #require(window.toolbar)
        #expect(window.title == "Shortcuts")
        #expect(toolbar.selectedItemIdentifier?.rawValue == "shortcuts")
        #expect(controller.content?.tab == .shortcuts)

        model.tab = .general
        try await waitUntilSettled(window) { controller.content?.tab == .general }
        #expect(window.title == "General")
        #expect(toolbar.selectedItemIdentifier?.rawValue == "general")
        #expect(controller.content?.tab == .general)

        model.tab = .shortcuts
        try await waitUntilSettled(window) { controller.content?.tab == .shortcuts }
        #expect(window.title == "Shortcuts")
        #expect(toolbar.selectedItemIdentifier?.rawValue == "shortcuts")

        // A click on a toolbar item sets the model's tab.
        let generalItem = try #require(
            controller.toolbar(
                toolbar, itemForItemIdentifier: NSToolbarItem.Identifier("general"), willBeInsertedIntoToolbar: true))
        _ = try #require(generalItem.target).perform(generalItem.action, with: generalItem)
        #expect(model.tab == .general)
        #expect(window.title == "General", "the click is answered at once")
    }

    @Test("a window created while the model is on the General tab opens on it")
    func opensOnTheModelsTab() {
        let model = SettingsModel(
            backend: InMemorySettingsBackend(config: Config(bindings: [])), loginItem: FakeLoginItem(),
            language: FakeLanguage())
        model.tab = .general
        let controller = SettingsWindowController(
            model: model, host: host, frameName: "PiccoloSettingsTests.\(UUID().uuidString)")
        controller.visibleFrameProvider = { _ in Self.bigScreen }
        let window = controller.ensureWindow()
        #expect(window.title == "General")
        #expect(window.toolbar?.selectedItemIdentifier?.rawValue == "general")
        #expect(controller.content?.tab == .general)
    }

    @Test("changing the tab forgets the error of the tab it was made on")
    func tabChangeClearsTheError() async throws {
        let (controller, model, window) = makeController()
        // A shortcut that cannot be a global one is refused, with its reason under the row.
        model.beginRecording(.builtIn(.placeWindow(.preset(.rightHalf))))
        model.record(Shortcut(keyCode: 0, modifiers: [.shift]))
        #expect(model.error != nil)
        model.tab = .general
        try await waitUntilSettled(window) { controller.content?.tab == .general }
        #expect(model.error == nil)
    }

    // MARK: Sizes

    @Test("the Shortcuts tab opens at 640 × 720, resizable down to 560 × 480; the General tab cannot be resized")
    func shortcutsSize() async throws {
        let (controller, model, window) = makeController()
        #expect(contentSize(of: window) == CGSize(width: 640, height: 720))
        #expect(window.contentMinSize == CGSize(width: 560, height: 480))
        #expect(window.contentMaxSize.height > 10_000)
        #expect(window.styleMask.contains(.resizable))
        #expect(window.standardWindowButton(.zoomButton)?.isEnabled == true)

        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
        #expect(window.contentMinSize == window.contentMaxSize, "the General tab can be resized")
        #expect(window.standardWindowButton(.zoomButton)?.isEnabled == false)
    }

    @Test("the General tab is 640 wide and as tall as its content asks, and fits without scrolling")
    func generalSize() async throws {
        let (controller, model, window) = makeController()
        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
        let content = try #require(controller.content)

        let asked = content.generalFittingHeight
        #expect(asked > 300, "the General tab asks for only \(asked) pt")
        let size = contentSize(of: window)
        #expect(size.width == 640)
        #expect(abs(size.height - asked) < 1, "the window's content is \(size.height) pt high, the tab asks for \(asked)")
        #expect(content.contentFits, "the General tab scrolls in a window as tall as it asks for")
    }

    @Test("the General tab's window grows when the restart row appears and shrinks when it goes")
    func generalFollowsItsContent() async throws {
        let language = FakeLanguage(stored: .system, running: .en, system: .en)
        let (controller, model, window) = makeController(language: language)
        // SwiftUI updates a view that is in a window on screen: this one is on screen but invisible, and
        // takes no focus and no clicks.
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        window.setFrameTopLeftPoint(CGPoint(x: 300, y: 1400))
        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
        let content = try #require(controller.content)
        let plain = contentSize(of: window).height
        let top = window.frame.maxY

        model.setLanguage(.zhHans)
        #expect(model.restartRequired)
        try await waitUntilSettled(window) {
            content.generalFittingHeight > plain + 20 && isGeneralFitted(controller, window) && content.contentFits
        }
        let withRestart = contentSize(of: window).height
        #expect(withRestart > plain + 20, "the window is \(withRestart) pt high with the restart row, \(plain) without")
        #expect(abs(withRestart - content.generalFittingHeight) < 1)
        #expect(content.contentFits)
        #expect(window.frame.maxY == top, "the top edge moved")

        model.setLanguage(.en)
        try await waitUntilSettled(window) {
            abs(contentSize(of: window).height - plain) < 1
        }
        #expect(abs(contentSize(of: window).height - plain) < 1, "the window did not shrink back")
    }

    @Test("switching tabs keeps the top-left corner, and back gives the Shortcuts frame back")
    func topLeftStaysAndShortcutsFrameComesBack() async throws {
        let (controller, model, window) = makeController()
        window.setFrameTopLeftPoint(CGPoint(x: 300, y: 1400))
        let shortcuts = window.frame

        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
        #expect(window.frame.maxY == shortcuts.maxY, "the top edge moved")
        #expect(window.frame.minX == shortcuts.minX, "the left edge moved")
        #expect(window.frame.height != shortcuts.height)

        model.tab = .shortcuts
        try await waitUntilSettled(window) { controller.content?.tab == .shortcuts && window.frame == shortcuts }
        #expect(window.frame == shortcuts)
    }

    @Test("the size the person gives the Shortcuts tab is the one it comes back to")
    func shortcutsSizeIsRemembered() async throws {
        let (controller, model, window) = makeController()
        window.setFrameTopLeftPoint(CGPoint(x: 300, y: 1400))
        window.setContentSize(CGSize(width: 700, height: 600))
        window.setFrameTopLeftPoint(CGPoint(x: 300, y: 1400))
        let shortcuts = window.frame

        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
        model.tab = .shortcuts
        try await waitUntilSettled(window) {
            controller.content?.tab == .shortcuts && window.frame == shortcuts
        }
        #expect(contentSize(of: window) == CGSize(width: 700, height: 600))
        #expect(window.frame == shortcuts)
    }

    /// What is saved under `name`: the system's string for a window frame ("x y width height" and the
    /// screen's), as its first four numbers. Nil when nothing is saved.
    private func savedFrame(named name: String) -> CGRect? {
        guard let string = UserDefaults.standard.string(forKey: "NSWindow Frame \(name)") else { return nil }
        let numbers = string.split(separator: " ").compactMap { Double($0) }
        guard numbers.count >= 4 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    @Test("the Shortcuts tab's frame is saved under its own name when the person changes it, and its size restored by the next window")
    func shortcutsFrameIsSaved() async throws {
        let name = "PiccoloSettingsTests.\(UUID().uuidString)"
        defer { NSWindow.removeFrame(usingName: name) }
        let (_, _, window) = makeController(frameName: name)
        #expect(savedFrame(named: name) == nil, "opening the window saved the frame the person did not choose")

        window.setContentSize(CGSize(width: 720, height: 500))
        window.setFrameTopLeftPoint(CGPoint(x: 300, y: 1400))
        let saved = try #require(savedFrame(named: name), "the person's resize and move saved no frame")
        #expect(saved.width == 720)
        #expect(saved.minX == 300)

        let (_, _, next) = makeController(frameName: name)
        #expect(contentSize(of: next) == CGSize(width: 720, height: 500))
    }

    @Test("the General tab's frame is not saved: it follows its content, wherever the window is")
    func generalFrameIsNotSaved() async throws {
        let name = "PiccoloSettingsTests.\(UUID().uuidString)"
        defer { NSWindow.removeFrame(usingName: name) }
        let (controller, model, window) = makeController(frameName: name)
        window.setContentSize(CGSize(width: 720, height: 500))
        window.setFrameTopLeftPoint(CGPoint(x: 300, y: 1400))
        let saved = try #require(savedFrame(named: name))

        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
        window.setFrameTopLeftPoint(CGPoint(x: 500, y: 1200))
        #expect(window.frame.size != saved.size)
        #expect(savedFrame(named: name) == saved, "the General tab's frame was saved")

        model.tab = .shortcuts
        try await waitUntilSettled(window) {
            controller.content?.tab == .shortcuts && contentSize(of: window) == CGSize(width: 720, height: 500)
        }
        #expect(contentSize(of: window) == CGSize(width: 720, height: 500))
    }

    @Test("no tab makes the window taller than the visible frame of its screen; a tab that does not fit scrolls")
    func neverTallerThanTheScreen() async throws {
        let small = CGRect(x: 0, y: 0, width: 1280, height: 600)
        let (controller, model, window) = makeController(screen: small)
        let content = try #require(controller.content)
        #expect(window.frame.height <= small.height)
        #expect(small.contains(window.frame), "the Shortcuts window is not inside the screen: \(window.frame)")

        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window, screen: small) }
        #expect(window.frame.height <= small.height)
        #expect(small.contains(window.frame), "the General window is not inside the screen: \(window.frame)")
        #expect(
            content.generalFittingHeight > contentSize(of: window).height, "the General tab fits in 600 pt, the test is moot")
        #expect(!content.contentFits, "a General tab taller than the window does not scroll")

        model.tab = .shortcuts
        try await waitUntilSettled(window) { controller.content?.tab == .shortcuts }
        #expect(small.contains(window.frame))
    }

    // MARK: Focus

    @Test("the first responder is told apart: the window itself or nothing, a text field and its editor, anything else")
    func firstResponderKinds() throws {
        let (controller, _, window) = makeController()
        let contentView = try #require(window.contentView)
        #expect(controller.firstResponderKind == .none)

        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 22))
        let other = NSView(frame: NSRect(x: 10, y: 50, width: 100, height: 22))
        contentView.addSubview(field)
        contentView.addSubview(other)

        #expect(window.makeFirstResponder(field))
        #expect(controller.firstResponderKind == .textField, "the field editor is \(String(describing: window.firstResponder))")
        #expect(window.makeFirstResponder(nil))
        #expect(controller.firstResponderKind == .none)
        #expect(window.firstResponder === window)

        // A view that takes the focus is neither.
        final class Focusable: NSView {
            override var acceptsFirstResponder: Bool { true }
        }
        let focusable = Focusable(frame: NSRect(x: 10, y: 90, width: 100, height: 22))
        contentView.addSubview(focusable)
        #expect(window.makeFirstResponder(focusable))
        #expect(controller.firstResponderKind == .other)
    }

    @Test("changing the tab leaves no text field with the focus")
    func tabChangeClearsTheFocus() async throws {
        let (controller, model, window) = makeController()
        let contentView = try #require(window.contentView)
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 22))
        contentView.addSubview(field)
        #expect(window.makeFirstResponder(field))
        #expect(controller.firstResponderKind == .textField)

        model.tab = .general
        try await waitUntilSettled(window) { isGeneralFitted(controller, window) }
        #expect(controller.firstResponderKind == .none)
    }
}
