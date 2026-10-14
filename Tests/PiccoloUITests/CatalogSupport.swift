import Foundation
import Testing

/// The string catalogs of the repository (`Localizable.xcstrings`), read as JSON from the source
/// tree, and the sources they translate. The tests check the files that are committed, not what
/// a build made of them.
enum Repository {
    /// The root of the checkout, found from this file.
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }()

    static func url(_ path: String) -> URL {
        root.appending(path: path)
    }

    /// The `.swift` files under `folder` (a path from the root), sorted, with their paths from the root.
    static func swiftFiles(under folder: String) -> [(path: String, text: String)] {
        let base = url(folder)
        guard
            let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        else { return [] }
        var files: [(String, String)] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let path = String(file.path.dropFirst(root.path.count + 1))
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                files.append((path, text))
            }
        }
        return files.sorted { $0.0 < $1.0 }
    }
}

/// One `Localizable.xcstrings`.
struct StringCatalog {
    /// The languages every catalog lists for every key.
    static let languages = ["en", "zh-Hans", "zh-Hant", "ja", "fr", "es", "pt-BR", "de"]

    struct Entry {
        /// The text of a language: one for a plain string, one per plural category for a plural.
        /// `nil` when the entry has no localization for the language.
        let localizations: [String: Localization]
    }

    struct Localization {
        /// `translated`, `new`, ...
        let states: [String]
        /// The texts: one, or one per plural category.
        let values: [String]
        let isPlural: Bool
    }

    let path: String
    let sourceLanguage: String
    let entries: [String: Entry]

    init(path: String) throws {
        self.path = path
        let data = try Data(contentsOf: Repository.url(path))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        sourceLanguage = root["sourceLanguage"] as? String ?? ""
        let strings = try #require(root["strings"] as? [String: Any])
        var entries: [String: Entry] = [:]
        for (key, raw) in strings {
            let object = try #require(raw as? [String: Any])
            var localizations: [String: Localization] = [:]
            for (language, rawLocalization) in (object["localizations"] as? [String: Any]) ?? [:] {
                let localization = try #require(rawLocalization as? [String: Any])
                if let unit = localization["stringUnit"] as? [String: Any] {
                    localizations[language] = Localization(
                        states: [unit["state"] as? String ?? ""], values: [unit["value"] as? String ?? ""],
                        isPlural: false)
                } else if let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                    let units = plural.values.compactMap { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
                    localizations[language] = Localization(
                        states: units.map { $0["state"] as? String ?? "" },
                        values: units.map { $0["value"] as? String ?? "" }, isPlural: true)
                }
            }
            entries[key] = Entry(localizations: localizations)
        }
        self.entries = entries
    }

    static func ui() throws -> StringCatalog {
        try StringCatalog(path: "Sources/PiccoloUI/Resources/Localizable.xcstrings")
    }

    static func app() throws -> StringCatalog {
        try StringCatalog(path: "App/Localizable.xcstrings")
    }

    // MARK: Format specifiers

    /// The format specifiers of a value in order, as (position or nil, type): `%@` is (nil, "@"),
    /// `%2$lld` is (2, "lld"). `%%` is not a specifier.
    static func specifiers(in text: String) -> [(position: Int?, type: String)] {
        let pattern = #"%(?:(\d+)\$)?(l{0,2}[dDiuUxXoOfeEgGcCsSpaA@])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        var found: [(Int?, String)] = []
        var index = 0
        while index < nsText.length {
            // Skip an escaped percent sign.
            if nsText.substring(with: NSRange(location: index, length: min(2, nsText.length - index))) == "%%" {
                index += 2
                continue
            }
            if let match = regex.firstMatch(
                in: text, range: NSRange(location: index, length: nsText.length - index)),
                match.range.location == index
            {
                let position = match.range(at: 1).location == NSNotFound
                    ? nil : Int(nsText.substring(with: match.range(at: 1)))
                found.append((position, nsText.substring(with: match.range(at: 2))))
                index += match.range.length
            } else {
                index += 1
            }
        }
        return found
    }

    /// A key with its specifiers replaced by one marker, to compare with the literal of a source file.
    static func shape(ofKey key: String) -> String {
        key.replacing("%%", with: "\u{2}")
            .replacing(/%(?:\d+\$)?l{0,2}[dDiuUxXoOfeEgGcCsSpaA@]/, with: "\u{1}")
            .replacing("\u{2}", with: "%")
    }
}

/// Finds the text literals handed to `localized:` in Swift source, with each interpolation replaced
/// by one marker (`\u{1}`), the way ``StringCatalog/shape(ofKey:)`` shapes a catalog key.
enum LocalizedLiterals {
    static func find(in source: String) -> [String] {
        let characters = Array(source)
        let marker = Array("localized:")
        var literals: [String] = []
        var i = 0
        while i < characters.count {
            guard characters[i...].starts(with: marker) else {
                i += 1
                continue
            }
            var j = i + marker.count
            while j < characters.count, characters[j].isWhitespace { j += 1 }
            guard j < characters.count, characters[j] == "\"" else {
                i = j
                continue
            }
            j += 1
            var text = ""
            var depth = 0
            while j < characters.count {
                let c = characters[j]
                if depth > 0 {
                    if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
                } else if c == "\\" && j + 1 < characters.count {
                    if characters[j + 1] == "(" {
                        text.append("\u{1}")
                        depth = 1
                    } else {
                        text.append(characters[j + 1])
                    }
                    j += 2
                    continue
                } else if c == "\"" {
                    break
                } else {
                    text.append(c)
                }
                j += 1
            }
            literals.append(text)
            i = j + 1
        }
        return literals
    }

    /// The text of every `String(localized:` call of `source` up to its closing parenthesis.
    static func calls(in source: String) -> [String] {
        let characters = Array(source)
        let marker = Array("String(localized:")
        var calls: [String] = []
        var i = 0
        while i < characters.count {
            guard characters[i...].starts(with: marker) else {
                i += 1
                continue
            }
            var j = i + marker.count
            var depth = 1
            var inString = false
            var interpolation = 0
            while j < characters.count, depth > 0 {
                let c = characters[j]
                if inString {
                    if interpolation > 0 {
                        if c == "(" { interpolation += 1 } else if c == ")" { interpolation -= 1 }
                    } else if c == "\\" && j + 1 < characters.count {
                        if characters[j + 1] == "(" { interpolation = 1 }
                        j += 1
                    } else if c == "\"" {
                        inString = false
                    }
                } else if c == "\"" {
                    inString = true
                } else if c == "(" {
                    depth += 1
                } else if c == ")" {
                    depth -= 1
                }
                j += 1
            }
            calls.append(String(characters[i..<min(j, characters.count)]))
            i = j
        }
        return calls
    }
}
