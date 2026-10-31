import AppKit
import SwiftUI
import Testing

import PiccoloCore

@testable import PiccoloUI

/// The General tab as the Settings window shows it: its groups, a rejected value under its field, a
/// window-level error above the version, the fill order pictures and the config problems, which the tab
/// leaves to the Shortcuts tab. Like the other render tests, the views are drawn into bitmaps off screen,
/// and nothing is shown.
@MainActor
@Suite("General tab")
struct GeneralTabTests {
    private static let size = NSSize(width: 640, height: 900)

    private func host(trusted: Bool = true) -> SettingsHost {
        SettingsHost(
            isAccessibilityTrusted: { trusted },
            openAccessibilitySettings: {},
            revealConfigInFinder: {},
            appVersion: "0.1.0 (1)")
    }

    private func model(issues: [String] = [], language: FakeLanguage = FakeLanguage()) -> SettingsModel {
        let backend = InMemorySettingsBackend(config: Config(bindings: []), issues: issues)
        return SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: language) { _ in nil }
    }

    /// Renders the General tab for `model` at the size of the window and returns the bitmap.
    private func render(_ model: SettingsModel, trusted: Bool = true, dark: Bool = false) throws -> NSBitmapImageRep {
        let view = GeneralTab(model: model, host: host(trusted: trusted))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered,
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

    private static let appearances: [(name: String, dark: Bool)] = [("light", false), ("dark", true)]

    @Test("the tab renders with Accessibility granted and not granted, in light and dark appearance")
    func accessibility() throws {
        for (name, dark) in Self.appearances {
            let granted = try render(model(), trusted: true, dark: dark)
            let missing = try render(model(), trusted: false, dark: dark)
            #expect(hasContent(granted), "the tab is blank with Accessibility granted in \(name) appearance")
            #expect(hasContent(missing), "the tab is blank without Accessibility in \(name) appearance")
            #expect(png(granted) != png(missing), "a missing grant looks like a granted one in \(name) appearance")
        }
    }

    @Test("the restart row appears when a restart is needed, in light and dark appearance")
    func restartRow() throws {
        for (name, dark) in Self.appearances {
            let language = FakeLanguage(stored: .system, running: .en, system: .en)
            let model = model(language: language)
            let plain = try render(model, dark: dark)
            model.setLanguage(.zhHans)
            #expect(model.restartRequired)
            let restart = try render(model, dark: dark)
            #expect(hasContent(restart), "the tab is blank with the restart row in \(name) appearance")
            #expect(png(restart) != png(plain), "the restart row does not show in \(name) appearance")
        }
    }

    @Test("a rejected window gap shows under its field, in light and dark appearance")
    func gapError() throws {
        for (name, dark) in Self.appearances {
            let model = model()
            let clean = try render(model, dark: dark)
            #expect(!model.setGap(100))
            #expect(model.errorTarget == .field(.gap))
            let rejected = try render(model, dark: dark)
            #expect(hasContent(rejected), "the tab is blank with a rejected gap in \(name) appearance")
            #expect(png(rejected) != png(clean), "the rejected gap shows nothing in \(name) appearance")
        }
    }

    @Test("a rejected linked resize step shows under its field, in light and dark appearance")
    func resizeStepError() throws {
        for (name, dark) in Self.appearances {
            let model = model()
            let clean = try render(model, dark: dark)
            #expect(!model.setResizeStep(0.9))
            #expect(model.errorTarget == .field(.resizeStep))
            let rejected = try render(model, dark: dark)
            #expect(hasContent(rejected), "the tab is blank with a rejected resize step in \(name) appearance")
            #expect(png(rejected) != png(clean), "the rejected resize step shows nothing in \(name) appearance")
        }
    }

    @Test("a window-level error shows above the version, in light and dark appearance")
    func windowError() throws {
        for (name, dark) in Self.appearances {
            let backend = InMemorySettingsBackend(config: Config(bindings: []))
            let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage()) { _ in
                nil
            }
            let clean = try render(model, dark: dark)
            backend.failure = "the disk is full"
            #expect(!model.setAnimation(.slow))
            #expect(model.errorTarget == .window)
            let rejected = try render(model, dark: dark)
            #expect(hasContent(rejected), "the tab is blank with a window error in \(name) appearance")
            #expect(png(rejected) != png(clean), "the window error shows nothing in \(name) appearance")
        }
    }

    @Test("a refused save of the window animation names the window until the next accepted change")
    func refusedAnimationNamesTheWindow() {
        let backend = InMemorySettingsBackend(config: Config(bindings: []))
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage()) { _ in nil }
        #expect(model.errorTarget == nil)

        backend.failure = "the disk is full"
        #expect(!model.setAnimation(.slow))
        #expect(model.errorTarget == .window)
        #expect(model.error != nil)
        #expect(model.animation == .fast)

        backend.failure = nil
        #expect(model.setAnimation(.slow))
        #expect(model.errorTarget == nil)
        #expect(model.error == nil)
    }

    @Test("rows first and columns first render with their own picture selected, in light and dark appearance")
    func fillOrders() throws {
        for (name, dark) in Self.appearances {
            let model = model()
            let rows = try render(model, dark: dark)
            #expect(model.setGridFillOrder(.columns))
            let columns = try render(model, dark: dark)
            #expect(hasContent(columns), "the tab is blank with columns first in \(name) appearance")
            #expect(png(columns) != png(rows), "rows first and columns first look the same in \(name) appearance")
            #expect(model.setGridFillOrder(.rows))
            #expect(png(try render(model, dark: dark)) == png(rows), "rows first does not come back in \(name) appearance")
        }
    }

    @Test("the config problems are not shown on the General tab")
    func configProblemsStayOnTheShortcutsTab() throws {
        let clean = try render(model())
        let problems = try render(model(issues: ["bindings[4] shortcut was refused: taken by the system"]))
        #expect(png(problems) == png(clean), "the General tab shows the problems of the config file")
    }

    @Test("a rejected resize step is called the linked resize step, in English")
    func resizeStepMessage() throws {
        let english = try #require(AppLanguage.en.textBundle)
        let rejected = SettingsMessages.describe(
            .outOfRange(field: "resizeStep", rule: "must be > 0 and <= 0.5"), bundle: english)
        #expect(rejected == "The linked resize step must be more than 0% and at most 50%.")
        let notFinite = SettingsMessages.describe(.notFinite(field: "resizeStep"), bundle: english)
        #expect(notFinite == "The linked resize step must be a number.")

        let model = model()
        #expect(!model.setResizeStep(0.9))
        #expect(model.error == SettingsMessages.describe(.outOfRange(field: "resizeStep", rule: "must be > 0 and <= 0.5")))
    }
}
