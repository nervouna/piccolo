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
}
