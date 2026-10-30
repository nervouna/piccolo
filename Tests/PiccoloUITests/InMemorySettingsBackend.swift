import Foundation
import PiccoloCore

@testable import PiccoloUI

/// A backend that keeps the config in memory and records what the model asks of it.
@MainActor
final class InMemorySettingsBackend: SettingsBackend {
    var config: Config
    /// The issues `current()` reports.
    var currentIssues: [String]
    /// The bindings `current()` reports as inactive.
    var inactive: Set<UUID> = []
    /// What the next `save` answers with.
    var issuesAfterSave: [String] = []
    /// When set, `save` throws this and changes nothing.
    var failure: String?
    var onExternalChange: (@MainActor () -> Void)?

    /// Every config that was saved, in order.
    private(set) var saved: [Config] = []
    /// Whether the hotkeys were suspended at the time of each save.
    private(set) var suspendedAtSave: [Bool] = []
    /// Every request to suspend (`true`) or restore (`false`) the hotkeys, in order.
    private(set) var suspendRequests: [Bool] = []
    private(set) var isSuspended = false

    init(config: Config = .default, issues: [String] = []) {
        self.config = config
        self.currentIssues = issues
    }

    func current() -> SettingsSnapshot {
        SettingsSnapshot(config: config, issues: currentIssues, inactiveBindingIDs: inactive)
    }

    func save(_ config: Config) throws -> [String] {
        if let failure {
            throw SettingsSaveError(failure)
        }
        self.config = config
        saved.append(config)
        suspendedAtSave.append(isSuspended)
        currentIssues = issuesAfterSave
        return issuesAfterSave
    }

    /// When set, the issues `current()` reports once the hotkeys are restored.
    var issuesAfterResume: [String]?

    /// Whether there is a config file to copy when bindings are replaced.
    var hasFile = true
    /// The copies `backUpAndReplace` made, in order.
    private(set) var copies: [String] = []
    /// The file name `backUpAndReplace` gives its copy.
    static let copyName = "config.backup-test.json"

    func backUpAndReplace(with bindings: [KeyBinding]) throws -> String? {
        if let failure {
            throw SettingsSaveError(failure)
        }
        let copy = hasFile ? Self.copyName : nil
        if let copy {
            copies.append(copy)
        }
        var replaced = config
        replaced.bindings = bindings
        config = replaced
        saved.append(replaced)
        suspendedAtSave.append(isSuspended)
        currentIssues = issuesAfterSave
        return copy
    }

    func setShortcutsSuspended(_ suspended: Bool) {
        suspendRequests.append(suspended)
        isSuspended = suspended
        if !suspended, let issuesAfterResume {
            currentIssues = issuesAfterResume
        }
    }

    /// The config was replaced from outside, for example by a reload from the menu.
    func replaceFromOutside(_ config: Config, issues: [String] = []) {
        self.config = config
        self.currentIssues = issues
        onExternalChange?()
    }
}

/// Fixed IDs and shortcuts for the model tests.
enum UIFixture {
    static let idA = UUID(uuidString: "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40")!
    static let idB = UUID(uuidString: "7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D")!
    static let idC = UUID(uuidString: "0D9E8F7A-6B5C-4D3E-8F2A-1B0C9D8E7F6A")!

    static let hyper: Set<Modifier> = [.control, .option, .shift, .command]
    static let f13 = Shortcut(keyCode: FunctionKey.f13, modifiers: hyper)
    static let f14 = Shortcut(keyCode: FunctionKey.f14, modifiers: hyper)
    static let f15 = Shortcut(keyCode: FunctionKey.f15, modifiers: hyper)

    /// The letter A with control: registrable, and not a function key.
    static let controlA = Shortcut(keyCode: 0, modifiers: [.control])

    /// Two bindings: Left Half on ⌃⌥⇧⌘F13 and Next Display without a shortcut.
    static func twoBindings() -> Config {
        Config(bindings: [
            KeyBinding(id: idA, action: .placeWindow(.preset(.leftHalf)), shortcut: f13),
            KeyBinding(id: idB, action: .moveToDisplay(.next)),
        ])
    }
}
