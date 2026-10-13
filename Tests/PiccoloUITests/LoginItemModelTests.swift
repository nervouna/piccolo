import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

@MainActor
@Suite("Settings model: launch at login")
struct LoginItemModelTests {
    private func make(
        _ status: LoginItemStatus = .notRegistered
    ) -> (model: SettingsModel, loginItem: FakeLoginItem, backend: InMemorySettingsBackend) {
        let backend = InMemorySettingsBackend(config: UIFixture.twoBindings())
        let loginItem = FakeLoginItem(status: status)
        let model = SettingsModel(backend: backend, loginItem: loginItem) { _ in nil }
        return (model, loginItem, backend)
    }

    // MARK: Every status

    @Test(
        "the model starts with the status the system reports, and the switch is on for the registered ones",
        arguments: [
            (LoginItemStatus.enabled, true),
            (.notRegistered, false),
            (.requiresApproval, true),
            (.notFound, false),
        ])
    func initialStatus(status: LoginItemStatus, isOn: Bool) {
        let (model, loginItem, _) = make(status)

        #expect(model.loginItemStatus == status)
        #expect(model.launchesAtLogin == isOn)
        #expect(model.loginItemError == nil)
        // Looking at the status asks for nothing.
        #expect(loginItem.requests.isEmpty)
    }

    @Test("the test covers every status the system can report")
    func everyStatusIsCovered() {
        #expect(Set(LoginItemStatus.allCases) == [.enabled, .notRegistered, .requiresApproval, .notFound])
        #expect(
            LoginItemStatus.allCases.map(\.rawValue).sorted()
                == ["enabled", "notFound", "notRegistered", "requiresApproval"])
    }

    @Test(
        "refresh reads the status the system reports now, for every status",
        arguments: LoginItemStatus.allCases)
    func refreshReadsTheSystem(status: LoginItemStatus) {
        let (model, loginItem, _) = make(.notRegistered)

        // The user switched Piccolo on or off in System Settings behind the model's back.
        loginItem.status = status
        #expect(model.loginItemStatus == .notRegistered, "the model changed before it was asked to look")
        model.refreshLoginItem()

        #expect(model.loginItemStatus == status)
        #expect(model.launchesAtLogin == status.isRegistered)
        #expect(loginItem.requests.isEmpty)
    }

    // MARK: Successful changes

    @Test("turning it on registers and the status becomes enabled")
    func turnOn() {
        let (model, loginItem, backend) = make(.notRegistered)

        #expect(model.setLaunchAtLogin(true))

        #expect(loginItem.requests == [true])
        #expect(model.loginItemStatus == .enabled)
        #expect(model.launchesAtLogin)
        #expect(model.loginItemError == nil)
        // It is no change of the config.
        #expect(backend.saved.isEmpty)
        #expect(model.error == nil)
    }

    @Test("turning it on can end in requires approval, which still shows the switch on")
    func turnOnNeedsApproval() {
        let (model, loginItem, _) = make(.notRegistered)
        loginItem.statusAfterRegistering = .requiresApproval

        #expect(model.setLaunchAtLogin(true))

        #expect(model.loginItemStatus == .requiresApproval)
        #expect(model.launchesAtLogin)
        #expect(model.loginItemError == nil)
    }

    @Test("turning it off unregisters and the status becomes not registered", arguments: [
        LoginItemStatus.enabled, .requiresApproval,
    ])
    func turnOff(from status: LoginItemStatus) {
        let (model, loginItem, _) = make(status)

        #expect(model.setLaunchAtLogin(false))

        #expect(loginItem.requests == [false])
        #expect(model.loginItemStatus == .notRegistered)
        #expect(!model.launchesAtLogin)
        #expect(model.loginItemError == nil)
    }

    @Test("a change is followed by a read of the status the system reports, not by a guess")
    func statusAfterChangeIsRead() {
        let (model, loginItem, _) = make(.notRegistered)
        // The system registered the item, and the user's earlier choice in System Settings means
        // it is not allowed to run.
        loginItem.statusAfterRegistering = .requiresApproval
        model.setLaunchAtLogin(true)
        #expect(model.loginItemStatus == .requiresApproval)

        // The user then allows it in System Settings; the next change sees that.
        loginItem.status = .enabled
        model.setLaunchAtLogin(false)
        #expect(model.loginItemStatus == .notRegistered)
    }

    // MARK: Failed changes

    @Test("a refused registration leaves the switch off and shows the system's message")
    func turnOnFails() {
        let (model, loginItem, backend) = make(.notRegistered)
        loginItem.failure = LoginItemError(message: "Operation not permitted")

        let accepted = model.setLaunchAtLogin(true)

        #expect(!accepted)
        #expect(loginItem.requests == [true])
        #expect(model.loginItemStatus == .notRegistered)
        #expect(!model.launchesAtLogin)
        let message = model.loginItemError
        #expect(message == "Launch at login could not be turned on: Operation not permitted")
        #expect(backend.saved.isEmpty)
        // The message belongs next to the switch, not to the config's editor.
        #expect(model.error == nil)
    }

    @Test("a refused unregistration leaves the switch on and shows the system's message")
    func turnOffFails() {
        let (model, loginItem, _) = make(.enabled)
        loginItem.failure = LoginItemError(message: "Job not found")

        let accepted = model.setLaunchAtLogin(false)

        #expect(!accepted)
        #expect(loginItem.requests == [false])
        #expect(model.loginItemStatus == .enabled)
        #expect(model.launchesAtLogin)
        #expect(model.loginItemError == "Launch at login could not be turned off: Job not found")
    }

    @Test("after a failure the status is the one the system reports, even when it changed anyway")
    func failureReadsStatus() {
        let (model, loginItem, _) = make(.notRegistered)
        loginItem.failure = LoginItemError(message: "The operation couldn't be completed")
        loginItem.statusAfterFailure = .requiresApproval

        #expect(!model.setLaunchAtLogin(true))

        #expect(model.loginItemStatus == .requiresApproval)
        #expect(model.loginItemError != nil)
    }

    @Test("a later success clears the message of the failure")
    func successClearsTheError() {
        let (model, loginItem, _) = make(.notRegistered)
        loginItem.failure = LoginItemError(message: "No")
        model.setLaunchAtLogin(true)
        #expect(model.loginItemError != nil)

        loginItem.failure = nil
        #expect(model.setLaunchAtLogin(true))

        #expect(model.loginItemError == nil)
        #expect(model.loginItemStatus == .enabled)
    }

    @Test("a refresh keeps the message of a failure; clearing the errors removes it")
    func refreshKeepsClearForgets() {
        let (model, loginItem, _) = make(.notRegistered)
        loginItem.failure = LoginItemError(message: "No")
        model.setLaunchAtLogin(true)
        let message = model.loginItemError

        model.refreshLoginItem()
        #expect(model.loginItemError == message)

        model.clearError()
        #expect(model.loginItemError == nil)
    }

    @Test("a failure that carries no message still gets a sentence, without a dangling colon")
    func failureWithEmptyMessage() {
        let (model, loginItem, _) = make(.notRegistered)
        loginItem.failure = LoginItemError(message: "")

        model.setLaunchAtLogin(true)

        #expect(model.loginItemError == "Launch at login could not be turned on.")
    }

    // MARK: System Settings

    @Test("opening Login Items asks the system to open System Settings, and nothing else")
    func openLoginItemsSettings() {
        let (model, loginItem, backend) = make(.requiresApproval)

        model.openLoginItemsSettings()

        #expect(loginItem.settingsOpened == 1)
        #expect(loginItem.requests.isEmpty)
        #expect(backend.saved.isEmpty)
        #expect(model.loginItemStatus == .requiresApproval)
    }

    // MARK: The config is untouched

    @Test("the login item and the config do not disturb each other")
    func independentOfTheConfig() {
        let (model, loginItem, backend) = make(.notRegistered)
        loginItem.failure = LoginItemError(message: "No")
        model.setLaunchAtLogin(true)

        // A rejected config change does not touch the login item's message...
        model.setShortcut(UIFixture.idB, to: UIFixture.f13)
        #expect(model.error != nil)
        #expect(model.loginItemError != nil)

        // ...and an accepted one does not clear it either: it belongs to the switch.
        #expect(model.setResizeStep(0.07))
        #expect(model.error == nil)
        #expect(model.loginItemError != nil)
        #expect(backend.saved.count == 1)
        #expect(loginItem.requests == [true])
    }
}
