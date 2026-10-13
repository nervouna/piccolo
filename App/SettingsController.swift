import AppKit
import PiccoloCore
import PiccoloSystem
import PiccoloUI

/// The Settings window of the running app: one model over the config in use, one window.
///
/// The window is an `NSWindow` hosting the SwiftUI view (`SettingsWindowController` in
/// `PiccoloUI`), not a SwiftUI `Settings` scene. A menu bar app has no menu item that SwiftUI
/// wires to a `Settings` scene, and opening one from code (the menu's "Settings…", a second launch
/// of the app, the debug control channel) is awkward and not reliable on macOS 14 and later. With
/// an `NSWindow` showing, closing, key status and the keyboard are all under our control.
@MainActor
final class SettingsController {
    static let shared = SettingsController()

    let model: SettingsModel
    private let windowController: SettingsWindowController

    private init() {
        let model = SettingsModel(
            backend: ConfigSettingsBackend(controller: .shared), loginItem: SystemLoginItemBackend())
        self.model = model
        windowController = SettingsWindowController(
            model: model,
            host: SettingsHost(
                isAccessibilityTrusted: { AccessibilityStatus.shared.isTrusted },
                openAccessibilitySettings: { AccessibilityPermission().openSettings() },
                revealConfigInFinder: { ConfigController.shared.revealInFinder() },
                appVersion: Self.appVersion))
    }

    /// Whether the window is on screen (or minimized).
    var isOpen: Bool {
        windowController.isOpen
    }

    /// Whether the window is the key window of the active app, which is where key presses go.
    var isKey: Bool {
        windowController.isKey
    }

    /// Opens the window, or brings it to the front.
    func show() {
        windowController.show()
    }

    /// Closes the window. A recording in progress ends and the hotkeys come back.
    func close() {
        windowController.close()
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }
}

/// The Settings model's view of the app: the config file in use and the global hotkeys.
@MainActor
final class ConfigSettingsBackend: SettingsBackend {
    private let controller: ConfigController

    init(controller: ConfigController) {
        self.controller = controller
    }

    var onExternalChange: (@MainActor () -> Void)? {
        get { controller.onExternalLoad }
        set { controller.onExternalLoad = newValue }
    }

    func current() -> SettingsSnapshot {
        SettingsSnapshot(config: controller.config, issues: controller.status.issues)
    }

    func save(_ config: Config) throws -> [String] {
        do {
            try controller.save(config)
        } catch ConfigStoreError.newerFileVersion(let version) {
            throw SettingsSaveError(
                "the config file has format version \(version), which this version of Piccolo cannot "
                    + "write; the file was left untouched")
        } catch ConfigStoreError.invalid(let error) {
            throw SettingsSaveError("\(error)")
        } catch {
            throw SettingsSaveError(error.localizedDescription)
        }
        return controller.status.issues
    }

    func setShortcutsSuspended(_ suspended: Bool) {
        controller.setShortcutsSuspended(suspended)
    }
}

/// The Settings model's view of the login item: Piccolo's `SMAppService.mainApp`.
@MainActor
final class SystemLoginItemBackend: LoginItemBackend {
    private let loginItem = LoginItem()

    var status: LoginItemStatus {
        loginItem.status
    }

    func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        try loginItem.setEnabled(enabled)
    }

    func openSystemSettings() {
        loginItem.openSystemSettings()
    }
}
