import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// The copy that a save makes of a file whose last load dropped entries, and what the issue list
/// says about it.
@MainActor
@Suite("Shortcut manager copies before a save")
struct ShortcutManagerBackupTests {
    @MainActor
    private final class Fixture {
        let directory: URL
        let backend = FakeHotkeyBackend()
        let manager: ShortcutManager

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "piccolo-manager-backup-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            manager = ShortcutManager(
                registrar: HotkeyRegistrar(backend: backend),
                initialURL: directory.appending(path: "config.json")
            ) { _, _ in }
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        var configURL: URL {
            directory.appending(path: "config.json")
        }

        /// Writes `config.json` as a user would: a version and these bindings, in this order.
        /// Entries that are not valid bindings stay in the file, so that the loader skips them.
        @discardableResult
        func writeEntries(_ entries: [String]) throws -> Data {
            let data = Data(#"{"version": 1, "bindings": [\#(entries.joined(separator: ", "))]}"#.utf8)
            try data.write(to: configURL)
            return data
        }

        /// The copies made before saves: `config.backup-<stamp>.json`, or a numbered one.
        func backupNames() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.wholeMatch(of: #/config\.backup-\d{8}-\d{6}(-\d+)?\.json/#) != nil }
                .sorted()
        }

        func bytes(ofBackup name: String) throws -> Data {
            try Data(contentsOf: directory.appending(path: name))
        }

        func json(_ binding: KeyBinding) throws -> String {
            String(decoding: try JSONEncoder().encode(binding), as: UTF8.self)
        }
    }

    /// A binding entry the loader skips: its ID is not a UUID.
    private let undecodableEntry = #"{"id": "not-a-uuid"}"#

    private func binding(_ keyCode: Int) -> KeyBinding {
        KeyBinding(
            action: .placeWindow(.preset(.leftHalf)),
            shortcut: Shortcut(keyCode: keyCode, modifiers: [.control, .option]))
    }

    /// Loads a file with one valid binding and one skipped entry, saves an edit of it and returns
    /// what the test needs to check: the bytes of the file before the save and the copy's name.
    private func saveAfterSkippedEntry(
        _ fixture: Fixture
    ) throws -> (original: Data, copy: String, status: ShortcutManager.Status) {
        let kept = binding(FunctionKey.f13)
        let original = try fixture.writeEntries([try fixture.json(kept), undecodableEntry])
        fixture.manager.load(from: fixture.configURL)

        let status = try fixture.manager.save(Config(bindings: [kept, binding(FunctionKey.f14)]))
        let copy = try #require(try fixture.backupNames().first)
        return (original, copy, status)
    }

    // MARK: Copies

    @Test("a save after a clean load makes no copy")
    func cleanLoadNoCopy() throws {
        let fixture = try Fixture()
        let kept = binding(FunctionKey.f13)
        try fixture.writeEntries([try fixture.json(kept)])
        fixture.manager.load(from: fixture.configURL)

        let status = try fixture.manager.save(Config(bindings: [kept, binding(FunctionKey.f14)]))

        #expect(try fixture.backupNames().isEmpty)
        #expect(status.issues.isEmpty)
    }

    @Test("a save after a load that skipped a binding makes exactly one copy, with the original bytes")
    func skippedEntryMakesOneCopy() throws {
        let fixture = try Fixture()

        let (original, copy, _) = try saveAfterSkippedEntry(fixture)

        #expect(try fixture.backupNames() == [copy])
        #expect(copy.wholeMatch(of: #/config\.backup-\d{8}-\d{6}\.json/#) != nil, "the copy is named \(copy)")
        #expect(try fixture.bytes(ofBackup: copy) == original)
        #expect(try ConfigStore(url: fixture.configURL).load().config.bindings.count == 2)
    }

    @Test("a second save after the same load makes no second copy")
    func secondSaveNoSecondCopy() throws {
        let fixture = try Fixture()
        let (_, copy, _) = try saveAfterSkippedEntry(fixture)

        let status = try fixture.manager.save(Config(bindings: [binding(FunctionKey.f13)]))

        #expect(try fixture.backupNames() == [copy])
        #expect(status.issues.count == 1, "the issues are \(status.issues)")
    }

    @Test("a save after a load that replaced an invalid resizeStep makes a copy too")
    func invalidResizeStepMakesCopy() throws {
        let fixture = try Fixture()
        let kept = binding(FunctionKey.f13)
        let original = Data(
            #"{"bindings": [\#(try fixture.json(kept))], "resizeStep": 0.9, "version": 1}"#.utf8)
        try original.write(to: fixture.configURL)
        fixture.manager.load(from: fixture.configURL)

        try fixture.manager.save(Config(bindings: [kept]))

        let copies = try fixture.backupNames()
        #expect(copies.count == 1)
        #expect(try fixture.bytes(ofBackup: try #require(copies.first)) == original)
    }

    @Test("a save after a load that skipped nothing, or found no file, makes no copy")
    func noCopyWithoutDroppedEntries() throws {
        let fixture = try Fixture()
        fixture.manager.load(from: fixture.configURL)

        try fixture.manager.save(Config(bindings: [binding(FunctionKey.f13)]))
        try fixture.manager.save(Config(bindings: [binding(FunctionKey.f14)]))

        #expect(try fixture.backupNames().isEmpty)
    }

    @Test("a file moved aside because it was unusable is not copied, the moved-aside file is the copy")
    func movedAsideFileMakesNoCopy() throws {
        let fixture = try Fixture()
        try Data("not json".utf8).write(to: fixture.configURL)
        fixture.manager.load(from: fixture.configURL)

        try fixture.manager.save(Config(bindings: [binding(FunctionKey.f13)]))

        #expect(try fixture.backupNames().isEmpty)
    }

    @Test("a refused save makes no copy, and the first valid save after it still makes one")
    func refusedSaveKeepsCopyForLater() throws {
        let fixture = try Fixture()
        let kept = binding(FunctionKey.f13)
        let original = try fixture.writeEntries([try fixture.json(kept), undecodableEntry])
        fixture.manager.load(from: fixture.configURL)

        #expect(throws: ConfigStoreError.self) {
            try fixture.manager.save(Config(resizeStep: 0.9, bindings: [kept]))
        }
        #expect(try fixture.backupNames().isEmpty)
        #expect(try Data(contentsOf: fixture.configURL) == original)

        try fixture.manager.save(Config(bindings: [kept]))

        let copies = try fixture.backupNames()
        #expect(copies.count == 1)
        #expect(try fixture.bytes(ofBackup: try #require(copies.first)) == original)
    }

    // MARK: Issue list

    @Test("the issue list after the save names the copy and says that entries did not load")
    func issueNamesCopy() throws {
        let fixture = try Fixture()

        let (_, copy, status) = try saveAfterSkippedEntry(fixture)

        let notice = try #require(status.issues.last, "the issues are \(status.issues)")
        #expect(notice.contains(copy), "the notice is \"\(notice)\"")
        #expect(notice.contains("did not load"), "the notice is \"\(notice)\"")
        #expect(fixture.manager.status.issues == status.issues)
    }

    @Test("the copy notice stays on every later save until the next load")
    func noticeStaysUntilLoad() throws {
        let fixture = try Fixture()
        let (_, copy, _) = try saveAfterSkippedEntry(fixture)

        let later = try fixture.manager.save(Config(bindings: [binding(FunctionKey.f13)]))
        #expect(later.issues.last?.contains(copy) == true, "the issues are \(later.issues)")

        let suspended = fixture.manager.setSuspended(true)
        #expect(suspended.issues.last?.contains(copy) == true, "the issues are \(suspended.issues)")
    }

    @Test("a reload of a clean file clears the notice, and the next save makes no copy")
    func reloadClearsNotice() throws {
        let fixture = try Fixture()
        let (_, copy, _) = try saveAfterSkippedEntry(fixture)
        try fixture.writeEntries([try fixture.json(binding(FunctionKey.f13))])

        let reloaded = fixture.manager.load(from: fixture.configURL)
        #expect(reloaded.issues.isEmpty, "the issues are \(reloaded.issues)")

        let saved = try fixture.manager.save(Config(bindings: [binding(FunctionKey.f14)]))
        #expect(saved.issues.isEmpty, "the issues are \(saved.issues)")
        #expect(try fixture.backupNames() == [copy])
    }

    // MARK: Reload resets the copy

    @Test("after a reload of a file that skipped entries, the next save copies it again, and the earlier copy stays")
    func reloadAllowsAnotherCopy() throws {
        let fixture = try Fixture()
        let (firstOriginal, firstCopy, _) = try saveAfterSkippedEntry(fixture)

        // The user edits the file by hand, adding another entry that does not load.
        let secondOriginal = try fixture.writeEntries([
            try fixture.json(binding(FunctionKey.f15)), #"{"id": "also-not-a-uuid"}"#,
        ])
        fixture.manager.load(from: fixture.configURL)
        let status = try fixture.manager.save(Config(bindings: [binding(FunctionKey.f15)]))

        // Whether both copies fell in the same second or not, neither replaces the other.
        let copies = try fixture.backupNames()
        #expect(copies.count == 2, "the copies are \(copies)")
        #expect(copies.contains(firstCopy))
        #expect(try fixture.bytes(ofBackup: firstCopy) == firstOriginal)
        let newest = try #require(copies.first { $0 != firstCopy })
        #expect(try fixture.bytes(ofBackup: newest) == secondOriginal)
        #expect(status.issues.last?.contains(newest) == true, "the issues are \(status.issues)")
    }

    @Test("a save after a load that replaced an unreadable window setting makes a copy too")
    func unreadableSettingMakesCopy() throws {
        let fixture = try Fixture()
        let kept = binding(FunctionKey.f13)
        let original = Data(
            #"{"animation": "bounce", "bindings": [\#(try fixture.json(kept))], "version": 1}"#.utf8)
        try original.write(to: fixture.configURL)
        fixture.manager.load(from: fixture.configURL)

        try fixture.manager.save(Config(bindings: [kept]))

        let copies = try fixture.backupNames()
        #expect(copies.count == 1)
        #expect(try fixture.bytes(ofBackup: try #require(copies.first)) == original)
        #expect(try ConfigStore(url: fixture.configURL).load().config.animation == .fast)
    }
}
