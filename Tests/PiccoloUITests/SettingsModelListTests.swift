import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

@MainActor
@Suite("Settings model: list")
struct SettingsModelListTests {
    private func make(
        _ config: Config = UIFixture.twoBindings()
    ) -> (model: SettingsModel, backend: InMemorySettingsBackend) {
        let backend = InMemorySettingsBackend(config: config)
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage()) { code in
            ["0": "a", "11": "b"][String(code)]
        }
        return (model, backend)
    }

    private let leftRow = KeymapRowID.builtIn(.placeWindow(.preset(.leftHalf)))
    private let nextRow = KeymapRowID.builtIn(.moveToDisplay(.next))

    @Test("the model keeps the file order in the config, and starts with no search and every section")
    func fileOrder() {
        let (model, _) = make()
        #expect(model.bindings.map(\.id) == [UIFixture.idA, UIFixture.idB])
        #expect(model.search == "")
        #expect(model.keymap.map(\.section) == KeymapSection.allCases)
    }

    @Test("a search narrows the keymap to the rows that match, and saves nothing")
    func searchNarrowsTheKeymap() {
        let (model, backend) = make()

        model.setSearch("display")

        #expect(model.search == "display")
        #expect(model.keymap.flatMap(\.rows).map(\.id).contains(nextRow))
        #expect(!model.keymap.flatMap(\.rows).map(\.id).contains(leftRow))
        #expect(model.keymap.map(\.section) == [.displays])
        #expect(backend.saved.isEmpty)
    }

    @Test("a search nothing matches leaves no section, and clearing it brings every section back")
    func searchWithoutMatch() {
        let (model, _) = make()

        model.setSearch("zzz")
        #expect(model.keymap.isEmpty)

        model.setSearch("")
        #expect(model.keymap.map(\.section) == KeymapSection.allCases)
    }

    @Test("the search matches the shortcut text of a row")
    func searchByShortcut() {
        let (model, _) = make()
        model.setSearch("⌃⌥⇧⌘F13")
        #expect(model.keymap.flatMap(\.rows).map(\.id) == [leftRow])
    }

    @Test("the inactive shortcuts come from the backend, on load, after a save and after a reload")
    func inactiveFromBackend() {
        let backend = InMemorySettingsBackend(config: UIFixture.twoBindings())
        backend.inactive = [UIFixture.idA]
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage())
        #expect(model.inactiveBindingIDs == [UIFixture.idA])

        backend.inactive = [UIFixture.idB]
        model.setGap(8)
        #expect(model.inactiveBindingIDs == [UIFixture.idB])

        backend.inactive = []
        backend.replaceFromOutside(backend.config)
        #expect(model.inactiveBindingIDs.isEmpty)
    }

    @Test("no row is marked while a shortcut is being recorded, and the marks come back afterwards")
    func nothingMarkedWhileRecording() {
        let backend = InMemorySettingsBackend(config: UIFixture.twoBindings())
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage())

        // With every hotkey suspended the backend would report them all as not registered.
        backend.inactive = [UIFixture.idA, UIFixture.idB]
        model.beginRecording(nextRow)
        #expect(model.inactiveBindingIDs.isEmpty)

        backend.inactive = [UIFixture.idA]
        model.cancelRecording()
        #expect(model.inactiveBindingIDs == [UIFixture.idA])
    }
}
