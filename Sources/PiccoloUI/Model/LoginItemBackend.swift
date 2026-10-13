import PiccoloCore

/// What ``SettingsModel`` needs from the system to start Piccolo at login. The app plugs in
/// `LoginItem` (over `SMAppService.mainApp`); tests use a fake.
@MainActor
public protocol LoginItemBackend: AnyObject {
    /// What the system says now.
    var status: LoginItemStatus { get }

    /// Registers (`true`) or unregisters (`false`) Piccolo as a login item. Asking for the state
    /// that is already in force does nothing. Registering can end in
    /// ``LoginItemStatus/requiresApproval``: the status says so afterwards.
    ///
    /// - Throws: ``LoginItemError`` with the system's message when the system refuses.
    func setEnabled(_ enabled: Bool) throws(LoginItemError)

    /// Opens Login Items in System Settings, where the user allows an item that requires approval.
    func openSystemSettings()
}
