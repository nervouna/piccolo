import AppKit
import SwiftUI
import Testing

import PiccoloCore

@testable import PiccoloUI

/// Draws the Settings views into bitmaps, off screen, as a smoke test that every state of the
/// window can be built and laid out. Nothing is shown and no permission is involved: the views
/// draw themselves into a bitmap of their own hosting view.
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

    /// Renders `view` at `size` with the given appearance and returns the bitmap.
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
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
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

    @Test("the whole window renders in light and dark appearance, with every kind of binding")
    func wholeWindow() throws {
        let all = [Self.leftHalf, Self.custom, Self.grid, Self.display, Self.divider]
        for (name, dark) in [("light", false), ("dark", true)] {
            let model = model(all, issues: ["bindings[4] shortcut was refused: taken by the system"])
            let bitmap = try render(SettingsView(model: model, host: host), dark: dark)
            #expect(hasContent(bitmap), "the window is blank in \(name) appearance")
            keep(bitmap, as: "window-\(name)")
        }
    }

    @Test("the window shows the tab and the selected binding the model names")
    func followsTheModel() throws {
        let model = model([Self.leftHalf, Self.custom])
        let shortcuts = try render(SettingsView(model: model, host: host))

        model.tab = .general
        let general = try render(SettingsView(model: model, host: host))
        #expect(png(shortcuts) != png(general), "the window looks the same on the General tab as on the Shortcuts tab")

        model.tab = .shortcuts
        let again = try render(SettingsView(model: model, host: host))
        #expect(png(again) == png(shortcuts), "going back to the Shortcuts tab did not bring the same window back")

        model.selectedBindingID = UIFixture.idA
        let first = try render(SettingsView(model: model, host: host))
        model.selectedBindingID = UIFixture.idB
        let second = try render(SettingsView(model: model, host: host))
        #expect(png(first) != png(second), "the window looks the same with the first and the second binding selected")
    }

    @Test("the Shortcuts tab renders each kind of action selected")
    func eachAction() throws {
        let bindings: [(String, KeyBinding)] = [
            ("preset", Self.leftHalf), ("custom", Self.custom), ("grid", Self.grid),
            ("display", Self.display), ("divider", Self.divider),
        ]
        for (name, binding) in bindings {
            let model = model([binding])
            model.selectedBindingID = binding.id
            let bitmap = try render(ShortcutsTab(model: model))
            #expect(hasContent(bitmap), "the \(name) editor is blank")
            keep(bitmap, as: "shortcuts-\(name)")
        }
    }

    @Test("the Shortcuts tab renders when empty, while recording and with an error")
    func otherStates() throws {
        let empty = try render(ShortcutsTab(model: model([])))
        #expect(hasContent(empty))
        keep(empty, as: "shortcuts-empty")

        let recording = model([Self.leftHalf, Self.custom])
        recording.beginRecording(UIFixture.idB)
        let recordingBitmap = try render(ShortcutsTab(model: recording))
        #expect(hasContent(recordingBitmap))
        keep(recordingBitmap, as: "shortcuts-recording")

        let failing = model([Self.leftHalf, Self.custom])
        failing.setShortcut(UIFixture.idB, to: UIFixture.f13)
        #expect(failing.error != nil)
        let errorBitmap = try render(ShortcutsTab(model: failing))
        #expect(hasContent(errorBitmap))
        keep(errorBitmap, as: "shortcuts-error")
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

    @Test("the General tab fits the default size of the window without scrolling")
    func generalTabFits() {
        let hosting = NSHostingView(rootView: GeneralTab(model: model([]), host: host))
        hosting.frame = NSRect(origin: .zero, size: Self.size)

        // The tab strip and the padding around the tab take about 60 pt.
        let needed = hosting.fittingSize.height + 70
        #expect(
            needed <= SettingsWindowController.defaultContentSize.height,
            "the General tab needs about \(needed) pt, the window opens \(SettingsWindowController.defaultContentSize.height) pt high")
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
