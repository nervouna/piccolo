import Foundation
import Testing

@testable import PiccoloCore

@Suite("Login item status")
struct LoginItemStatusTests {
    @Test("the names are the ones the control channel uses")
    func names() {
        #expect(
            LoginItemStatus.allCases.map(\.rawValue)
                == ["enabled", "notRegistered", "requiresApproval", "notFound"])
    }

    @Test("Piccolo counts as registered when enabled and when waiting for approval")
    func isRegistered() {
        #expect(LoginItemStatus.enabled.isRegistered)
        #expect(LoginItemStatus.requiresApproval.isRegistered)
        #expect(!LoginItemStatus.notRegistered.isRegistered)
        #expect(!LoginItemStatus.notFound.isRegistered)
    }

    @Test("a status survives encoding and decoding by name")
    func codable() throws {
        for status in LoginItemStatus.allCases {
            let data = try JSONEncoder().encode([status])
            #expect(String(decoding: data, as: UTF8.self) == "[\"\(status.rawValue)\"]")
            #expect(try JSONDecoder().decode([LoginItemStatus].self, from: data) == [status])
        }
    }

    @Test("a login item error carries the message and describes itself with it")
    func error() {
        let error = LoginItemError(message: "Operation not permitted")
        #expect(error.message == "Operation not permitted")
        #expect(error.errorDescription == "Operation not permitted")
        #expect(error == LoginItemError(message: "Operation not permitted"))
        #expect(error != LoginItemError(message: "Job not found"))
    }
}
