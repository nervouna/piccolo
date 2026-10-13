import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

@MainActor
@Suite("Shortcut manager")
struct ShortcutManagerTests {
    @MainActor
    private final class Fixture {
        let directory: URL
        let backend = FakeHotkeyBackend()
        let manager: ShortcutManager
        let fired = Fired()

        final class Fired {
            var runs: [(action: Action, id: UUID)] = []
        }

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "piccolo-shortcut-manager-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fired = fired
            manager = ShortcutManager(
                registrar: HotkeyRegistrar(backend: backend),
                initialURL: directory.appending(path: "config.json")
            ) { action, id in
                fired.runs.append((action, id))
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        /// A config file `name` in the temporary directory holding `bindings`.
        func write(_ bindings: [KeyBinding], as name: String = "config.json") throws -> URL {
            let url = directory.appending(path: name)
            try ConfigStore(url: url).save(Config(bindings: bindings))
            return url
        }

        /// A `config.json` whose bindings are `entries`, as JSON text and in this order. An entry
        /// that is not a valid binding stays in the file, so that the loader skips it.
        func writeEntries(_ entries: [String]) throws -> URL {
            let url = directory.appending(path: "config.json")
            try Data(#"{"version": 1, "bindings": [\#(entries.joined(separator: ", "))]}"#.utf8).write(to: url)
            return url
        }
    }

    private func shortcut(_ keyCode: Int, _ modifiers: Modifier...) -> Shortcut {
        Shortcut(keyCode: keyCode, modifiers: Set(modifiers))
    }

    private let hyper: Set<Modifier> = [.control, .option, .shift, .command]

    private func binding(
        _ keyCode: Int?, _ action: Action = .placeWindow(.preset(.leftHalf))
    ) -> KeyBinding {
        KeyBinding(
            action: action,
            shortcut: keyCode.map { Shortcut(keyCode: $0, modifiers: hyper) })
    }

    // MARK: Loading

    @Test("before anything is loaded nothing is registered, and the status names the initial file")
    func initialStatus() throws {
        let fixture = try Fixture()
        let status = fixture.manager.status
        #expect(status.path == fixture.directory.appending(path: "config.json").path)
        #expect(status.registered.isEmpty)
        #expect(status.issues.isEmpty)
        #expect(fixture.backend.calls.isEmpty)
    }

    @Test("a missing file means no bindings, no issues, and no file is created")
    func missingFile() throws {
        let fixture = try Fixture()
        let url = fixture.directory.appending(path: "nothing-here.json")

        let status = fixture.manager.load(from: url)

        #expect(status == ShortcutManager.Status(path: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @Test("the shortcuts of a valid file are registered")
    func validFile() throws {
        let fixture = try Fixture()
        let first = binding(FunctionKey.f13)
        let second = binding(FunctionKey.f14, .placeWindow(.preset(.maximize)))
        let url = try fixture.write([first, second])

        let status = fixture.manager.load(from: url)

        #expect(status.path == url.path)
        #expect(status.bindingCount == 2)
        #expect(
            status.registered == [
                ShortcutPlan.Registration(id: first.id, shortcut: first.shortcut!),
                ShortcutPlan.Registration(id: second.id, shortcut: second.shortcut!),
            ])
        #expect(status.issues.isEmpty)
        #expect(fixture.manager.status == status)
        #expect(fixture.backend.liveShortcuts == [first.shortcut!, second.shortcut!])
    }

    @Test("bindings without a shortcut count but register nothing, and are no problem")
    func bindingWithoutShortcut() throws {
        let fixture = try Fixture()
        let url = try fixture.write([binding(nil), binding(FunctionKey.f13)])

        let status = fixture.manager.load(from: url)

        #expect(status.bindingCount == 2)
        #expect(status.registered.count == 1)
        #expect(status.issues.isEmpty)
    }

    @Test("a shortcut that may not be registered, and a duplicate, are reported by binding index and the rest still registers")
    func planIssues() throws {
        let fixture = try Fixture()
        let first = binding(FunctionKey.f13)
        let plainA = KeyBinding(
            action: .placeWindow(.preset(.center)), shortcut: shortcut(0))
        let duplicate = binding(FunctionKey.f13, .placeWindow(.preset(.maximize)))
        let url = try fixture.write([first, binding(nil), plainA, duplicate])

        let status = fixture.manager.load(from: url)

        #expect(status.bindingCount == 4)
        #expect(status.registered.map(\.id) == [first.id])
        // One line for each, and each starts with the binding it is about.
        #expect(status.issues.count == 2)
        #expect(status.issues.first?.hasPrefix("bindings[2]") == true)
        #expect(status.issues.last?.hasPrefix("bindings[3]") == true)
    }

    @Test("load issues of the file are kept: a bad binding is skipped and named")
    func loadIssues() throws {
        let fixture = try Fixture()
        let good = binding(FunctionKey.f13)
        let url = fixture.directory.appending(path: "config.json")
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let text = #"{"version": 1, "bindings": [\#(goodJSON), {"id": "not-a-uuid"}]}"#
        try Data(text.utf8).write(to: url)

        let status = fixture.manager.load(from: url)

        #expect(status.bindingCount == 1)
        #expect(status.registered.map(\.id) == [good.id])
        #expect(status.issues.count == 1)
        #expect(status.issues.first?.contains("bindings[1]") == true)
    }

    @Test("a file that is not JSON is moved aside, reported, and registers nothing")
    func notJSON() throws {
        let fixture = try Fixture()
        let url = fixture.directory.appending(path: "config.json")
        try Data("this is not json".utf8).write(to: url)

        let status = fixture.manager.load(from: url)

        #expect(status.registered.isEmpty)
        #expect(status.bindingCount == 0)
        #expect(status.issues.count == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
        #expect(names.count == 1 && names[0].hasPrefix("config.corrupt-"), "the directory holds \(names)")
    }

    @Test("a file that cannot be read is reported and registers nothing")
    func unreadableFile() throws {
        let fixture = try Fixture()
        // A directory where the file should be: reading it fails with an I/O error.
        let url = fixture.directory.appending(path: "config.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        let status = fixture.manager.load(from: url)

        #expect(status.registered.isEmpty)
        #expect(status.issues.count == 1)
        #expect(status.issues.first?.contains("config.json") == true)
    }

    // MARK: Replacing

    @Test("loading a second file replaces the first")
    func loadReplaces() throws {
        let fixture = try Fixture()
        let a = binding(FunctionKey.f13)
        let b = binding(FunctionKey.f14)
        let urlA = try fixture.write([a], as: "a.json")
        let urlB = try fixture.write([b], as: "b.json")

        fixture.manager.load(from: urlA)
        let status = fixture.manager.load(from: urlB)

        #expect(status.path == urlB.path)
        #expect(status.registered.map(\.id) == [b.id])
        #expect(fixture.backend.liveShortcuts == [b.shortcut!])

        // The first file's hotkey is gone for good.
        fixture.backend.press(a.shortcut!)
        #expect(fixture.fired.runs.isEmpty)
    }

    @Test("problems of the first file do not carry over to the second")
    func issuesDoNotCarryOver() throws {
        let fixture = try Fixture()
        let bad = fixture.directory.appending(path: "bad.json")
        try Data("{".utf8).write(to: bad)
        let good = try fixture.write([binding(FunctionKey.f13)], as: "good.json")

        #expect(!fixture.manager.load(from: bad).issues.isEmpty)
        #expect(fixture.manager.load(from: good).issues.isEmpty)
    }

    @Test("reloading the same file keeps its shortcuts registered")
    func reloadSameFile() throws {
        let fixture = try Fixture()
        let a = binding(FunctionKey.f13)
        let url = try fixture.write([a])

        fixture.manager.load(from: url)
        let status = fixture.manager.load(from: url)

        #expect(status.issues.isEmpty)
        #expect(status.registered.map(\.id) == [a.id])
    }

    @Test("a missing file after a loaded one releases everything")
    func missingAfterLoaded() throws {
        let fixture = try Fixture()
        fixture.manager.load(from: try fixture.write([binding(FunctionKey.f13)]))

        let status = fixture.manager.load(from: fixture.directory.appending(path: "gone.json"))

        #expect(status.registered.isEmpty)
        #expect(fixture.backend.live.isEmpty)
    }

    // MARK: Refused shortcuts

    @Test("a shortcut the system refuses is reported by binding index with the reason; the others register")
    func refusedShortcut() throws {
        let fixture = try Fixture()
        let good = binding(FunctionKey.f13)
        let refused = binding(FunctionKey.f14)
        fixture.backend.refuse(refused.shortcut!, reason: "taken by the system")
        let url = try fixture.write([good, refused])

        let status = fixture.manager.load(from: url)

        #expect(status.registered.map(\.id) == [good.id])
        #expect(status.issues.count == 1)
        let issue = try #require(status.issues.first)
        #expect(issue.contains("bindings[1]"))
        #expect(issue.contains("taken by the system"))
    }

    // MARK: Positions in the file

    /// The text of `binding` as a config file holds it.
    private func json(_ binding: KeyBinding) throws -> String {
        String(decoding: try JSONEncoder().encode(binding), as: UTF8.self)
    }

    /// A binding entry the loader skips: its ID is not a UUID.
    private let undecodableEntry = #"{"id": "not-a-uuid"}"#

    @Test("after a skipped binding, the load issue and the duplicate name the positions in the file")
    func duplicateAfterSkippedBinding() throws {
        let fixture = try Fixture()
        let first = binding(FunctionKey.f13)
        let second = binding(FunctionKey.f14)
        let duplicate = binding(FunctionKey.f14, .placeWindow(.preset(.maximize)))
        let url = try fixture.writeEntries([
            try json(first), undecodableEntry, try json(second), try json(duplicate),
        ])

        let status = fixture.manager.load(from: url)

        #expect(status.registered.map(\.id) == [first.id, second.id])
        #expect(status.issues.count == 2)
        #expect(status.issues.first?.hasPrefix("bindings[1]") == true)
        let duplicateIssue = try #require(status.issues.last)
        #expect(duplicateIssue.hasPrefix("bindings[3]"), "the duplicate issue is \"\(duplicateIssue)\"")
        #expect(duplicateIssue.contains("bindings[2]"), "the duplicate issue is \"\(duplicateIssue)\"")
        #expect(!duplicateIssue.contains("bindings[1]"), "the duplicate issue is \"\(duplicateIssue)\"")
    }

    @Test("a shortcut that may not be registered, after a skipped binding, is named by its position in the file")
    func unregistrableAfterSkippedBinding() throws {
        let fixture = try Fixture()
        let first = binding(FunctionKey.f13)
        let plainA = KeyBinding(action: .placeWindow(.preset(.center)), shortcut: shortcut(0))
        let url = try fixture.writeEntries([try json(first), undecodableEntry, try json(plainA)])

        let status = fixture.manager.load(from: url)

        #expect(status.registered.map(\.id) == [first.id])
        #expect(status.issues.count == 2)
        let issue = try #require(status.issues.last)
        #expect(issue.hasPrefix("bindings[2]"), "the issue is \"\(issue)\"")
    }

    @Test("a shortcut the system refuses, after a skipped binding, is named by its position in the file")
    func refusedAfterSkippedBinding() throws {
        let fixture = try Fixture()
        let good = binding(FunctionKey.f13)
        let refused = binding(FunctionKey.f14)
        fixture.backend.refuse(refused.shortcut!, reason: "taken by the system")
        let url = try fixture.writeEntries([try json(good), undecodableEntry, try json(refused)])

        let status = fixture.manager.load(from: url)

        #expect(status.registered.map(\.id) == [good.id])
        #expect(status.issues.count == 2)
        let issue = try #require(status.issues.last)
        #expect(issue.hasPrefix("bindings[2]"), "the issue is \"\(issue)\"")
        #expect(issue.contains("taken by the system"))
    }

    @Test("after a save from Settings the issues name the bindings by their position in the saved list")
    func positionsAfterSave() throws {
        let fixture = try Fixture()
        let first = binding(FunctionKey.f13)
        let second = binding(FunctionKey.f14)
        let url = try fixture.writeEntries([try json(first), undecodableEntry, try json(second)])
        fixture.manager.load(from: url)

        // Settings appends a binding that shares the shortcut of the second one.
        let added = binding(FunctionKey.f14, .moveToDisplay(.next))
        let status = try fixture.manager.save(Config(bindings: fixture.manager.config.bindings + [added]))

        #expect(status.registered.map(\.id) == [first.id, second.id])
        #expect(status.issues.count == 1)
        let issue = try #require(status.issues.first)
        #expect(issue.hasPrefix("bindings[2]"), "the issue is \"\(issue)\"")
        #expect(issue.contains("bindings[1]"), "the issue is \"\(issue)\"")
    }

    // MARK: Pressing

    @Test("pressing a registered shortcut hands over the action and the ID of its binding")
    func pressRunsAction() throws {
        let fixture = try Fixture()
        let left = binding(FunctionKey.f13, .placeWindow(.preset(.leftHalf)))
        let next = binding(FunctionKey.f14, .moveToDisplay(.next))
        fixture.manager.load(from: try fixture.write([left, next]))

        fixture.backend.press(next.shortcut!)
        fixture.backend.press(left.shortcut!)

        #expect(fixture.fired.runs.map(\.id) == [next.id, left.id])
        #expect(fixture.fired.runs.map(\.action) == [.moveToDisplay(.next), .placeWindow(.preset(.leftHalf))])
    }

    // MARK: Status line

    @Test("the summary counts shortcuts and, when there are any, problems")
    func summary() {
        let registration = ShortcutPlan.Registration(
            id: UUID(), shortcut: Shortcut(keyCode: FunctionKey.f13, modifiers: []))
        typealias Status = ShortcutManager.Status

        #expect(Status(path: "x").summary == "0 shortcuts active")
        #expect(Status(path: "x", registered: [registration]).summary == "1 shortcut active")
        #expect(
            Status(path: "x", registered: [registration, registration, registration]).summary
                == "3 shortcuts active")
        #expect(
            Status(path: "x", registered: [registration], issues: ["a"]).summary
                == "1 shortcut active, 1 config problem")
        #expect(
            Status(path: "x", registered: [registration, registration], issues: ["a", "b"]).summary
                == "2 shortcuts active, 2 config problems")
        #expect(Status(path: "x", issues: ["a"]).summary == "0 shortcuts active, 1 config problem")
    }
}
