import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import Testing

@testable import PiccoloUI

/// Acceptance tests for the chrome of the Settings window: the toolbar tabs, the size of each tab, and
/// the keyboard focus when the window opens or the tab changes. They read the window from
/// `settings.state` (`windowFrame`, `windowTitle`, `firstResponder`, `contentFits`) and put it on each
/// display with `settings.moveWindow`.
///
/// Every test runs on a temporary config (see ``withSettingsSession(_:inNewSubfolder:_:)``), and the
/// window is moved with `settings.moveWindow`, which saves nothing, so that the frame the person left
/// the Shortcuts tab at is not touched.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Settings window chrome")
    struct SettingsWindowChrome {
        private let piccolo = PiccoloClient()

        /// How long the window is watched after it has come up, for a focus that arrives late.
        private static let focusWatch: Duration = .milliseconds(600)

        /// What `settings.state` says about the window.
        private struct Chrome {
            var isOpen: Bool
            var isKey: Bool
            var tab: String
            var effectiveLanguage: String
            /// The window's frame in canonical space, when it is open.
            var frame: CGRect?
            var title: String?
            /// `none`, `textField` or `other`.
            var firstResponder: String
            var contentFits: Bool?

            init(_ state: JSONValue) throws {
                guard let isOpen = state["isOpen"]?.boolValue, let isKey = state["isKey"]?.boolValue,
                    let tab = state["tab"]?.stringValue, let language = state["effectiveLanguage"]?.stringValue,
                    let firstResponder = state["firstResponder"]?.stringValue
                else {
                    throw AcceptanceFailure("settings.state does not answer the window fields: \(state)")
                }
                self.isOpen = isOpen
                self.isKey = isKey
                self.tab = tab
                self.effectiveLanguage = language
                self.frame = state["windowFrame"]?.rectValue
                self.title = state["windowTitle"]?.stringValue
                self.firstResponder = firstResponder
                self.contentFits = state["contentFits"]?.boolValue
            }
        }

        private func chrome() throws -> Chrome {
            try Chrome(try piccolo.send("settings.state"))
        }

        /// The name of `tab` in the language the running Piccolo shows.
        private func name(of tab: String) throws -> String {
            let language = try #require(AppLanguage(rawValue: try chrome().effectiveLanguage))
            let bundle = try #require(language.textBundle)
            let settingsTab = try #require(SettingsTab(rawValue: tab))
            return SettingsTabText.title(of: settingsTab, bundle: bundle)
        }

        /// Waits until the window is open and has stopped changing its frame, with the title of `tab`
        /// when one is given, and returns what it shows. A change of tab animates the window, so the
        /// frame is read again after a pause until two reads agree.
        private func settled(onTab tab: String? = nil, timeout: TimeInterval = 5) async throws -> Chrome {
            let title = try tab.map(name(of:))
            var previous: CGRect?
            return try await eventually(
                "the Settings window to be open\(title.map { " with the title \"\($0)\"" } ?? ""), and to stop changing its frame",
                timeout: timeout, interval: 0.15
            ) { () throws -> Observation<Chrome> in
                let now = try chrome()
                let before = previous
                previous = now.frame
                guard now.isOpen, let frame = now.frame else { return .unsatisfied("the window is not open") }
                if let title, now.title != title {
                    return .unsatisfied("the title is \(now.title.map { "\"\($0)\"" } ?? "nil")")
                }
                guard let before, framesMatch(before, frame, tolerance: 0.5) else {
                    return .unsatisfied("the frame is still changing: \(describe(frame))")
                }
                return .satisfied(now)
            }
        }

        /// Opens the window as a person would find it: Piccolo in front and the Settings window key.
        private func openAsKey(_ session: SettingsSession) async throws {
            try session.openSettings()
            try await session.bringPiccoloForward()
            _ = try await eventually("the Settings window to be open and the key window", timeout: 5) {
                () throws -> Observation<Void> in
                let now = try chrome()
                return now.isOpen && now.isKey ? .satisfied(()) : .unsatisfied("isOpen \(now.isOpen), isKey \(now.isKey)")
            }
        }

        /// Looks at the focus now, and again after `focusWatch`: a field that takes it late counts.
        private func expectNoFocus(_ context: String) async throws {
            let now = try chrome()
            #expect(now.firstResponder == "none", "\(context): the first responder is \(now.firstResponder) right away")
            try await Task.sleep(for: Self.focusWatch)
            let later = try chrome()
            #expect(
                later.firstResponder == "none",
                "\(context): the first responder is \(later.firstResponder) \(Self.focusWatch) later")
        }

        private func moveWindow(toDisplay index: Int) throws {
            _ = try piccolo.send("settings.moveWindow", ["display": .int(index)])
        }

        // MARK: 1. Focus and title

        @Test("settingsChrome 1. opening Settings and changing the tab leave no field with the focus, and the title is the tab's name")
        func noInitialFocusAndTitle() async throws {
            try await withSettingsSession { session in
                defer { _ = try? piccolo.settingsShowTab("shortcuts") }
                // Opened on each tab in turn, and the tab changed once the window is open.
                for (first, second) in [("shortcuts", "general"), ("general", "shortcuts")] {
                    try piccolo.settingsShowTab(first)
                    try await openAsKey(session)
                    let opened = try await settled(onTab: first)
                    #expect(opened.title == (try name(of: first)))
                    #expect(opened.tab == first)
                    try await expectNoFocus("just opened on the \(first) tab")

                    let shown = try piccolo.settingsShowTab(second)
                    #expect(shown.tab == second)
                    let changed = try await settled(onTab: second)
                    #expect(changed.title == (try name(of: second)))
                    try await expectNoFocus("after switching to the \(second) tab")

                    try piccolo.settingsClose()
                    try await PiccoloWindows.waitForNoWindow(pid: try piccolo.pid())
                }
            }
        }

        // MARK: 2. The General tab

        @Test("settingsChrome 2. on the General tab the content fits without scrolling")
        func generalFits() async throws {
            try await withSettingsSession { session in
                defer { _ = try? piccolo.settingsShowTab("shortcuts") }
                try piccolo.settingsShowTab("general")
                try session.openSettings()
                let general = try await settled(onTab: "general")
                #expect(general.contentFits == true, "the General tab scrolls in a window of \(general.frame.map(describe) ?? "no frame")")
            }
        }

        // MARK: 3. Back to the Shortcuts tab

        @Test("settingsChrome 4. switching from General back to Shortcuts gives the Shortcuts frame back, top edge unchanged")
        func shortcutsFrameComesBack() async throws {
            try await withSettingsSession { session in
                defer { _ = try? piccolo.settingsShowTab("shortcuts") }
                try piccolo.settingsShowTab("shortcuts")
                try session.openSettings()
                _ = try await settled(onTab: "shortcuts")
                // A place of its own, so that the window can grow downwards from it.
                try moveWindow(toDisplay: 0)
                let shortcuts = try #require(try await settled(onTab: "shortcuts").frame)

                _ = try piccolo.settingsShowTab("general")
                let general = try #require(try await settled(onTab: "general").frame)
                #expect(general.height != shortcuts.height, "the General tab has the Shortcuts tab's size")
                #expect(
                    approximatelyEqual(general.minY, shortcuts.minY),
                    "the top edge moved from \(shortcuts.minY) to \(general.minY) on the General tab")
                #expect(approximatelyEqual(general.minX, shortcuts.minX), "the left edge moved")

                _ = try piccolo.settingsShowTab("shortcuts")
                let back = try #require(try await settled(onTab: "shortcuts").frame)
                #expect(
                    framesMatch(back, shortcuts),
                    "back on the Shortcuts tab the window is \(describe(back)), it was \(describe(shortcuts))")
            }
        }

        // MARK: 4. The screens

        @Test("settingsChrome 5. on every connected display the window is no taller than the display's visible frame, on both tabs")
        func fitsEveryDisplay() async throws {
            let displays = try piccolo.displays()
            try await withSettingsSession { session in
                defer { _ = try? piccolo.settingsShowTab("shortcuts") }
                try piccolo.settingsShowTab("shortcuts")
                try session.openSettings()
                _ = try await settled(onTab: "shortcuts")

                for display in displays {
                    for tab in ["shortcuts", "general"] {
                        _ = try piccolo.settingsShowTab(tab)
                        _ = try await settled(onTab: tab)
                        try moveWindow(toDisplay: display.index)
                        let state = try await settled(onTab: tab)
                        let frame = try #require(state.frame)
                        let visible = display.visibleFrame
                        print(
                            "settingsChrome display \(display.index) (visible \(describe(visible.size))), \(tab) tab: "
                                + "window \(describe(frame)), contentFits \(String(describing: state.contentFits))")
                        #expect(
                            frame.height <= visible.height + frameTolerance,
                            "display \(display.index), \(tab) tab: the window is \(frame.height) pt high, the visible frame \(visible.height) pt")
                        #expect(
                            frame.width <= visible.width + frameTolerance,
                            "display \(display.index), \(tab) tab: the window is \(frame.width) pt wide, the visible frame \(visible.width) pt")
                    }
                }
            }
        }
    }
}
