import Foundation
import PiccoloControl

/// What the arrange tests need beyond the basic fixture commands: minimizing, and the fixture's pid.
extension FixtureApp {
    /// The process ID of the one running fixture. Tests pass it as `onlyPid`, so they fail rather
    /// than guess when there is none or more than one.
    func processID() throws -> pid_t {
        let pids = processIDs()
        guard pids.count == 1, let pid = pids.first else {
            throw AcceptanceFailure("expected exactly one \(Self.processName) process, found \(pids)")
        }
        return pid
    }

    /// Minimizes the window into the Dock. The fixture answers after the window server stopped
    /// listing it as on screen.
    func miniaturize(id: String) throws {
        _ = try send("miniaturize", ["id": .string(id)])
    }

    /// Brings a minimized window back from the Dock.
    func deminiaturize(id: String) throws {
        _ = try send("deminiaturize", ["id": .string(id)])
    }

    /// Whether the fixture reports the window as minimized (`list` has the flag).
    func isMiniaturized(id: String) throws -> Bool {
        guard let entries = try send("list").arrayValue,
            let entry = entries.first(where: { $0["id"]?.stringValue == id })
        else {
            throw AcceptanceFailure("the fixture has no window '\(id)'")
        }
        guard let flag = entry["isMiniaturized"]?.boolValue else {
            throw AcceptanceFailure("the fixture's list has no isMiniaturized flag for '\(id)': \(entry)")
        }
        return flag
    }
}
