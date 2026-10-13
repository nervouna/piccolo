import Foundation
import PiccoloControl
import PiccoloCore
import Testing

/// Acceptance tests for launching Piccolo at login: the installed Debug Piccolo reports what
/// `SMAppService.mainApp` says, and (only when asked to) registers and unregisters itself.
///
/// `SMAppService.mainApp` stands for the running app bundle, so everything goes through the
/// control channel; neither the test process nor a command line tool can ask it. No window is
/// involved: the commands drive the same model methods as the switch in the General tab.
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends.
extension DesktopAcceptanceTests {
    @Suite("Launch at login")
    struct LaunchAtLogin {
        private let piccolo = PiccoloClient()

        @Test("loginItem 1. loginItem.status answers one of the four states, and settings.state.loginItem agrees")
        func loginItemStatusIsReported() throws {
            // The client rejects a name that is none of the four.
            let status = try piccolo.loginItemStatus()
            print("loginItem: the system reports \(status.rawValue)")

            let state = try piccolo.settingsState()
            #expect(
                state.loginItem == status.rawValue,
                "settings.state reports the login item as \"\(state.loginItem)\", loginItem.status as \"\(status.rawValue)\"")
            // Asking again changes nothing: the commands only read.
            #expect(try piccolo.loginItemStatus() == status)
        }

        @Test(
            "loginItem 2. enabling registers (enabled or requires approval), disabling unregisters, and the status is put back",
            .enabled(
                if: Acceptance.isLoginItemEnabled,
                "set \(Acceptance.loginItemEnvironmentVariable)=1: it registers Piccolo as a login item on this machine, which shows a system notification")
        )
        func loginItemCanBeEnabledAndDisabled() async throws {
            try await withLoginItemRestored { _ in
                let enabled = try piccolo.loginItemSet(true)
                print("loginItem: after enabling the system reports \(enabled.rawValue)")
                #expect(
                    enabled == .enabled || enabled == .requiresApproval,
                    "after enabling, the status is \(enabled.rawValue), expected enabled or requiresApproval")
                try expectStatus(enabled, after: "enabling")

                let disabled = try piccolo.loginItemSet(false)
                #expect(
                    disabled == .notRegistered,
                    "after disabling, the status is \(disabled.rawValue), expected notRegistered")
                try expectStatus(disabled, after: "disabling")
            }
        }

        // MARK: Support

        /// The status must be what a fresh `loginItem.status` and `settings.state` report.
        private func expectStatus(_ expected: LoginItemStatus, after what: String) throws {
            let status = try piccolo.loginItemStatus()
            #expect(
                status == expected,
                "after \(what), loginItem.status answers \(status.rawValue), loginItem.set answered \(expected.rawValue)")
            let state = try piccolo.settingsState()
            #expect(
                state.loginItem == expected.rawValue,
                "after \(what), settings.state reports the login item as \"\(state.loginItem)\", expected \"\(expected.rawValue)\"")
        }

        /// Remembers the login item's status, runs `body`, and puts the status back, also when
        /// `body` fails. A failure to put it back is its own failure: after a failed `body` it is
        /// recorded as a second issue of the test, next to the error that is thrown.
        private func withLoginItemRestored<Result>(
            _ body: (LoginItemStatus) async throws -> Result
        ) async throws -> Result {
            let original = try piccolo.loginItemStatus()
            print("loginItem: the status before the test is \(original.rawValue)")
            let result: Result
            do {
                result = try await body(original)
            } catch {
                do {
                    try restore(original)
                } catch {
                    Issue.record("putting the login item back to \(original.rawValue) after the failed test failed as well: \(error)")
                }
                throw error
            }
            try restore(original)
            return result
        }

        /// Registers or unregisters until the status is `original` again. Asking for a state that
        /// is already in force does nothing, so this changes the login item only when it differs.
        ///
        /// An app the system has never heard of reports `notFound`, and one that was registered
        /// and unregistered again may report `notRegistered`: no API takes it back to `notFound`.
        /// Neither is a login item, so they count as the same state here.
        private func restore(_ original: LoginItemStatus) throws {
            guard try !isSameState(piccolo.loginItemStatus(), original) else { return }
            let restored = try piccolo.loginItemSet(original.isRegistered)
            guard isSameState(restored, original) else {
                throw AcceptanceFailure(
                    "the login item was \(original.rawValue) before the test; after asking for \(original.isRegistered ? "registered" : "unregistered") it is \(restored.rawValue). Check Login Items in System Settings.",
                    isRetryable: false)
            }
            print("loginItem: put the status back to \(original.rawValue) (it reports \(restored.rawValue))")
        }

        private func isSameState(_ a: LoginItemStatus, _ b: LoginItemStatus) -> Bool {
            a == b || (!a.isRegistered && !b.isRegistered)
        }
    }
}
