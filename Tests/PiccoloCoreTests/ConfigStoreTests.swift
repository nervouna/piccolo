import Foundation
import Testing

@testable import PiccoloCore

@Suite("Config store")
struct ConfigStoreTests {
    private func writeText(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// A single valid binding, used as the expected content of a clean file.
    private var placeLeftHalf: Binding {
        Binding(
            id: Fixture.idA,
            action: .placeWindow(.preset(.leftHalf)),
            shortcut: Shortcut(keyCode: 123, modifiers: [.control, .option]))
    }

    // MARK: Missing file

    @Test("a missing file loads the defaults without issues and writes nothing")
    func missingFile() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            let result = try ConfigStore(url: url).load()
            #expect(result == LoadResult(config: .default, issues: []))
            #expect(try entryNames(in: directory).isEmpty)
        }
    }

    // MARK: Save and load

    @Test("saving and then loading returns an equal config with no issues")
    func saveThenLoad() throws {
        let config = Config(resizeStep: 0.2, bindings: allKindsBindings)
        try withTemporaryDirectory { directory in
            let store = ConfigStore(url: directory.appending(path: "config.json"))
            try store.save(config)
            #expect(try store.load() == LoadResult(config: config, issues: []))
        }
    }

    @Test("save creates a missing parent directory")
    func saveCreatesDirectory() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "nested/deeper/config.json")
            let store = ConfigStore(url: url)
            try store.save(.default)
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(try store.load() == LoadResult(config: .default, issues: []))
        }
    }

    @Test("save refuses an invalid config and writes nothing")
    func saveRejectsInvalidConfig() throws {
        let bad = Config(bindings: [
            Binding(
                id: Fixture.idB,
                action: .placeWindow(.custom(FractionalRect(x: 0.5, y: 0, width: 0.75, height: 1))))
        ])
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            #expect(
                throws: ConfigStoreError.invalid(.outOfRange(field: "x + width", rule: "must be <= 1"))
            ) {
                try ConfigStore(url: url).save(bad)
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("save refuses a config with a duplicate binding ID and writes nothing")
    func saveRejectsDuplicateIDs() throws {
        let bad = Config(bindings: [
            Binding(id: Fixture.idA, action: .moveToDisplay(.next)),
            Binding(id: Fixture.idA, action: .moveToDisplay(.previous)),
        ])
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            #expect(throws: ConfigStoreError.invalid(.duplicateBindingID(Fixture.idA))) {
                try ConfigStore(url: url).save(bad)
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("save refuses a config whose version this build cannot read")
    func saveRejectsUnsupportedVersion() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            #expect(throws: ConfigStoreError.invalid(.unsupportedVersion(2))) {
                try ConfigStore(url: url).save(Config(version: 2))
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: Sample file

    @Test("the sample file from the issue loads without issues")
    func loadSample() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(
                """
                {
                  "bindings": [
                    { "action": { "frame": { "preset": "leftHalf" }, "type": "placeWindow" },
                      "id": "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40",
                      "shortcut": { "keyCode": 123, "modifiers": ["control", "option"] } },
                    { "action": { "frame": { "custom": { "height": 1, "width": 0.5, "x": 0.25, "y": 0 } }, "type": "placeWindow" },
                      "id": "7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D" },
                    { "action": { "direction": "next", "type": "moveToDisplay" }, "id": "0D9E8F7A-6B5C-4D3E-8F2A-1B0C9D8E7F6A" },
                    { "action": { "columns": 2, "count": 4, "rows": 2, "type": "arrangeGrid" }, "id": "2C4D6E8F-1A3B-4C5D-9E7F-0A1B2C3D4E5F" },
                    { "action": { "direction": "left", "type": "moveDivider" }, "id": "9B8A7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D" }
                  ],
                  "resizeStep": 0.05,
                  "version": 1
                }
                """,
                to: url)
            let result = try ConfigStore(url: url).load()
            #expect(result.issues.isEmpty)
            #expect(result.config.bindings.count == 5)
            #expect(result.config.resizeStep == 0.05)
        }
    }

    // MARK: Corrupt files

    @Test("a file that is not JSON is moved aside and the defaults are loaded")
    func notJSON() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            let original = Data("{ this is not json".utf8)
            try original.write(to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.config == .default)
            #expect(result.issues.count == 1)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            let copies = try corruptCopyNames(in: directory)
            #expect(copies.count == 1)
            #expect(try Data(contentsOf: directory.appending(path: copies[0])) == original)
        }
    }

    @Test(
        "an unusable top level is moved aside and the defaults are loaded",
        arguments: [
            "[]",
            "42",
            "null",
            #""config""#,
            #"{"bindings":[]}"#,
            #"{"version":1}"#,
            #"{"version":"1","bindings":[]}"#,
            #"{"version":0,"bindings":[]}"#,
            #"{"version":1,"bindings":{}}"#,
        ])
    func unusableTopLevel(json: String) throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            let original = Data(json.utf8)
            try original.write(to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.config == .default)
            #expect(result.issues.count == 1)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            let copies = try corruptCopyNames(in: directory)
            #expect(copies.count == 1)
            #expect(try Data(contentsOf: directory.appending(path: copies[0])) == original)
        }
    }

    @Test("a moved-aside file is named after the config file and the time it was moved")
    func corruptCopyName() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText("not json", to: url)
            _ = try ConfigStore(url: url).load()
            // The config file itself is gone, so the only entry is the moved copy.
            let names = try entryNames(in: directory)
            #expect(names.count == 1)
            #expect(names.allSatisfy { $0.wholeMatch(of: #/config\.corrupt-\d{8}-\d{6}\.json/#) != nil })
        }
    }

    // MARK: Newer version

    @Test("a newer version is left byte-identical, the defaults are loaded and saving is refused")
    func newerVersion() throws {
        let original = Data(
            #"{"bindings":[{"action":{"type":"teleport"},"id":"5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40"}],"resizeStep":0.05,"version":2}"#
                .utf8)
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try original.write(to: url)
            let store = ConfigStore(url: url)

            let result = try store.load()

            #expect(result.config == .default)
            #expect(result.issues.count == 1)
            #expect(try Data(contentsOf: url) == original)
            #expect(try corruptCopyNames(in: directory).isEmpty)

            #expect(throws: ConfigStoreError.newerFileVersion(2)) {
                try store.save(.default)
            }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    // MARK: Bindings

    @Test("an undecodable or invalid binding is skipped, names its index, and the others load")
    func skippedBindings() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(
                """
                {
                  "bindings": [
                    { "action": { "frame": { "preset": "leftHalf" }, "type": "placeWindow" },
                      "id": "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40" },
                    { "action": { "frame": { "preset": "bigHalf" }, "type": "placeWindow" },
                      "id": "7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D" },
                    { "action": { "frame": { "custom": { "height": 1, "width": 0.75, "x": 0.5, "y": 0 } }, "type": "placeWindow" },
                      "id": "0D9E8F7A-6B5C-4D3E-8F2A-1B0C9D8E7F6A" },
                    { "action": { "direction": "next", "type": "moveToDisplay" },
                      "id": "2C4D6E8F-1A3B-4C5D-9E7F-0A1B2C3D4E5F" }
                  ],
                  "version": 1
                }
                """,
                to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.config.bindings.map(\.id) == [Fixture.idA, Fixture.idD])
            #expect(result.issues.count == 2)
            #expect(result.issues[0].contains("bindings[1]"))
            #expect(result.issues[0].contains("bigHalf"))
            #expect(result.issues[1].contains("bindings[2]"))
            #expect(result.issues[1].contains("x + width"))
        }
    }

    @Test("an unknown action type is skipped and reported by index")
    func unknownActionTypeSkipped() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(
                """
                {
                  "bindings": [
                    { "action": { "type": "teleport" }, "id": "7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D" }
                  ],
                  "version": 1
                }
                """,
                to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.config.bindings.isEmpty)
            #expect(result.issues.count == 1)
            #expect(result.issues[0].contains("bindings[0]"))
            #expect(result.issues[0].contains("teleport"))
        }
    }

    @Test("of two bindings sharing an ID the first one wins and the second is reported")
    func duplicateIDs() throws {
        let first = Binding(id: Fixture.idA, action: .moveToDisplay(.next))
        let third = Binding(id: Fixture.idB, action: .moveToDisplay(.previous))
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(
                """
                {
                  "bindings": [
                    { "action": { "direction": "next", "type": "moveToDisplay" },
                      "id": "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40" },
                    { "action": { "direction": "left", "type": "moveDivider" },
                      "id": "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40" },
                    { "action": { "direction": "previous", "type": "moveToDisplay" },
                      "id": "7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D" }
                  ],
                  "version": 1
                }
                """,
                to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.config.bindings == [first, third])
            #expect(result.issues.count == 1)
            #expect(result.issues[0].contains("bindings[1]"))
            #expect(result.issues[0].contains("duplicate"))
        }
    }

    // MARK: resizeStep

    @Test(
        "an invalid resizeStep falls back to the default and the bindings still load",
        arguments: ["0", "0.6", "-0.05", "1e400", #""fast""#])
    func invalidResizeStep(value: String) throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(
                """
                {
                  "bindings": [
                    { "action": { "frame": { "preset": "leftHalf" }, "type": "placeWindow" },
                      "id": "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40" }
                  ],
                  "resizeStep": \(value),
                  "version": 1
                }
                """,
                to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.config.resizeStep == Config.defaultResizeStep)
            #expect(result.config.bindings.map(\.id) == [Fixture.idA])
            #expect(result.issues.count == 1)
            #expect(result.issues[0].contains("resizeStep"))
        }
    }

    @Test("a missing resizeStep uses the default without an issue")
    func missingResizeStep() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(#"{"bindings":[],"version":1}"#, to: url)
            let result = try ConfigStore(url: url).load()
            #expect(result == LoadResult(config: .default, issues: []))
        }
    }
}
