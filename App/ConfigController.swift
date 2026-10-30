import AppKit
import Observation
import OSLog
import PiccoloCore
import PiccoloSystem

/// Owns the loaded config and its global hotkeys for the whole run, and tells the menu what
/// came of the last load.
///
/// A hotkey runs its binding's action through `ActionExecutor`, one action at a time on a
/// queue of its own. The main thread, where the system delivers the hotkey, only hands the
/// action over: Accessibility calls can take seconds when an app does not answer.
///
/// With the destination preview on, a shortcut runs when it is released, and a shortcut held for
/// 0.2 s shows a highlight where its windows will go (see `ShortcutManager` and `DestinationPreview`).
/// The highlight is planned on the same queue as the actions.
@MainActor
@Observable
final class ConfigController {
    static let shared = ConfigController()

    /// What the last load came to: the file, the registered shortcuts and the problems.
    private(set) var status: ShortcutManager.Status

    /// Called after another file replaced the config in effect: a reload, or `config.load`.
    /// Not called for ``save(_:)``. The Settings window follows it.
    @ObservationIgnored var onExternalLoad: (@MainActor () -> Void)?

    #if DEBUG
    /// How many times each binding's hotkey fired (was pressed) since launch. The debug channel uses
    /// it to tell that a simulated key press reached the hotkey registry.
    @ObservationIgnored private(set) var pressCounts: [UUID: Int] = [:]
    /// How many times each binding's key was released since launch, and how many times the temporary
    /// Escape hotkey fired.
    @ObservationIgnored private(set) var releaseCounts: [UUID: Int] = [:]
    @ObservationIgnored private(set) var escapeCount = 0
    #endif

    @ObservationIgnored private let logger = Logger(subsystem: "io.damao.piccolo", category: "config")
    @ObservationIgnored private let actionQueue = DispatchQueue(
        label: "io.damao.piccolo.actions", qos: .userInitiated)
    @ObservationIgnored private(set) lazy var preview = DestinationPreview(
        presenter: HighlightPanels(), queue: actionQueue
    ) { action, settings in
        try ActionExecutor.live.destinations(for: action, settings: settings)
    }
    @ObservationIgnored private lazy var manager: ShortcutManager = {
        let manager = ShortcutManager(
            registrar: HotkeyRegistrar(backend: CarbonHotkeyBackend()),
            initialURL: ConfigLocation.defaultURL
        ) { [weak self] action, bindingID in
            self?.run(action, bindingID: bindingID)
        }
        manager.onPreview = { [weak self] change in
            self?.previewChanged(change)
        }
        #if DEBUG
        manager.onHotkeyEvent = { [weak self] event in
            self?.observe(event)
        }
        #endif
        return manager
    }()

    private init() {
        status = ShortcutManager.Status(path: ConfigLocation.defaultURL.path)
    }

    /// Loads the config at the default location. Call once at launch: when there is no file there,
    /// the default shortcuts are written first (see `ShortcutManager.loadAtLaunch(from:)`).
    func start() {
        let wroteDefaults = manager.loadAtLaunch(from: ConfigLocation.defaultURL)
        status = manager.status
        log(wroteDefaults ? "wrote the default shortcuts and loaded" : "loaded")
        onExternalLoad?()
    }

    /// Loads the config at the default location again, replacing everything loaded before.
    func reload() {
        apply(ConfigLocation.defaultURL)
    }

    /// Loads another file instead of the default one, until the next ``reload()`` or a quit.
    /// For the debug channel; nothing is written anywhere.
    func load(from url: URL) {
        apply(url)
    }

    /// The config the last load read.
    var config: Config {
        manager.config
    }

    /// Writes `config` to the file in use (the default location, or the file given to
    /// ``load(from:)``), creating its folder on the first save, and applies it: the shortcuts
    /// take effect at once.
    func save(_ config: Config) throws {
        status = try manager.save(config)
        log("saved")
    }

    /// Replaces the bindings in use with `bindings`, keeping the other settings, after copying the file
    /// in use next to itself, and applies the result (see `ShortcutManager.replaceKeepingCopy(with:)`).
    func replaceKeepingCopy(with bindings: [KeyBinding]) throws -> ShortcutManager.Replacement {
        let replacement = try manager.replaceKeepingCopy(with: bindings)
        status = replacement.status
        log("replaced")
        return replacement
    }

    /// Releases every global hotkey (`true`) or registers them again (`false`), for the time a
    /// shortcut is being recorded.
    func setShortcutsSuspended(_ suspended: Bool) {
        status = manager.setSuspended(suspended)
        logger.info(
            "shortcuts \(suspended ? "suspended" : "restored", privacy: .public): \(self.status.summary, privacy: .public)"
        )
    }

    /// Shows the config file in Finder. A missing file is not created: Finder opens the
    /// closest folder that exists instead.
    func revealInFinder() {
        let url = ConfigLocation.defaultURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        var folder = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.path), folder.path != "/" {
            folder = folder.deletingLastPathComponent()
        }
        NSWorkspace.shared.open(folder)
    }

    private func apply(_ url: URL) {
        status = manager.load(from: url)
        log("loaded")
        onExternalLoad?()
    }

    private func log(_ what: String) {
        logger.info(
            "\(what, privacy: .public) \(URL(fileURLWithPath: self.status.path).lastPathComponent, privacy: .public): \(self.status.summary, privacy: .public)"
        )
        for issue in status.issues {
            logger.error("config problem: \(issue, privacy: .public)")
        }
    }

    private func previewChanged(_ change: ShortcutManager.Preview) {
        switch change {
        case .show(let action, let bindingID):
            preview.show(action, settings: ActionSettings(config), bindingID: bindingID)
        case .hide:
            preview.hide()
        }
    }

    #if DEBUG
    private func observe(_ event: ShortcutManager.HotkeyEvent) {
        switch event {
        case .pressed(let bindingID): pressCounts[bindingID, default: 0] += 1
        case .released(let bindingID): releaseCounts[bindingID, default: 0] += 1
        case .escape: escapeCount += 1
        }
    }

    /// The binding whose shortcut is down, and its shortcut.
    var held: (id: UUID, shortcut: Shortcut)? {
        guard let id = manager.heldBindingID,
            let shortcut = status.registered.first(where: { $0.id == id })?.shortcut
        else { return nil }
        return (id, shortcut)
    }

    /// What became of the last hold: see `HoldRules.Outcome`.
    var lastHold: HoldRules.Outcome? {
        manager.lastHold
    }

    /// Whether the temporary Escape hotkey is registered.
    var escapeIsRegistered: Bool {
        manager.escapeIsRegistered
    }
    #endif

    /// Runs the action of a binding on the action queue. With the preview on this is the release of
    /// the shortcut, otherwise the press.
    private func run(_ action: Action, bindingID: UUID) {
        let executor = ActionExecutor.live
        let settings = ActionSettings(config)
        let logger = logger
        actionQueue.async {
            var notice: FailureNotice?
            do {
                let outcome = try executor.run(action, settings: settings)
                logger.debug(
                    "binding \(bindingID.uuidString, privacy: .public): \(String(describing: outcome), privacy: .public)"
                )
                notice = FailureNotice(outcome: outcome, for: action)
            } catch {
                logger.error(
                    "binding \(bindingID.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                notice = FailureNotice(error: error)
            }
            if let notice {
                Self.showNotice(notice)
            }
        }
    }

    /// Shows a failure notice on the display of the focused window (read here, on the action queue,
    /// where an Accessibility call may take its time), or of the mouse when there is none.
    private nonisolated static func showNotice(_ notice: FailureNotice) {
        let windowFrame = try? FocusedWindow.current().frame()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NoticeController.shared.show(notice, windowFrame: windowFrame)
            }
        }
    }
}
