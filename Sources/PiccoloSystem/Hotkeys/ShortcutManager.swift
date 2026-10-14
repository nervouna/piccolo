import Foundation
import PiccoloCore

/// Loads a config file and keeps its shortcuts registered as global hotkeys.
///
/// ``load(from:)`` reads the file, decides which shortcuts may be registered
/// (`ShortcutPlan.resolve`), hands them to the registrar and records what came of it in
/// ``status``. Every call replaces the previous state completely. A hotkey press calls
/// `onAction` with the action of its binding, on the main thread; the closure must return
/// quickly and run the action somewhere else.
///
/// ``save(_:)`` writes an edited config to the file that is loaded and applies it.
/// ``setSuspended(_:)`` releases every hotkey for a while, for example while a shortcut is being
/// recorded, and registers them again afterwards; loads and saves during that time register
/// nothing, and the suspension outlives them.
@MainActor
public final class ShortcutManager {
    /// What the last ``load(from:)`` came to.
    public struct Status: Equatable, Sendable {
        /// The file that was loaded.
        public var path: String
        /// The bindings the file contributed, after bad ones were skipped. Not all of them have
        /// a shortcut, and not every shortcut is registered.
        public var bindingCount: Int
        /// The shortcuts that are registered, in binding order.
        public var registered: [ShortcutPlan.Registration]
        /// One line for each problem: bindings skipped while loading, shortcuts that may not be
        /// registered, shortcuts the system refused, and, after a save that copied the file, where
        /// the copy is. Empty when everything is in order.
        public var issues: [String]

        public init(
            path: String, bindingCount: Int = 0, registered: [ShortcutPlan.Registration] = [],
            issues: [String] = []
        ) {
            self.path = path
            self.bindingCount = bindingCount
            self.registered = registered
            self.issues = issues
        }

        /// The line for the menu: "3 shortcuts active", or "3 shortcuts active, 2 config problems".
        public var summary: String {
            var text = "\(registered.count) \(registered.count == 1 ? "shortcut" : "shortcuts") active"
            if !issues.isEmpty {
                text += ", \(issues.count) config \(issues.count == 1 ? "problem" : "problems")"
            }
            return text
        }
    }

    private let registrar: HotkeyRegistrar
    private let onAction: @MainActor (_ action: Action, _ bindingID: UUID) -> Void
    private var actions: [UUID: Action] = [:]
    /// The file the last ``load(from:)`` read, and where ``save(_:)`` writes.
    private var url: URL
    /// The problems the last load found in the file itself, before the shortcuts were looked at.
    private var loadIssues: [String] = []
    /// Whether the file the last ``load(from:)`` read held entries that the load did not keep: a
    /// skipped binding or an invalid `resizeStep`. A save over such a file copies it first.
    private var droppedEntries = false
    /// The copy made of the file before a save, since the last ``load(from:)``. There is at most
    /// one per load: later saves make no further copy, and the issues name this one until the next load.
    private var backupCopy: URL?

    /// Nothing is registered until the first ``load(from:)``.
    public private(set) var status: Status

    /// The config the last ``load(from:)`` read: `Config.default` before any load, for a missing
    /// file and for one that could not be used.
    public private(set) var config: Config = .default

    /// The position in the file of each binding of ``config``, from the last ``load(from:)``. Issues
    /// name bindings by these positions, so that they point at the same entry as the file does.
    private var sourceIndices: [UUID: Int] = [:]

    /// Whether the hotkeys are released for the time being. See ``setSuspended(_:)``.
    public private(set) var isSuspended = false

    /// - Parameters:
    ///   - initialURL: The file reported by ``status`` before anything is loaded.
    ///   - onAction: Called on the main thread when a registered shortcut is pressed.
    public init(
        registrar: HotkeyRegistrar,
        initialURL: URL,
        onAction: @escaping @MainActor (_ action: Action, _ bindingID: UUID) -> Void
    ) {
        self.registrar = registrar
        self.onAction = onAction
        self.url = initialURL
        self.status = Status(path: initialURL.path)
    }

    /// Loads the config at `url` and registers its shortcuts, replacing whatever was loaded
    /// before. A missing file gives no bindings. An unreadable one is reported in the issues,
    /// and nothing stays registered.
    @discardableResult
    public func load(from url: URL) -> Status {
        droppedEntries = read(url)
        backupCopy = nil
        return register()
    }

    /// The first load at launch. When there is no file at `url`, writes `Config.defaultShortcuts` there
    /// first, then loads the file as ``load(from:)`` does. A file that exists is never written over,
    /// whatever it holds. Answers whether the defaults were written. When they could not be written,
    /// the issues say so and the load goes on with no bindings.
    @discardableResult
    public func loadAtLaunch(from url: URL) -> Bool {
        var wrote = false
        var notice: String?
        do {
            wrote = try ConfigStore(url: url).createIfMissing(.defaultShortcuts)
        } catch {
            notice = "the default shortcuts could not be written to \(url.lastPathComponent): \(error.localizedDescription)"
        }
        droppedEntries = read(url)
        backupCopy = nil
        if let notice {
            loadIssues.append(notice)
        }
        _ = register()
        return wrote
    }

    /// What ``replaceKeepingCopy(with:)`` left behind.
    public struct Replacement: Equatable, Sendable {
        /// The copy made of the file before it was replaced, or `nil` when there was no file to copy.
        public var copy: URL?
        /// The status after the replacement.
        public var status: Status
    }

    /// Makes `config` the config in use, as ``save(_:)`` does, after copying the file that is in use
    /// next to itself as `ConfigStore.backUp()` does. The copy is made whatever the last load dropped:
    /// the bindings are replaced as a whole, so the file as it was stays recoverable. Nothing is copied
    /// or changed when `config` is refused.
    ///
    /// - Throws: `ConfigStoreError` when `config` is invalid or the file is from a newer version, and
    ///   the I/O error when the copy or the file cannot be written.
    @discardableResult
    public func replaceKeepingCopy(with config: Config) throws -> Replacement {
        let store = ConfigStore(url: url)
        try store.checkSave(config)
        var copy: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            copy = try store.backUp()
        }
        try store.save(config)
        droppedEntries = read(url)
        backupCopy = nil
        return Replacement(copy: copy, status: register())
    }

    /// Writes `config` to the file that was loaded last (the initial file before any load),
    /// creating its folder when needed, and loads it again, so that the shortcuts take effect at
    /// once and ``status`` describes the saved file.
    ///
    /// When the last ``load(from:)`` dropped entries from that file, the file is first copied next
    /// to itself as `config.backup-<yyyyMMdd-HHmmss>.json`. That happens once per load: a save that
    /// follows makes no further copy, and the issues say where the copy is until the next load.
    ///
    /// - Throws: `ConfigStoreError` when the config is invalid or the file is from a newer
    ///   version, and the I/O error when the copy or the file cannot be written. Nothing is
    ///   copied or changed when the config is refused.
    @discardableResult
    public func save(_ config: Config) throws -> Status {
        let store = ConfigStore(url: url)
        try store.checkSave(config)
        if droppedEntries && backupCopy == nil {
            backupCopy = try store.backUp()
        }
        try store.save(config)
        // The file now holds what was saved. Its own load drops nothing, so the flag stays as the
        // last load left it, and the copy and its notice stay until the next load.
        _ = read(url)
        return register()
    }

    /// Releases every hotkey (`true`) or registers the loaded config's shortcuts again (`false`).
    /// While suspended, ``status`` lists nothing as registered, and neither a load nor a save
    /// registers anything. Asking for the state that is already in force changes nothing.
    @discardableResult
    public func setSuspended(_ suspended: Bool) -> Status {
        guard suspended != isSuspended else { return status }
        isSuspended = suspended
        return register()
    }

    /// Reads the config at `url` into ``config``, ``sourceIndices`` and ``loadIssues``, and answers
    /// whether the file held entries that the load did not keep.
    private func read(_ url: URL) -> Bool {
        var issues: [String] = []
        var config = Config.default
        var sourceIndices: [UUID: Int] = [:]
        var dropped = false
        do {
            let result = try ConfigStore(url: url).load()
            config = result.config
            sourceIndices = result.sourceIndices
            issues += result.issues
            dropped = result.droppedEntries
        } catch {
            issues.append("\(url.lastPathComponent) could not be read: \(error.localizedDescription)")
        }
        self.url = url
        self.config = config
        self.sourceIndices = sourceIndices
        loadIssues = issues
        return dropped
    }

    /// Registers what the loaded config allows (nothing while suspended) and records the outcome.
    private func register() -> Status {
        var issues = loadIssues
        let plan = ShortcutPlan.resolve(config.bindings, sourceIndices: sourceIndices)
        issues += plan.issues

        let refusals = registrar.apply(isSuspended ? [] : plan.registrations) { [weak self] bindingID in
            self?.pressed(bindingID)
        }
        for refusal in refusals {
            issues.append("\(bindingName(refusal.id)) shortcut was refused: \(refusal.reason); it is not registered")
        }
        if let backupCopy {
            issues.append(
                "\(url.lastPathComponent) had entries that did not load, and saving leaves them out; "
                    + "the file as it was before the first save since loading is kept as "
                    + "\(backupCopy.lastPathComponent), next to it")
        }

        let registered = registrar.registered
        let registeredIDs = Set(registered.map(\.id))
        actions = Dictionary(
            config.bindings.filter { registeredIDs.contains($0.id) }.map { ($0.id, $0.action) },
            uniquingKeysWith: { first, _ in first })

        status = Status(
            path: url.path, bindingCount: config.bindings.count, registered: registered, issues: issues)
        return status
    }

    /// How an issue names a binding: by its position in the file, as `ShortcutPlan` does.
    private func bindingName(_ bindingID: UUID) -> String {
        let position = sourceIndices[bindingID] ?? config.bindings.firstIndex(where: { $0.id == bindingID })
        return position.map { "bindings[\($0)]" } ?? "binding \(bindingID.uuidString)"
    }

    private func pressed(_ bindingID: UUID) {
        guard let action = actions[bindingID] else { return }
        onAction(action, bindingID)
    }
}
