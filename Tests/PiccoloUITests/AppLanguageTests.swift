import Foundation
import Testing

@testable import PiccoloUI

@Suite("App languages")
struct AppLanguageTests {
    @Test("the choice is System default or one of the eight languages, with the codes macOS uses")
    func codes() {
        #expect(AppLanguage.allCases.map(\.rawValue) == [
            "system", "en", "zh-Hans", "zh-Hant", "ja", "fr", "es", "pt-BR", "de",
        ])
        #expect(AppLanguage.languages.map(\.rawValue) == [
            "en", "zh-Hans", "zh-Hant", "ja", "fr", "es", "pt-BR", "de",
        ])
        #expect(AppLanguage.system.code == nil)
        #expect(AppLanguage.zhHans.code == "zh-Hans")
        #expect(AppLanguage.fallback == .en)
    }

    @Test("every language is named in itself, and System default is named by a translated text")
    func nativeNames() {
        #expect(AppLanguage.languages.compactMap(\.nativeName) == [
            "English", "简体中文", "繁體中文", "日本語", "Français", "Español", "Português (Brasil)", "Deutsch",
        ])
        #expect(AppLanguage.system.nativeName == nil)
    }

    @Test("every language has a folder of texts in the resource bundle", arguments: AppLanguage.languages)
    func textBundles(_ language: AppLanguage) throws {
        let bundle = try #require(language.textBundle, "there is no \(language.rawValue).lproj in PiccoloUI's resources")
        // The folder holds the texts: the English key is in it.
        #expect(bundle.localizedString(forKey: "Left Half", value: "<missing>", table: nil) != "<missing>")
    }

    @Test("System default answers with the resource bundle itself, in the language of the running app")
    func systemTextBundle() {
        #expect(AppLanguage.system.textBundle === AppLanguage.currentTextBundle)
    }

    // MARK: Matching a list of languages

    @Test(
        "the best language for a list of preferences",
        arguments: [
            (["zh-Hans-CN", "en-CN"], AppLanguage.zhHans),
            (["en-CN", "zh-Hans-CN"], .en),
            (["zh-Hans"], .zhHans),
            (["zh-Hant-TW"], .zhHant),
            (["zh-TW"], .zhHant),
            (["zh-HK"], .zhHant),
            (["zh-Hant-HK"], .zhHant),
            (["zh-CN"], .zhHans),
            (["zh"], .zhHans),
            (["ja-JP"], .ja),
            (["fr-CA"], .fr),
            (["es-419"], .es),
            (["es-MX", "en"], .es),
            (["pt-BR"], .ptBR),
            (["pt-PT"], .ptBR),
            (["de-AT"], .de),
            (["en-GB"], .en),
            // A language the interface is not available in gives way to the next one.
            (["ko-KR", "ja-JP"], .ja),
        ] as [([String], AppLanguage)])
    func best(_ preferences: [String], _ expected: AppLanguage) {
        #expect(AppLanguage.best(for: preferences) == expected)
    }

    @Test("a list without any of the eight languages matches none")
    func noMatch() {
        #expect(AppLanguage.best(for: ["ko-KR", "ru"]) == nil)
        #expect(AppLanguage.best(for: []) == nil)
        #expect(AppLanguage.best(for: [""]) == nil)
    }
}

@Suite("Language defaults")
struct LanguageDefaultsTests {
    /// A defaults domain of its own that is removed afterwards.
    private func withDefaults<Result>(
        _ body: (LanguageDefaults, UserDefaults, String) throws -> Result
    ) throws -> Result {
        let domain = "io.damao.piccolo.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        return try body(LanguageDefaults(defaults: defaults, domain: domain), defaults, domain)
    }

    @Test("a domain without AppleLanguages is on System default")
    func empty() throws {
        try withDefaults { stored, _, _ in
            #expect(stored.stored == .system)
        }
    }

    @Test("a chosen language is stored as the only element of AppleLanguages in the domain", arguments: AppLanguage.languages)
    func storing(_ language: AppLanguage) throws {
        try withDefaults { stored, defaults, domain in
            stored.store(language)

            #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] == [language.rawValue])
            #expect(stored.stored == language)
        }
    }

    @Test("System default removes the stored list")
    func systemDefaultRemoves() throws {
        try withDefaults { stored, defaults, domain in
            stored.store(.zhHans)
            #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] != nil)

            stored.store(.system)

            #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil)
            #expect(stored.stored == .system)
        }
    }

    @Test("storing replaces the language, and leaves the rest of the domain alone")
    func storingReplaces() throws {
        try withDefaults { stored, defaults, domain in
            defaults.set("kept", forKey: "other")

            stored.store(.fr)
            stored.store(.de)

            #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] == ["de"])
            #expect(defaults.string(forKey: "other") == "kept")
            stored.store(.system)
            #expect(defaults.string(forKey: "other") == "kept")
        }
    }

    @Test("a list written by System Settings reads as its first supported language")
    func readsWhatTheSystemWrote() throws {
        try withDefaults { stored, defaults, _ in
            defaults.set(["zh-Hans-CN", "en-CN"], forKey: "AppleLanguages")
            #expect(stored.stored == .zhHans)

            defaults.set(["ko-KR", "pt-BR"], forKey: "AppleLanguages")
            #expect(stored.stored == .ptBR)
        }
    }

    @Test("a list with no supported language reads as System default")
    func unsupported() throws {
        try withDefaults { stored, defaults, _ in
            defaults.set(["ko-KR"], forKey: "AppleLanguages")
            #expect(stored.stored == .system)
        }
    }
}
