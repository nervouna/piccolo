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

    @Test("the model lists the bindings in sections, and keeps the file order in the config")
    func sections() {
        let (model, _) = make()
        #expect(model.sections.map(\.kind) == [.placeWindow, .moveToDisplay])
        #expect(model.bindings.map(\.id) == [UIFixture.idA, UIFixture.idB])
        #expect(model.search == "")
    }

    @Test("a search keeps the selection while the selected binding is shown")
    func searchKeepsSelection() {
        let (model, backend) = make()
        model.selectedBindingID = UIFixture.idB

        model.setSearch("display")

        #expect(model.selectedBindingID == UIFixture.idB)
        #expect(model.isVisible(UIFixture.idB))
        #expect(!model.isVisible(UIFixture.idA))
        #expect(backend.saved.isEmpty)
    }

    @Test("a search that hides the selected binding selects the first shown one")
    func searchMovesSelection() {
        let (model, _) = make()
        #expect(model.selectedBindingID == UIFixture.idA)

        model.setSearch("display")

        #expect(model.selectedBindingID == UIFixture.idB)
    }

    @Test("a search nothing matches selects nothing, and clearing it selects the first binding")
    func searchWithoutMatch() {
        let (model, _) = make()

        model.setSearch("zzz")
        #expect(model.sections.isEmpty)
        #expect(model.selectedBindingID == nil)

        model.setSearch("")
        #expect(model.selectedBindingID == UIFixture.idA)
        #expect(model.sections.flatMap(\.bindings).count == 2)
    }

    @Test("the search matches the shortcut text of the layout")
    func searchByShortcut() {
        let (model, _) = make()
        model.setSearch("⌃⌥⇧⌘F13")
        #expect(model.sections.flatMap(\.bindings).map(\.id) == [UIFixture.idA])
    }

    @Test("adding a binding clears a search that would hide it, and selects it")
    func addingClearsSearch() throws {
        let (model, _) = make()
        model.setSearch("display")

        let id = try #require(model.addBinding())

        #expect(model.search == "")
        #expect(model.selectedBindingID == id)
        #expect(model.isVisible(id))
    }

    @Test("adding a binding leaves a search that still shows it")
    func addingKeepsMatchingSearch() throws {
        let (model, _) = make()
        model.setSearch("left")

        let id = try #require(model.addBinding())

        #expect(model.search == "left")
        #expect(model.selectedBindingID == id)
    }

    @Test("the inactive shortcuts come from the backend, on load, after a save and after a reload")
    func inactiveFromBackend() {
        let backend = InMemorySettingsBackend(config: UIFixture.twoBindings())
        backend.inactive = [UIFixture.idA]
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage())
        #expect(model.inactiveBindingIDs == [UIFixture.idA])

        backend.inactive = [UIFixture.idB]
        model.setShortcut(UIFixture.idB, to: UIFixture.f14)
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
        model.beginRecording(UIFixture.idB)
        #expect(model.inactiveBindingIDs.isEmpty)

        backend.inactive = [UIFixture.idA]
        model.cancelRecording()
        #expect(model.inactiveBindingIDs == [UIFixture.idA])
    }
}
