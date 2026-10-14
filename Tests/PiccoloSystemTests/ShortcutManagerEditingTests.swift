import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// Saving an edited config through the manager, and suspending the hotkeys while a shortcut is
/// recorded.
@MainActor
@Suite("Shortcut manager editing")
struct ShortcutManagerEditingTests {
    @MainActor
    private final class Fixture {
        let directory: URL
        let backend = FakeHotkeyBackend()
        let manager: ShortcutManager
        let initialURL: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "piccolo-manager-editing-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            initialURL = directory.appending(path: "nested").appending(path: "config.json")
            manager = ShortcutManager(
                registrar: HotkeyRegistrar(backend: backend), initialURL: initialURL
            ) { _, _ in }
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func write(_ bindings: [KeyBinding], as name: String = "config.json") throws -> URL {
            let url = directory.appending(path: name)
            try ConfigStore(url: url).save(Config(bindings: bindings))
            return url
        }
    }

    private let hyper: Set<Modifier> = [.control, .option, .shift, .command]

    private func binding(_ keyCode: Int?, _ action: Action = .placeWindow(.preset(.leftHalf))) -> KeyBinding {
        KeyBinding(action: action, shortcut: keyCode.map { Shortcut(keyCode: $0, modifiers: hyper) })
    }

    // MARK: config

    @Test("config is the default before a load and the loaded config after")
    func configAfterLoad() throws {
        let fixture = try Fixture()
        #expect(fixture.manager.config == .default)

        let a = binding(FunctionKey.f13)
        fixture.manager.load(from: try fixture.write([a]))
        #expect(fixture.manager.config.bindings == [a])

        fixture.manager.load(from: fixture.directory.appending(path: "missing.json"))
        #expect(fixture.manager.config == .default)
    }

    // MARK: save

    @Test("save writes the file that was loaded, creates nothing else, and registers the new shortcuts")
    func saveWritesLoadedFile() throws {
        let fixture = try Fixture()
        let old = binding(FunctionKey.f13)
        let url = try fixture.write([old], as: "loaded.json")
        fixture.manager.load(from: url)

        let added = binding(FunctionKey.f14, .placeWindow(.preset(.maximize)))
        let status = try fixture.manager.save(Config(resizeStep: 0.1, bindings: [old, added]))

        #expect(status.path == url.path)
        #expect(status.bindingCount == 2)
        #expect(status.registered.map(\.id) == [old.id, added.id])
        #expect(fixture.backend.liveShortcuts == [old.shortcut!, added.shortcut!])
        #expect(fixture.manager.config == Config(resizeStep: 0.1, bindings: [old, added]))

        let onDisk = try ConfigStore(url: url).load()
        #expect(onDisk.config.bindings == [old, added])
        #expect(onDisk.config.resizeStep == 0.1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["loaded.json"])
    }

    @Test("before any load, save writes the initial file and creates its folder")
    func saveCreatesFolder() throws {
        let fixture = try Fixture()
        #expect(!FileManager.default.fileExists(atPath: fixture.initialURL.deletingLastPathComponent().path))
        let a = binding(FunctionKey.f13)

        let status = try fixture.manager.save(Config(bindings: [a]))

        #expect(status.path == fixture.initialURL.path)
        #expect(FileManager.default.fileExists(atPath: fixture.initialURL.path))
        #expect(status.registered.map(\.id) == [a.id])
    }

    @Test("saving a shortcut the plan skips reports it in the issues")
    func saveReportsIssues() throws {
        let fixture = try Fixture()
        let first = binding(FunctionKey.f13)
        let plainA = KeyBinding(action: .moveToDisplay(.next), shortcut: Shortcut(keyCode: 0, modifiers: []))
        fixture.manager.load(from: try fixture.write([]))

        let status = try fixture.manager.save(Config(bindings: [first, plainA]))

        #expect(status.registered.map(\.id) == [first.id])
        #expect(status.issues.count == 1)
        #expect(status.issues.first?.hasPrefix("bindings[1]") == true)
    }

    @Test("an invalid config is not written and changes nothing")
    func saveInvalid() throws {
        let fixture = try Fixture()
        let a = binding(FunctionKey.f13)
        let url = try fixture.write([a])
        fixture.manager.load(from: url)
        let before = try Data(contentsOf: url)

        let invalid = Config(resizeStep: 0.9, bindings: [])
        #expect(throws: ConfigStoreError.self) { try fixture.manager.save(invalid) }

        #expect(try Data(contentsOf: url) == before)
        #expect(fixture.manager.config.bindings == [a])
        #expect(fixture.backend.liveShortcuts == [a.shortcut!])
    }

    @Test("a file from a newer version is not overwritten")
    func saveRefusesNewerFile() throws {
        let fixture = try Fixture()
        let url = fixture.directory.appending(path: "newer.json")
        try Data(#"{"version": 99, "bindings": []}"#.utf8).write(to: url)
        let before = try Data(contentsOf: url)
        fixture.manager.load(from: url)

        #expect(throws: ConfigStoreError.self) { try fixture.manager.save(Config(bindings: [binding(FunctionKey.f13)])) }

        #expect(try Data(contentsOf: url) == before)
    }

    // MARK: suspend

    @Test("suspending releases every hotkey and the status lists none; resuming registers them again")
    func suspendAndResume() throws {
        let fixture = try Fixture()
        let a = binding(FunctionKey.f13)
        let b = binding(FunctionKey.f14)
        fixture.manager.load(from: try fixture.write([a, b]))
        #expect(fixture.backend.live.count == 2)

        let suspended = fixture.manager.setSuspended(true)

        #expect(suspended.registered.isEmpty)
        #expect(fixture.manager.status.registered.isEmpty)
        #expect(fixture.manager.isSuspended)
        #expect(fixture.backend.live.isEmpty)
        #expect(suspended.bindingCount == 2)

        let resumed = fixture.manager.setSuspended(false)

        #expect(resumed.registered.map(\.id) == [a.id, b.id])
        #expect(!fixture.manager.isSuspended)
        #expect(fixture.backend.liveShortcuts == [a.shortcut!, b.shortcut!])
    }

    @Test("a pressed shortcut does nothing while suspended and works again afterwards")
    func pressWhileSuspended() throws {
        let backend = FakeHotkeyBackend()
        var fired: [UUID] = []
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "piccolo-manager-editing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ShortcutManager(
            registrar: HotkeyRegistrar(backend: backend), initialURL: directory.appending(path: "config.json")
        ) { _, id in fired.append(id) }
        let a = binding(FunctionKey.f13)
        let url = directory.appending(path: "config.json")
        try ConfigStore(url: url).save(Config(bindings: [a]))
        manager.load(from: url)

        manager.setSuspended(true)
        backend.press(a.shortcut!)
        backend.release(a.shortcut!)
        #expect(fired.isEmpty)

        manager.setSuspended(false)
        backend.press(a.shortcut!)
        backend.release(a.shortcut!)
        #expect(fired == [a.id])
    }

    @Test("suspending twice, or resuming without a suspension, changes nothing")
    func suspendIsIdempotent() throws {
        let fixture = try Fixture()
        fixture.manager.load(from: try fixture.write([binding(FunctionKey.f13)]))
        let callsBefore = fixture.backend.calls.count

        fixture.manager.setSuspended(false)
        #expect(fixture.backend.calls.count == callsBefore)

        fixture.manager.setSuspended(true)
        let callsAfterSuspend = fixture.backend.calls.count
        fixture.manager.setSuspended(true)
        #expect(fixture.backend.calls.count == callsAfterSuspend)
    }

    @Test("a load while suspended registers nothing, and the suspension outlives it")
    func loadWhileSuspended() throws {
        let fixture = try Fixture()
        let a = binding(FunctionKey.f13)
        let urlA = try fixture.write([a], as: "a.json")
        let b = binding(FunctionKey.f14)
        let urlB = try fixture.write([b], as: "b.json")
        fixture.manager.load(from: urlA)
        fixture.manager.setSuspended(true)

        let status = fixture.manager.load(from: urlB)

        #expect(status.path == urlB.path)
        #expect(status.bindingCount == 1)
        #expect(status.registered.isEmpty)
        #expect(fixture.backend.live.isEmpty)
        #expect(fixture.manager.isSuspended)

        fixture.manager.setSuspended(false)
        #expect(fixture.manager.status.registered.map(\.id) == [b.id])
        #expect(fixture.backend.liveShortcuts == [b.shortcut!])
    }

    @Test("a save while suspended writes the file but registers nothing until the hotkeys come back")
    func saveWhileSuspended() throws {
        let fixture = try Fixture()
        let a = binding(FunctionKey.f13)
        let url = try fixture.write([a])
        fixture.manager.load(from: url)
        fixture.manager.setSuspended(true)

        let b = binding(FunctionKey.f14)
        let status = try fixture.manager.save(Config(bindings: [a, b]))

        #expect(status.registered.isEmpty)
        #expect(fixture.backend.live.isEmpty)
        #expect(try ConfigStore(url: url).load().config.bindings == [a, b])

        fixture.manager.setSuspended(false)
        #expect(fixture.manager.status.registered.map(\.id) == [a.id, b.id])
    }

    @Test("problems with the config show while suspended, and a refusal shows once the hotkeys are back")
    func issuesWhileSuspended() throws {
        let fixture = try Fixture()
        let first = binding(FunctionKey.f13)
        let duplicate = binding(FunctionKey.f13, .placeWindow(.preset(.maximize)))
        let refused = binding(FunctionKey.f14)
        fixture.backend.refuse(refused.shortcut!, reason: "taken by the system")
        fixture.manager.load(from: try fixture.write([first, duplicate, refused]))
        fixture.manager.setSuspended(true)

        let suspended = fixture.manager.status
        #expect(suspended.issues.count == 1, "while suspended: \(suspended.issues)")
        #expect(suspended.issues.first?.hasPrefix("bindings[1]") == true)

        let resumed = fixture.manager.setSuspended(false)
        #expect(resumed.issues.count == 2, "after resuming: \(resumed.issues)")
        #expect(resumed.issues.last?.contains("taken by the system") == true)
    }

    @Test("suspending before anything is loaded is allowed and registers nothing later")
    func suspendBeforeLoad() throws {
        let fixture = try Fixture()
        fixture.manager.setSuspended(true)
        fixture.manager.load(from: try fixture.write([binding(FunctionKey.f13)]))
        #expect(fixture.backend.live.isEmpty)
        fixture.manager.setSuspended(false)
        #expect(fixture.backend.live.count == 1)
    }
}
