import Foundation
import ServiceManagement
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// `SMAppService.mainApp` stands for the running bundle and registering shows a notification on
/// the owner's machine, so these tests run `LoginItem` over a fake service and never touch the
/// real one.
private final class FakeMainAppService: MainAppService {
    var status: SMAppService.Status
    var registerFailure: (any Error)?
    var unregisterFailure: (any Error)?
    /// What the status becomes after a successful registration.
    var statusAfterRegistering: SMAppService.Status = .enabled
    private(set) var calls: [String] = []

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        calls.append("register")
        if let registerFailure { throw registerFailure }
        status = statusAfterRegistering
    }

    func unregister() throws {
        calls.append("unregister")
        if let unregisterFailure { throw unregisterFailure }
        status = .notRegistered
    }
}

@Suite("Login item")
struct LoginItemTests {
    // MARK: Status

    @Test("every status of SMAppService maps to the one of the same name")
    func statusMapping() {
        #expect(LoginItem.status(from: .enabled) == .enabled)
        #expect(LoginItem.status(from: .notRegistered) == .notRegistered)
        #expect(LoginItem.status(from: .requiresApproval) == .requiresApproval)
        #expect(LoginItem.status(from: .notFound) == .notFound)
    }

    @Test(
        "the login item reports the service's status",
        arguments: [
            (SMAppService.Status.enabled, LoginItemStatus.enabled),
            (.notRegistered, .notRegistered),
            (.requiresApproval, .requiresApproval),
            (.notFound, .notFound),
        ])
    func reportsStatus(system: SMAppService.Status, expected: LoginItemStatus) {
        let item = LoginItem(service: FakeMainAppService(status: system))
        #expect(item.status == expected)
    }

    // MARK: Changing

    @Test("enabling registers a login item that is not registered")
    func enable() throws {
        let service = FakeMainAppService(status: .notRegistered)
        let item = LoginItem(service: service)

        try item.setEnabled(true)

        #expect(service.calls == ["register"])
        #expect(item.status == .enabled)
    }

    @Test("enabling can end in requires approval, which is not an error")
    func enableNeedsApproval() throws {
        let service = FakeMainAppService(status: .notRegistered)
        service.statusAfterRegistering = .requiresApproval
        let item = LoginItem(service: service)

        try item.setEnabled(true)

        #expect(item.status == .requiresApproval)
    }

    @Test("disabling unregisters a login item that is registered, also one that waits for approval", arguments: [
        SMAppService.Status.enabled, .requiresApproval,
    ])
    func disable(from status: SMAppService.Status) throws {
        let service = FakeMainAppService(status: status)
        let item = LoginItem(service: service)

        try item.setEnabled(false)

        #expect(service.calls == ["unregister"])
        #expect(item.status == .notRegistered)
    }

    @Test("asking for the state that is in force does nothing, so the system is never sent an error")
    func idempotent() throws {
        for (status, enabled) in [
            (SMAppService.Status.enabled, true),
            (.requiresApproval, true),
            (.notRegistered, false),
            (.notFound, false),
        ] {
            let service = FakeMainAppService(status: status)
            try LoginItem(service: service).setEnabled(enabled)
            #expect(service.calls.isEmpty, "setEnabled(\(enabled)) with the status \(status) called \(service.calls)")
        }
    }

    @Test("a login item the system cannot find is still registered when asked to")
    func enableWhenNotFound() throws {
        let service = FakeMainAppService(status: .notFound)
        try LoginItem(service: service).setEnabled(true)
        #expect(service.calls == ["register"])
    }

    // MARK: Errors

    @Test("a refused registration throws a LoginItemError with the system's message")
    func registerFails() {
        let service = FakeMainAppService(status: .notRegistered)
        service.registerFailure = NSError(
            domain: "SMAppServiceErrorDomain", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        let item = LoginItem(service: service)

        #expect(throws: LoginItemError(message: "Operation not permitted")) {
            try item.setEnabled(true)
        }
        #expect(item.status == .notRegistered)
    }

    @Test("a refused unregistration throws a LoginItemError with the system's message")
    func unregisterFails() {
        let service = FakeMainAppService(status: .enabled)
        service.unregisterFailure = NSError(
            domain: "SMAppServiceErrorDomain", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Job not found"])
        let item = LoginItem(service: service)

        #expect(throws: LoginItemError(message: "Job not found")) {
            try item.setEnabled(false)
        }
        #expect(item.status == .enabled)
    }

    @Test("a login item error describes itself with the message")
    func errorDescription() {
        let error = LoginItemError(message: "Operation not permitted")
        #expect(error.localizedDescription == "Operation not permitted")
    }
}
