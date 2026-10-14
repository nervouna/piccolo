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
    /// How many times each binding's hotkey fired since launch. The debug channel uses it to
    /// tell that a simulated key press reached the hotkey registry.
    @ObservationIgnored private(set) var pressCounts: [UUID: Int] = [:]
    #endif

    @ObservationIgnored private let logger = Logger(subsystem: "io.damao.piccolo", category: "config")
    @ObservationIgnored private let actionQueue = DispatchQueue(
        label: "io.damao.piccolo.actions", qos: .userInitiated)
    @ObservationIgnored private lazy var manager = ShortcutManager(
        registrar: HotkeyRegistrar(backend: CarbonHotkeyBackend()),
        initialURL: ConfigLocation.defaultURL
    ) { [weak self] action, bindingID in
        self?.pressed(action, bindingID: bindingID)
    }

    private init() {
        status = ShortcutManager.Status(path: ConfigLocation.defaultURL.path)
    }

    /// Loads the config at the default location. Call once at launch.
    func start() {
        reload()
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

    private func pressed(_ action: Action, bindingID: UUID) {
        #if DEBUG
        pressCounts[bindingID, default: 0] += 1
        #endif
        let executor = ActionExecutor.live
        let resizeStep = config.resizeStep
        let logger = logger
        actionQueue.async {
            do {
                let outcome = try executor.run(action, resizeStep: resizeStep)
                logger.debug(
                    "binding \(bindingID.uuidString, privacy: .public): \(String(describing: outcome), privacy: .public)"
                )
            } catch {
                logger.error(
                    "binding \(bindingID.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
