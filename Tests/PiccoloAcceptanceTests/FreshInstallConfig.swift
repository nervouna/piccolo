import Foundation
import PiccoloCore
import PiccoloSystem

/// The settings the frame tests are written for: no window gap, rows-first grids and the Fast
/// animation. A new install starts with other settings (a 16 pt gap, columns-first grids and the Medium
/// animation, see `Config.defaultShortcuts`), and the expected frames of the tests are computed from the
/// visible frame without a gap and with rows first, so every config an acceptance test writes states
/// these settings instead of reading the defaults. The resize step and the destination preview are the
/// defaults.
enum FrameTestSettings {
    static let animation = WindowAnimation.fast
    static let gridFillOrder = GridFillOrder.rows
    static let gap = 0
}

extension Config {
    /// A config with the settings of ``FrameTestSettings`` unless the caller says otherwise, and these
    /// `bindings`. What `Config(...)` gives is the default of a new install, which the frame tests are
    /// not written for.
    static func frameTest(
        resizeStep: Double = Config.defaultResizeStep, animation: WindowAnimation = FrameTestSettings.animation,
        gridFillOrder: GridFillOrder = FrameTestSettings.gridFillOrder,
        destinationPreview: Bool = Config.defaultDestinationPreview, gap: Int = FrameTestSettings.gap,
        bindings: [KeyBinding] = []
    ) -> Config {
        Config(
            resizeStep: resizeStep, animation: animation, gridFillOrder: gridFillOrder,
            destinationPreview: destinationPreview, gap: gap, bindings: bindings)
    }

    /// The default shortcut of a built-in action.
    ///
    /// - Throws: When the defaults hold no shortcut for `action`.
    static func defaultShortcut(of action: Action) throws -> Shortcut {
        guard let shortcut = defaultShortcuts.bindings.first(where: { $0.action == action })?.shortcut else {
            throw AcceptanceFailure("the default shortcuts hold no shortcut for \(action)", isRetryable: false)
        }
        return shortcut
    }
}

/// The config of a fresh install, as a file in a temporary directory, and the means to hand Piccolo
/// to it.
///
/// `action.run` and the hotkeys read the settings (gap, animation, grid fill order, resize step) of
/// the config in effect, and Settings writes the file that is loaded. At the default location that file
/// is the person's own, so a test that expects the frames of the fresh-install settings must never run
/// on it. Every acceptance test therefore starts on this config instead: the 33 bindings of
/// `Config.defaultShortcuts` with the settings the frame tests are written for (gap 0, rows-first grids
/// and the Fast animation, see ``FrameTestSettings``; the resize step and the destination preview are
/// the defaults), written to a temporary directory and loaded with `config.load`.
/// ``PiccoloRunningTrait`` does that before each test and puts Piccolo back on the default location
/// afterwards, and `withConfigDirectory` hands Piccolo back to it when a test is done with a config of
/// its own (see ``current``).
///
/// The file is never at the default location, so nothing here, and no Settings edit made while it is
/// loaded, can change the person's config.
struct FreshInstallConfig: Sendable {
    /// The fresh-install config of the test that is running, set around each test by
    /// ``PiccoloRunningTrait``. It is nil outside a test.
    @TaskLocal static var current: FreshInstallConfig?

    /// The temporary directory that holds the file.
    let directory: URL
    /// What the file holds. Kept so that every load writes the same config again, with the same
    /// binding IDs, whatever an earlier edit of the file in Settings left in it.
    let config: Config

    /// The config file.
    var file: URL { directory.appending(path: "config.json") }

    /// Makes the temporary directory. Nothing is loaded yet.
    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "piccolo-fresh-install-config-\(UUID().uuidString)")
        config = Config.frameTest(bindings: Config.defaultShortcuts.bindings)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The fresh-install config of the running test.
    ///
    /// - Throws: When called outside a test of the root suite, which carries ``PiccoloRunningTrait``.
    static func requireCurrent() throws -> FreshInstallConfig {
        guard let current else {
            throw AcceptanceFailure(
                "no fresh-install config is in scope: this code runs outside a test of the Desktop acceptance suite (.piccoloRunning sets it up)",
                isRetryable: false)
        }
        return current
    }

    /// Writes the fresh-install config to its file and loads it into Piccolo, which replaces
    /// whatever was loaded before and cancels whatever was held.
    ///
    /// - Returns: What `config.load` answered.
    /// - Throws: When Piccolo reports another path or does not count the bindings of a fresh install.
    @discardableResult
    func load(into piccolo: PiccoloClient = PiccoloClient()) throws -> PiccoloClient.ConfigStatus {
        try ConfigStore(url: file).save(config)
        let status = try piccolo.loadConfig(at: file)
        guard status.path == file.path else {
            throw AcceptanceFailure(
                "after config.load of the fresh-install config Piccolo reports the config path \(status.path), expected \(file.path)"
            )
        }
        guard status.bindingCount == config.bindings.count else {
            throw AcceptanceFailure(
                "Piccolo loaded \(status.bindingCount) bindings from the fresh-install config, expected \(config.bindings.count); issues: \(status.issues)"
            )
        }
        return status
    }

    /// Removes the temporary directory.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
