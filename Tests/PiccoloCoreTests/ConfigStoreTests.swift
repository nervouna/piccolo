import Foundation
import Testing

@testable import PiccoloCore

@Suite("Config store")
struct ConfigStoreTests {
    private func writeText(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// A single valid binding, used as the expected content of a clean file.
    private var placeLeftHalf: KeyBinding {
        KeyBinding(
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
        // Nothing is skipped, so each binding sits at its position in the saved list.
        let positions = Dictionary(
            uniqueKeysWithValues: config.bindings.enumerated().map { index, binding in (binding.id, index) })
        try withTemporaryDirectory { directory in
            let store = ConfigStore(url: directory.appending(path: "config.json"))
            try store.save(config)
            #expect(
                try store.load() == LoadResult(config: config, issues: [], sourceIndices: positions))
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
            KeyBinding(
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
            KeyBinding(id: Fixture.idA, action: .moveToDisplay(.next)),
            KeyBinding(id: Fixture.idA, action: .moveToDisplay(.previous)),
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
        let first = KeyBinding(id: Fixture.idA, action: .moveToDisplay(.next))
        let third = KeyBinding(id: Fixture.idB, action: .moveToDisplay(.previous))
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

    // MARK: Positions in the file

    @Test("each loaded binding carries its position in the file, counting the skipped ones")
    func sourceIndices() throws {
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
                    { "action": { "direction": "previous", "type": "moveToDisplay" },
                      "id": "0D9E8F7A-6B5C-4D3E-8F2A-1B0C9D8E7F6A" },
                    { "action": { "direction": "next", "type": "moveToDisplay" },
                      "id": "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40" },
                    { "action": { "direction": "next", "type": "moveToDisplay" },
                      "id": "2C4D6E8F-1A3B-4C5D-9E7F-0A1B2C3D4E5F" }
                  ],
                  "version": 1
                }
                """,
                to: url)

            let result = try ConfigStore(url: url).load()

            // Index 1 is undecodable and index 3 repeats the ID of index 0, so the first one wins.
            #expect(result.config.bindings.map(\.id) == [Fixture.idA, Fixture.idC, Fixture.idD])
            #expect(result.sourceIndices == [Fixture.idA: 0, Fixture.idC: 2, Fixture.idD: 4])
        }
    }

    @Test("a config that did not come from a file has no positions")
    func noPositionsWithoutFile() throws {
        try withTemporaryDirectory { directory in
            #expect(try ConfigStore(url: directory.appending(path: "missing.json")).load().sourceIndices.isEmpty)

            let newer = directory.appending(path: "newer.json")
            try writeText(#"{"bindings":[{"action":{"type":"teleport"},"id":"7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D"}],"version":2}"#, to: newer)
            #expect(try ConfigStore(url: newer).load().sourceIndices.isEmpty)

            let corrupt = directory.appending(path: "corrupt.json")
            try writeText("not json", to: corrupt)
            #expect(try ConfigStore(url: corrupt).load().sourceIndices.isEmpty)
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

    // MARK: Dropped entries

    @Test("a skipped binding reports dropped entries")
    func droppedBinding() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(#"{"bindings":[{"id":"not-a-uuid"}],"version":1}"#, to: url)
            #expect(try ConfigStore(url: url).load().droppedEntries)
        }
    }

    @Test("an invalid resizeStep that is replaced reports dropped entries")
    func droppedResizeStep() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(#"{"bindings":[],"resizeStep":0.9,"version":1}"#, to: url)
            #expect(try ConfigStore(url: url).load().droppedEntries)
        }
    }

    @Test(
        "a load that keeps everything reports no dropped entries",
        arguments: [
            #"{"bindings":[],"version":1}"#,
            #"{"bindings":[],"resizeStep":0.05,"version":1}"#,
            #"{"bindings":[],"version":1,"someFutureKey":true}"#,
        ])
    func noDroppedEntries(json: String) throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(json, to: url)
            #expect(try ConfigStore(url: url).load().droppedEntries == false)
        }
    }

    @Test("a missing, moved-aside or newer file reports no dropped entries")
    func noDroppedEntriesWhenNothingIsLoaded() throws {
        try withTemporaryDirectory { directory in
            #expect(try ConfigStore(url: directory.appending(path: "missing.json")).load().droppedEntries == false)

            let corrupt = directory.appending(path: "corrupt.json")
            try writeText("not json", to: corrupt)
            #expect(try ConfigStore(url: corrupt).load().droppedEntries == false)

            let newer = directory.appending(path: "newer.json")
            try writeText(#"{"bindings":[{"id":"not-a-uuid"}],"version":2}"#, to: newer)
            #expect(try ConfigStore(url: newer).load().droppedEntries == false)
        }
    }

    // MARK: Copies

    @Test("a backup holds the file's bytes, leaves the file in place and is named after it and the time")
    func backUpCopy() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            let original = Data(#"{"bindings":[],"extra":true,"version":1}"#.utf8)
            try original.write(to: url)

            let copy = try ConfigStore(url: url).backUp(at: Date(timeIntervalSince1970: 1_800_000_000))

            #expect(copy.lastPathComponent.wholeMatch(of: #/config\.backup-\d{8}-\d{6}\.json/#) != nil)
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: copy.lastPathComponent).path))
            #expect(try Data(contentsOf: copy) == original)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test("a backup with the same name as an earlier one never replaces it")
    func backUpNeverOverwrites() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            let store = ConfigStore(url: url)
            let date = Date(timeIntervalSince1970: 1_800_000_000)

            try writeText("first", to: url)
            let firstCopy = try store.backUp(at: date)
            try writeText("second", to: url)
            let secondCopy = try store.backUp(at: date)

            #expect(secondCopy.lastPathComponent != firstCopy.lastPathComponent)
            #expect(secondCopy.lastPathComponent.hasSuffix("-2.json"))
            #expect(try Data(contentsOf: firstCopy) == Data("first".utf8))
            #expect(try Data(contentsOf: secondCopy) == Data("second".utf8))
        }
    }

    @Test("backing up a missing file throws and creates nothing")
    func backUpMissingFile() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(url: directory.appending(path: "config.json"))
            #expect(throws: (any Error).self) {
                try store.backUp()
            }
            let names = try entryNames(in: directory)
            #expect(names.isEmpty)
        }
    }

    // MARK: Checking a save

    @Test("checkSave refuses what save refuses, and writes nothing either way")
    func checkSaveRefuses() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            let store = ConfigStore(url: url)

            #expect(throws: ConfigStoreError.invalid(.unsupportedVersion(2))) {
                try store.checkSave(Config(version: 2))
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))

            let newer = Data(#"{"bindings":[],"version":2}"#.utf8)
            try newer.write(to: url)
            #expect(throws: ConfigStoreError.newerFileVersion(2)) {
                try store.checkSave(.default)
            }
            #expect(try Data(contentsOf: url) == newer)
        }
    }

    @Test("checkSave accepts a valid config and writes nothing")
    func checkSaveAccepts() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try ConfigStore(url: url).checkSave(Config(bindings: allKindsBindings))
            #expect(try entryNames(in: directory).isEmpty)
        }
    }
}
