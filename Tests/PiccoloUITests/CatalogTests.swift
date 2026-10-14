import Foundation
import Testing

@testable import PiccoloUI

/// The string catalogs as files: every key is complete, the translations keep the arguments of the
/// English text, and the sources use exactly the keys the catalogs hold.
@Suite("String catalogs")
struct CatalogTests {
    private static let catalogs: [(name: String, load: @Sendable () throws -> StringCatalog)] = [
        ("PiccoloUI", { try StringCatalog.ui() }),
        ("App", { try StringCatalog.app() }),
    ]

    @Test("the catalogs are written in English and are not empty", arguments: catalogs.map(\.name))
    func basics(_ name: String) throws {
        let catalog = try Self.catalog(name)
        #expect(catalog.sourceLanguage == "en")
        #expect(catalog.entries.count > 5, "\(catalog.path) holds \(catalog.entries.count) strings")
    }

    @Test("every key lists all eight languages", arguments: catalogs.map(\.name))
    func allLanguagesListed(_ name: String) throws {
        let catalog = try Self.catalog(name)
        for (key, entry) in catalog.entries.sorted(by: { $0.key < $1.key }) {
            let missing = StringCatalog.languages.filter { entry.localizations[$0] == nil }
            #expect(missing.isEmpty, "\(catalog.path): \"\(key)\" has no entry for \(missing)")
            let extra = Set(entry.localizations.keys).subtracting(StringCatalog.languages)
            #expect(extra.isEmpty, "\(catalog.path): \"\(key)\" has entries for \(extra.sorted())")
        }
    }

    @Test("English and Simplified Chinese are complete: every key has a non-empty, translated value", arguments: catalogs.map(\.name))
    func englishAndSimplifiedChineseAreComplete(_ name: String) throws {
        let catalog = try Self.catalog(name)
        for (key, entry) in catalog.entries.sorted(by: { $0.key < $1.key }) {
            for language in ["en", "zh-Hans"] {
                guard let localization = entry.localizations[language] else { continue }
                #expect(
                    !localization.values.isEmpty && localization.values.allSatisfy({ !$0.isEmpty }),
                    "\(catalog.path): \"\(key)\" has an empty \(language) value")
                #expect(
                    localization.states.allSatisfy { $0 == "translated" },
                    "\(catalog.path): the \(language) value of \"\(key)\" is \(localization.states), not translated")
            }
        }
    }

    @Test(
        "no language has an empty value: the languages that are not translated hold the English text",
        arguments: catalogs.map(\.name))
    func noEmptyValues(_ name: String) throws {
        let catalog = try Self.catalog(name)
        for (key, entry) in catalog.entries.sorted(by: { $0.key < $1.key }) {
            for language in StringCatalog.languages {
                guard let localization = entry.localizations[language] else { continue }
                #expect(
                    localization.values.allSatisfy { !$0.isEmpty },
                    "\(catalog.path): \"\(key)\" has an empty \(language) value, which the app would show as a blank")
                #expect(
                    localization.states.allSatisfy { ["translated", "new", "needs_review"].contains($0) },
                    "\(catalog.path): \"\(key)\" has the state \(localization.states) in \(language)")
            }
        }
    }

    @Test(
        "every translation takes the same arguments as the English text, by position when there are several",
        arguments: catalogs.map(\.name))
    func argumentsAgree(_ name: String) throws {
        let catalog = try Self.catalog(name)
        for (key, entry) in catalog.entries.sorted(by: { $0.key < $1.key }) {
            let keySpecifiers = StringCatalog.specifiers(in: key)
            for language in StringCatalog.languages {
                guard let localization = entry.localizations[language] else { continue }
                for value in localization.values {
                    let specifiers = StringCatalog.specifiers(in: value)
                    #expect(
                        specifiers.map(\.type).sorted() == keySpecifiers.map(\.type).sorted(),
                        "\(catalog.path): the \(language) text of \"\(key)\" takes \(specifiers.map(\.type)), the key \(keySpecifiers.map(\.type))")
                    if specifiers.count > 1 {
                        // With several arguments a translation may reorder them: that only works by
                        // position, and each position has to be the type the English text gives it.
                        #expect(
                            specifiers.allSatisfy { $0.position != nil },
                            "\(catalog.path): the \(language) text of \"\(key)\" has several arguments, which need positions (%1$@)")
                        let byPosition = Dictionary(
                            specifiers.compactMap { s in s.position.map { ($0, s.type) } }, uniquingKeysWith: { a, _ in a })
                        let english = entry.localizations["en"]?.values.first.map(StringCatalog.specifiers) ?? []
                        let englishByPosition = Dictionary(
                            english.compactMap { s in s.position.map { ($0, s.type) } }, uniquingKeysWith: { a, _ in a })
                        #expect(
                            byPosition == englishByPosition,
                            "\(catalog.path): the \(language) text of \"\(key)\" gives the arguments other types than the English text")
                    }
                }
            }
        }
    }

    @Test("the English text of a string without arguments is its key", arguments: catalogs.map(\.name))
    func englishIsTheKey(_ name: String) throws {
        let catalog = try Self.catalog(name)
        for (key, entry) in catalog.entries.sorted(by: { $0.key < $1.key })
        where StringCatalog.specifiers(in: key).isEmpty && !(entry.localizations["en"]?.isPlural ?? false) {
            #expect(
                entry.localizations["en"]?.values == [key],
                "\(catalog.path): the English text of \"\(key)\" is \(entry.localizations["en"]?.values ?? [])")
        }
    }

    @Test("the plural forms of English are one and other, and Chinese has other", arguments: catalogs.map(\.name))
    func pluralCategories(_ name: String) throws {
        let catalog = try Self.catalog(name)
        for (key, entry) in catalog.entries where entry.localizations["en"]?.isPlural == true {
            #expect(entry.localizations["en"]?.values.count == 2, "\(catalog.path): \"\(key)\" in English")
            #expect(entry.localizations["zh-Hans"]?.values.count == 1, "\(catalog.path): \"\(key)\" in Simplified Chinese")
        }
    }

    // MARK: The sources

    @Test("every text the window looks up is in the PiccoloUI catalog, and every key of it is used")
    func uiKeysMatchTheSources() throws {
        let catalog = try StringCatalog.ui()
        let used = Self.literals(under: "Sources/PiccoloUI")
        let keys = Set(catalog.entries.keys.map(StringCatalog.shape(ofKey:)))
        for literal in used.sorted() {
            #expect(keys.contains(literal), "PiccoloUI looks up \"\(literal.replacing("\u{1}", with: "\\(…)"))\", which the catalog does not hold")
        }
        for key in catalog.entries.keys.sorted() where !used.contains(StringCatalog.shape(ofKey: key)) {
            Issue.record("the PiccoloUI catalog holds \"\(key)\", which no source looks up")
        }
    }

    @Test("every text the app looks up is in the App catalog, and every key of it is used")
    func appKeysMatchTheSources() throws {
        let catalog = try StringCatalog.app()
        let used = Self.literals(under: "App")
        let keys = Set(catalog.entries.keys.map(StringCatalog.shape(ofKey:)))
        for literal in used.sorted() {
            #expect(keys.contains(literal), "the app looks up \"\(literal.replacing("\u{1}", with: "\\(…)"))\", which the catalog does not hold")
        }
        for key in catalog.entries.keys.sorted() where !used.contains(StringCatalog.shape(ofKey: key)) {
            Issue.record("the App catalog holds \"\(key)\", which no source looks up")
        }
    }

    @Test("in PiccoloUI every String(localized:) names its bundle, so that none is looked up in the app's")
    func uiLookupsNameTheirBundle() {
        for file in Repository.swiftFiles(under: "Sources/PiccoloUI") {
            for call in LocalizedLiterals.calls(in: file.text) {
                #expect(call.contains("bundle:"), "\(file.path): \(call) has no bundle: parameter")
            }
        }
    }

    @Test("no source hands a literal to a SwiftUI control that would look it up in the main bundle")
    func noLiteralKeys() throws {
        let controls = try Regex(
            #"\b(?:Text|Button|Toggle|Picker|Section|Label|LabeledContent|Stepper|TextField|SecureField|Menu|Link|GroupBox|DisclosureGroup)\(\s*""#
        )
        let modifiers = try Regex(
            #"\.(?:help|accessibilityLabel|accessibilityHint|accessibilityValue|navigationTitle|alert|confirmationDialog|badge|tabItem)\(\s*""#
        )
        for file in Repository.swiftFiles(under: "Sources/PiccoloUI") + Repository.swiftFiles(under: "App") {
            let code = file.text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for match in code.matches(of: controls) + code.matches(of: modifiers) {
                Issue.record(
                    "\(file.path): \(code[match.range]) takes a literal as a localized key: use Text(localized:) or String(localized:)"
                )
            }
        }
    }

    // MARK: Support

    private static func catalog(_ name: String) throws -> StringCatalog {
        try #require(catalogs.first { $0.name == name }).load()
    }

    /// The shapes of the texts the sources under `folder` hand to `localized:`.
    private static func literals(under folder: String) -> Set<String> {
        var shapes: Set<String> = []
        for file in Repository.swiftFiles(under: folder) {
            shapes.formUnion(LocalizedLiterals.find(in: file.text))
        }
        return shapes
    }
}
