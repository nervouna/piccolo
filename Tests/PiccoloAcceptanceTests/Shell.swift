import CoreGraphics
import Foundation

/// Runs the few system tools the acceptance support needs.
enum Shell {
    struct Result {
        var status: Int32
        var output: String
        var errors: String
    }

    /// Runs an executable to completion. Output is captured; the tools used here print
    /// a few lines at most.
    static func run(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AcceptanceFailure("could not run \(executable): \(error.localizedDescription)")
        }
        // Read before waiting: a full pipe would block the tool forever.
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self),
            errors: String(decoding: errorData, as: UTF8.self))
    }

    /// `open <arguments>`: hands the request to LaunchServices, which is also what makes
    /// the system allow the launched or activated app to come to the front.
    static func open(_ arguments: [String]) throws {
        let result = try run("/usr/bin/open", arguments)
        guard result.status == 0 else {
            throw AcceptanceFailure(
                "open \(arguments.joined(separator: " ")) failed with status \(result.status): "
                    + result.errors.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// The application that currently receives keyboard input, as LaunchServices reports it.
///
/// `NSWorkspace.frontmostApplication` is not usable here: in a process that does not run
/// an app's event loop it keeps returning the value from when it was first read. Asking
/// `lsappinfo` is a fresh query every time and needs no permission.
enum Frontmost {
    static func bundleID() -> String? {
        guard let front = try? Shell.run("/usr/bin/lsappinfo", ["front"]), front.status == 0 else {
            return nil
        }
        let asn = front.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asn.isEmpty,
            let info = try? Shell.run("/usr/bin/lsappinfo", ["info", "-only", "bundleid", asn]),
            info.status == 0
        else { return nil }
        // The report reads `bundleID="com.example.app"` on one line.
        for line in info.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("bundleID=") else { continue }
            let value = trimmed.dropFirst("bundleID=".count).trimmingCharacters(
                in: CharacterSet(charactersIn: "\""))
            return value.isEmpty || value == "[ NULL ]" ? nil : value
        }
        return nil
    }

    static let loginWindow = "com.apple.loginwindow"

    /// Whether the screen is locked, from the session dictionary (`CGSSessionScreenIsLocked`, which
    /// is there only while it is). Reading it needs no permission.
    static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
            let value = session["CGSSessionScreenIsLocked"]
        else { return false }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    /// `loginwindow` is what LaunchServices reports both behind the lock screen and when no
    /// application is frontmost, so the lock is looked at first.
    static func state() -> FrontState {
        if isScreenLocked() { return .locked }
        guard let id = bundleID(), id != loginWindow else { return .noApplication }
        return .application(id)
    }

    /// Why `wanted` is not frontmost, for a failure message.
    static func explain(_ state: FrontState, wanted: String) -> String {
        switch state {
        case .locked:
            return "the screen is locked (CGSSessionScreenIsLocked): no application can be brought to the front "
                + "until the owner unlocks it"
        case .noApplication:
            return "no application is frontmost: LaunchServices reports \(loginWindow) while the screen is not locked "
                + "(after an open of a Piccolo that was already gone failed with -600, the window server can be left "
                + "waiting for that instance, and no other application can be activated until a live one is)"
        case .application(let id):
            return "frontmost app is \(id), wanted \(wanted)"
        }
    }

    /// Clears "no application is frontmost" by activating Finder, a live process, through
    /// LaunchServices. Activating Piccolo would clear it too, but a Piccolo that has been active no
    /// longer fires simulated hotkeys (see ``PiccoloProcess``).
    static func clearNoApplication() throws {
        print("Frontmost: no application was frontmost; handed the front to Finder through LaunchServices")
        try Shell.open(["-b", "com.apple.finder"])
    }
}

/// Who has the front of the desktop, in the three states that need telling apart.
enum FrontState: Equatable {
    /// The screen is locked (`CGSSessionScreenIsLocked`). Nothing here can unlock it.
    case locked
    /// No application is frontmost: LaunchServices reports `com.apple.loginwindow`, or nothing,
    /// while the screen is not locked.
    case noApplication
    /// This application is frontmost (its bundle ID).
    case application(String)
}

/// What LaunchServices says about running apps, as `lsappinfo` reports it.
enum LaunchServicesRegistry {
    /// The application serial numbers LaunchServices lists as running for `bundleID`. Empty when it
    /// lists none, and when `lsappinfo` does not answer.
    static func instances(of bundleID: String) -> [String] {
        guard let result = try? Shell.run("/usr/bin/lsappinfo", ["find", "bundleid=\(bundleID)"]),
            result.status == 0
        else { return [] }
        return result.output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("ASN:") }
    }
}
