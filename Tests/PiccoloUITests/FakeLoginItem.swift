import PiccoloCore

@testable import PiccoloUI

/// A login item that lives in memory and records what the model asks of it.
@MainActor
final class FakeLoginItem: LoginItemBackend {
    var status: LoginItemStatus
    /// When set, `setEnabled` throws this and changes nothing.
    var failure: LoginItemError?
    /// What the status becomes when a registration succeeds: `.enabled`, or `.requiresApproval`
    /// when the system wants the user's consent first.
    var statusAfterRegistering: LoginItemStatus = .enabled
    /// A status the system ends up in although the request failed, for example an item that was
    /// registered after all. `nil` leaves the status as it was.
    var statusAfterFailure: LoginItemStatus?

    /// Every request to register (`true`) or unregister (`false`), in order, failed ones included.
    private(set) var requests: [Bool] = []
    /// How many times Login Items in System Settings was opened.
    private(set) var settingsOpened = 0

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        requests.append(enabled)
        if let failure {
            if let statusAfterFailure {
                status = statusAfterFailure
            }
            throw failure
        }
        status = enabled ? statusAfterRegistering : .notRegistered
    }

    func openSystemSettings() {
        settingsOpened += 1
    }
}
