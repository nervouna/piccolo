import Foundation
import PiccoloCore
import ServiceManagement

/// What ``LoginItem`` asks of `SMAppService`, so that its logic runs against a fake in tests.
/// `SMAppService` itself conforms.
protocol MainAppService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: MainAppService {}

/// Whether the app starts at login: the main app's `SMAppService`.
///
/// `SMAppService.mainApp` stands for the bundle of the running process, so this works only inside
/// the app, not from a command line tool or a test process. Registering shows a system
/// notification, and the user can switch the item off in System Settings at any time.
public struct LoginItem {
    private let service: any MainAppService

    /// The running app.
    public init() {
        self.init(service: SMAppService.mainApp)
    }

    init(service: any MainAppService) {
        self.service = service
    }

    /// What the system says now.
    public var status: LoginItemStatus {
        Self.status(from: service.status)
    }

    /// Registers (`true`) or unregisters (`false`) the app as a login item.
    ///
    /// Asking for the state that is already in force does nothing: an app that is registered
    /// (also one that waits for the user's approval) is not registered again, and one that is not
    /// registered is not unregistered, both of which the system reports as errors.
    ///
    /// - Throws: ``LoginItemError`` with the system's message.
    public func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        guard status.isRegistered != enabled else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            throw LoginItemError(message: error.localizedDescription)
        }
    }

    /// Opens Login Items in System Settings.
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func status(from status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled: .enabled
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }
}
