import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// The first load at launch, which writes the default shortcuts when there is no file, and the
/// replacement that Settings uses to restore them, which keeps a copy of the file first.
@MainActor
@Suite("Shortcut manager defaults")
struct ShortcutManagerDefaultsTests {
    @MainActor
    private final class Fixture {
        let directory: URL
        let backend = FakeHotkeyBackend()
        let manager: ShortcutManager

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "piccolo-manager-defaults-\(UUID().uuidString)")
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

        /// The copies made by replacements: `config.backup-<stamp>.json`, or a numbered one.
        func backupNames() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.wholeMatch(of: #/config\.backup-\d{8}-\d{6}(-\d+)?\.json/#) != nil }
                .sorted()
        }
    }

    private func binding(_ keyCode: Int) -> KeyBinding {
        KeyBinding(
            action: .placeWindow(.preset(.leftHalf)),
            shortcut: Shortcut(keyCode: keyCode, modifiers: [.control, .option, .shift, .command]))
    }

    // MARK: Launch

    @Test("at launch with no file, the default shortcuts are written, loaded and all 33 are registered")
    func launchWritesDefaults() throws {
        let fixture = try Fixture()

        let wrote = fixture.manager.loadAtLaunch(from: fixture.configURL)

        #expect(wrote)
        #expect(FileManager.default.fileExists(atPath: fixture.configURL.path))
        let status = fixture.manager.status
        #expect(status.bindingCount == 33, "the status counts \(status.bindingCount) bindings")
        #expect(status.registered.count == 33, "the status lists \(status.registered.count) as registered")
        #expect(status.issues.isEmpty, "the issues are \(status.issues)")
        #expect(fixture.backend.liveShortcuts.count == 33)
        let written = try ConfigStore(url: fixture.configURL).load().config
        #expect(written.bindings.map(\.action) == Config.defaultShortcuts.bindings.map(\.action))
        #expect(written.bindings.map(\.shortcut) == Config.defaultShortcuts.bindings.map(\.shortcut))
    }

    @Test(
        "at launch, an existing file is never written over, also one with no bindings",
        arguments: [
            #"{"version": 1, "bindings": []}"#,
            #"{"version": 1, "bindings": [], "resizeStep": 0.1}"#,
        ])
    func launchLeavesExistingFileAlone(text: String) throws {
        let fixture = try Fixture()
        let original = Data(text.utf8)
        try original.write(to: fixture.configURL)

        let wrote = fixture.manager.loadAtLaunch(from: fixture.configURL)

        #expect(!wrote)
        #expect(try Data(contentsOf: fixture.configURL) == original)
        #expect(fixture.manager.status.bindingCount == 0)
        #expect(fixture.manager.status.registered.isEmpty)
        #expect(fixture.backend.live.isEmpty)
    }

    @Test("at launch, an existing file with bindings loads as it is, and nothing is added to it")
    func launchLoadsExistingFile() throws {
        let fixture = try Fixture()
        let mine = binding(FunctionKey.f13)
        try ConfigStore(url: fixture.configURL).save(Config(bindings: [mine]))
        let original = try Data(contentsOf: fixture.configURL)

        let wrote = fixture.manager.loadAtLaunch(from: fixture.configURL)

        #expect(!wrote)
        #expect(try Data(contentsOf: fixture.configURL) == original)
        #expect(fixture.manager.status.registered.map(\.id) == [mine.id])
        #expect(fixture.manager.status.issues.isEmpty)
    }

    @Test("deleting the file brings the defaults back at the next launch")
    func deletedFileComesBack() throws {
        let fixture = try Fixture()
        fixture.manager.loadAtLaunch(from: fixture.configURL)
        try FileManager.default.removeItem(at: fixture.configURL)

        let wrote = fixture.manager.loadAtLaunch(from: fixture.configURL)

        #expect(wrote)
        #expect(fixture.manager.status.registered.count == 33)
    }

    @Test("reloading after the file was deleted loads no bindings and writes nothing")
    func reloadWritesNothing() throws {
        let fixture = try Fixture()
        fixture.manager.loadAtLaunch(from: fixture.configURL)
        try FileManager.default.removeItem(at: fixture.configURL)

        let status = fixture.manager.load(from: fixture.configURL)

        #expect(status.registered.isEmpty)
        #expect(status.bindingCount == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.configURL.path))
    }

    @Test("a launch that cannot write the defaults says so in the issues and registers nothing")
    func launchCannotWrite() throws {
        let fixture = try Fixture()
        // A regular file where the folder of the config file should be: the folder cannot be created.
        let blocker = fixture.directory.appending(path: "blocked")
        try Data("not a folder".utf8).write(to: blocker)
        let url = blocker.appending(path: "config.json")

        let wrote = fixture.manager.loadAtLaunch(from: url)

        #expect(!wrote)
        let status = fixture.manager.status
        #expect(status.registered.isEmpty)
        #expect(status.issues.count == 1, "the issues are \(status.issues)")
        #expect(status.issues.first?.contains("could not be written") == true, "the issues are \(status.issues)")
    }

    // MARK: Replacing

    @Test("replacing keeps a copy of the file as it was and registers the defaults")
    func replaceKeepsCopy() throws {
        let fixture = try Fixture()
        try ConfigStore(url: fixture.configURL).save(
            Config(bindings: [binding(FunctionKey.f13), binding(FunctionKey.f14)]))
        fixture.manager.load(from: fixture.configURL)
        let original = try Data(contentsOf: fixture.configURL)

        let replacement = try fixture.manager.replaceKeepingCopy(with: Config.defaultShortcuts.bindings)

        let copy = try #require(replacement.copy)
        #expect(copy.lastPathComponent.wholeMatch(of: #/config\.backup-\d{8}-\d{6}(-\d+)?\.json/#) != nil)
        #expect(try Data(contentsOf: copy) == original)
        #expect(try ConfigStore(url: fixture.configURL).load().config.bindings.count == 33)
        #expect(replacement.status.registered.count == 33)
        #expect(replacement.status.issues.isEmpty, "the issues are \(replacement.status.issues)")
        #expect(fixture.backend.liveShortcuts.count == 33)
    }

    @Test("replacing with no file keeps no copy and creates the file")
    func replaceWithoutFile() throws {
        let fixture = try Fixture()

        let replacement = try fixture.manager.replaceKeepingCopy(with: Config.defaultShortcuts.bindings)

        #expect(replacement.copy == nil)
        #expect(try fixture.backupNames().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.configURL.path))
        #expect(replacement.status.registered.count == 33)
    }

    @Test("a refused replacement copies nothing and changes nothing")
    func refusedReplacement() throws {
        let fixture = try Fixture()
        let newer = Data(#"{"bindings":[],"version":2}"#.utf8)
        try newer.write(to: fixture.configURL)
        fixture.manager.load(from: fixture.configURL)

        #expect(throws: ConfigStoreError.newerFileVersion(2)) {
            _ = try fixture.manager.replaceKeepingCopy(with: Config.defaultShortcuts.bindings)
        }

        #expect(try Data(contentsOf: fixture.configURL) == newer)
        #expect(try fixture.backupNames().isEmpty)
    }

    @Test("after a replacement the notice about dropped entries is gone, and a later save copies nothing")
    func replaceClearsDroppedEntries() throws {
        let fixture = try Fixture()
        let kept = binding(FunctionKey.f13)
        let json = String(decoding: try JSONEncoder().encode(kept), as: UTF8.self)
        try Data(#"{"version": 1, "bindings": [\#(json), {"id": "not-a-uuid"}]}"#.utf8).write(to: fixture.configURL)
        fixture.manager.load(from: fixture.configURL)

        let replacement = try fixture.manager.replaceKeepingCopy(with: Config.defaultShortcuts.bindings)
        #expect(replacement.copy != nil)
        #expect(replacement.status.issues.isEmpty, "the issues are \(replacement.status.issues)")

        try fixture.manager.save(Config(bindings: [binding(FunctionKey.f14)]))
        let copies = try fixture.backupNames()
        #expect(copies.count == 1, "the copies are \(copies)")
    }

    @Test("restoring keeps the resize step and the window settings, in the file and in the manager")
    func restoreKeepsSettings() throws {
        let fixture = try Fixture()
        try ConfigStore(url: fixture.configURL).save(
            Config(
                resizeStep: 0.1, animation: .slow, gridFillOrder: .columns, destinationPreview: false,
                bindings: [binding(FunctionKey.f13)]))
        fixture.manager.load(from: fixture.configURL)
        let defaults = Config.defaultShortcuts.bindings

        let replacement = try fixture.manager.replaceKeepingCopy(with: defaults)

        let expected = Config(
            resizeStep: 0.1, animation: .slow, gridFillOrder: .columns, destinationPreview: false,
            bindings: defaults)
        #expect(try ConfigStore(url: fixture.configURL).load().config == expected)
        #expect(fixture.manager.config == expected)
        #expect(replacement.status.issues.isEmpty, "the issues are \(replacement.status.issues)")
    }
}
