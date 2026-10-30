import AppKit
import SwiftUI
import Testing

import PiccoloCore

@testable import PiccoloUI

/// Lays the Shortcuts tab out off screen, as the window does, and measures the list.
@MainActor
@Suite("Shortcuts tab layout")
struct SettingsListLayoutTests {
    private func listHeight(contentHeight: CGFloat, selectFirst: Bool = true) throws -> (height: CGFloat, rowHeight: CGFloat) {
        let backend = InMemorySettingsBackend(config: Config.defaultShortcuts)
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage())
        if !selectFirst { model.selectedBindingID = nil }
        // The window's content: the tab view pads the tab by 12 pt and draws a tab strip of about 30 pt.
        let size = NSSize(width: 640, height: contentHeight)
        let hosting = NSHostingView(rootView: ShortcutsTab(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let table = try #require(Self.firstTable(in: hosting))
        let scroll = try #require(table.enclosingScrollView)
        return (scroll.frame.height, table.rowHeight)
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews {
            if let found = firstTable(in: sub) { return found }
        }
        return nil
    }

    @Test("with the default window size the list shows at least 12 rows")
    func tallEnough() throws {
        let (height, row) = try listHeight(contentHeight: 880 - 12 * 2 - 30)
        #expect(height / row >= 12, "list \(height) pt, row \(row) pt")
    }

    @Test("the list shrinks first when the window gets smaller")
    func shrinks() throws {
        let tall = try listHeight(contentHeight: 880 - 54).height
        let small = try listHeight(contentHeight: 600).height
        #expect(small < tall)
        #expect(small >= 4 * 22, "list \(small) pt")
    }
}
