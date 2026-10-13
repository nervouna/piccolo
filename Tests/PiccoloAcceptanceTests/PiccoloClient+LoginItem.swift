import Foundation
import PiccoloControl
import PiccoloCore

/// The login item commands of the Debug control channel.
extension PiccoloClient {
    /// `loginItem.status`: what the system says about starting Piccolo at login.
    func loginItemStatus() throws -> LoginItemStatus {
        try decodeLoginItemStatus(try send("loginItem.status"), of: "loginItem.status")
    }

    /// `loginItem.set`: registers (`true`) or unregisters (`false`) Piccolo as a login item, as the
    /// switch in Settings does, and answers the status afterwards. Registering shows a system
    /// notification on this machine: only a test that puts the login item back calls it.
    @discardableResult
    func loginItemSet(_ enabled: Bool) throws -> LoginItemStatus {
        try decodeLoginItemStatus(
            try send("loginItem.set", ["enabled": .bool(enabled)]), of: "loginItem.set")
    }

    /// The status of the name `settings.state` and the login item commands use, which must be
    /// one of the four the system can report.
    func decodeLoginItemStatus(_ result: JSONValue, of command: String) throws -> LoginItemStatus {
        guard let name = result["status"]?.stringValue else {
            throw AcceptanceFailure("Piccolo's \(command) answer has no status: \(result)")
        }
        return try loginItemStatus(named: name, of: command)
    }

    func loginItemStatus(named name: String, of command: String) throws -> LoginItemStatus {
        guard let status = LoginItemStatus(rawValue: name) else {
            let known = LoginItemStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw AcceptanceFailure("Piccolo's \(command) answered the status \"\(name)\", which is none of \(known)")
        }
        return status
    }
}
