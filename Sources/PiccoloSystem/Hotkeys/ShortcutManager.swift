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
        /// registered, shortcuts the system refused. Empty when everything is in order.
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

    /// Nothing is registered until the first ``load(from:)``.
    public private(set) var status: Status

    /// The config the last ``load(from:)`` read: `Config.default` before any load, for a missing
    /// file and for one that could not be used.
    public private(set) var config: Config = .default

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
        var issues: [String] = []
        var config = Config.default
        do {
            let result = try ConfigStore(url: url).load()
            config = result.config
            issues += result.issues
        } catch {
            issues.append("\(url.lastPathComponent) could not be read: \(error.localizedDescription)")
        }
        self.url = url
        self.config = config
        loadIssues = issues
        return register()
    }

    /// Writes `config` to the file that was loaded last (the initial file before any load),
    /// creating its folder when needed, and loads it again, so that the shortcuts take effect at
    /// once and ``status`` describes the saved file.
    ///
    /// - Throws: `ConfigStoreError` when the config is invalid or the file is from a newer
    ///   version, and the I/O error when it cannot be written. Nothing changes then.
    @discardableResult
    public func save(_ config: Config) throws -> Status {
        try ConfigStore(url: url).save(config)
        return load(from: url)
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

    /// Registers what the loaded config allows (nothing while suspended) and records the outcome.
    private func register() -> Status {
        var issues = loadIssues
        let plan = ShortcutPlan.resolve(config.bindings)
        issues += plan.issues

        let refusals = registrar.apply(isSuspended ? [] : plan.registrations) { [weak self] bindingID in
            self?.pressed(bindingID)
        }
        for refusal in refusals {
            let index = config.bindings.firstIndex { $0.id == refusal.id }
            let name = index.map { "bindings[\($0)]" } ?? "binding \(refusal.id.uuidString)"
            issues.append("\(name) shortcut was refused: \(refusal.reason); it is not registered")
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

    private func pressed(_ bindingID: UUID) {
        guard let action = actions[bindingID] else { return }
        onAction(action, bindingID)
    }
}
