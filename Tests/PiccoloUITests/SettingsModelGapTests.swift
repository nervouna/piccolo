import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

@MainActor
@Suite("Settings model: window gap")
struct SettingsModelGapTests {
    private func make(
        _ config: Config = UIFixture.twoBindings()
    ) -> (model: SettingsModel, backend: InMemorySettingsBackend) {
        let backend = InMemorySettingsBackend(config: config, issues: [])
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage()) { _ in nil }
        return (model, backend)
    }

    @Test("the model starts with the gap of the config, and the config it hands out holds it")
    func initial() {
        let (model, _) = make(Config(gap: 8, bindings: UIFixture.twoBindings().bindings))
        #expect(model.gap == 8)
        #expect(model.config.gap == 8)
    }

    @Test("a gap from 0 to 64 is saved", arguments: [0, 1, 12, 64])
    func accepted(_ value: Int) {
        let (model, backend) = make(Config(gap: 5, bindings: UIFixture.twoBindings().bindings))
        #expect(model.setGap(value))
        #expect(model.gap == value)
        #expect(backend.saved.last?.gap == value)
        #expect(model.error == nil)
    }

    @Test("a gap outside 0 to 64 is rejected with the model's message, and nothing is saved", arguments: [-1, 65, 1000])
    func rejected(_ value: Int) {
        let (model, backend) = make()
        #expect(!model.setGap(value))
        #expect(model.gap == 0)
        #expect(backend.saved.isEmpty)
        #expect(model.error?.contains("0") == true && model.error?.contains("64") == true)
    }

    @Test("a reload takes the gap of the config that replaced it")
    func reload() {
        let (model, backend) = make()
        backend.config.gap = 20
        model.reload()
        #expect(model.gap == 20)
    }

    @Test("the rejection reads in every language")
    func message() throws {
        let error = ValidationError.outOfRange(field: "gap", rule: "must be a whole number from 0 to 64")
        for language in AppLanguage.languages {
            let bundle = try #require(language.textBundle)
            let text = SettingsMessages.describe(error, bundle: bundle)
            #expect(text.contains("64"), "\(language): \(text)")
            #expect(!text.hasPrefix("gap "), "\(language) shows the raw field: \(text)")
        }
    }
}
