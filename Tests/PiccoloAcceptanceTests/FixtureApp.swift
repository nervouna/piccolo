import CoreGraphics
import Foundation
import PiccoloControl

/// A window the fixture opened, as the fixture reports it.
struct FixtureWindow: Sendable, Equatable {
    var id: String
    var windowNumber: Int
    /// What the fixture says; tests measure independently (see ``Measure``).
    var frame: CGRect
    /// Only filled in by `list`.
    var isKey: Bool = false
}

/// The PiccoloFixture app: launched through LaunchServices, driven over its control
/// channel. Identify it by bundle ID or pid, never by name (names are localized).
struct FixtureApp: Sendable {
    static let bundleID = "io.damao.piccolo.fixture"
    /// The process name, for `pgrep -x`.
    static let processName = "PiccoloFixture"

    private let client = ControlClient(serviceName: ControlServiceName.fixture, timeout: 10)

    // MARK: Lifecycle

    /// Returns a fixture that is running and answering, launching it first when needed.
    /// `scripts/accept.sh` launches it up front; this makes a direct run of the tests work
    /// and replaces a stale process left behind by an interrupted run.
    static func launched() async throws -> FixtureApp {
        let app = FixtureApp()
        if app.isAnswering { return app }

        if !app.processIDs().isEmpty {
            // Running but silent: still starting up, or left over from an earlier run.
            if await app.waitUntil(timeout: 3, { app.isAnswering }) { return app }
            try await app.terminate()
        }

        let url = Acceptance.fixtureAppURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AcceptanceFailure(
                "the fixture app does not exist at \(url.path); build it with scripts/build.sh debug "
                    + "(scripts/accept.sh does that), or point PICCOLO_FIXTURE_APP at it")
        }
        try Shell.open([url.path])
        guard await app.waitUntil(timeout: 30, { app.isAnswering }) else {
            throw AcceptanceFailure(
                "the fixture was launched from \(url.path) but does not answer on "
                    + "\(ControlServiceName.fixture) within 30 s (pids: \(app.processIDs()))")
        }
        return app
    }

    /// Asks the fixture to quit and waits for the process to be gone; ends it with signals
    /// when it does not comply.
    func quit() async throws {
        _ = try? client.send(command: "quit")
        if await waitUntil(timeout: 5, { processIDs().isEmpty }) { return }
        try await terminate()
    }

    /// Ends every fixture process with signals (a hung fixture does not read its queue).
    private func terminate() async throws {
        for signal in [SIGTERM, SIGKILL] {
            for pid in processIDs() { kill(pid, signal) }
            if await waitUntil(timeout: 3, { processIDs().isEmpty }) { return }
        }
        throw AcceptanceFailure("a \(Self.processName) process (pids \(processIDs())) could not be ended")
    }

    /// Polls `condition` every 50 ms; true as soon as it holds, false after `timeout`.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let reached: Bool? = try? await eventually("a condition", timeout: timeout) {
            condition() ? Observation.satisfied(true) : .unsatisfied("not yet")
        }
        return reached == true
    }

    /// The pids of running fixture processes (`pgrep -x`).
    func processIDs() -> [pid_t] {
        guard let result = try? Shell.run("/usr/bin/pgrep", ["-x", Self.processName]),
            result.status == 0
        else { return [] }
        return result.output.split(separator: "\n").compactMap { pid_t($0) }
    }

    /// Whether the fixture answers a request right now. Looks briefly, so that a hung
    /// fixture cannot hold up the caller.
    var isAnswering: Bool {
        let probe = ControlClient(serviceName: ControlServiceName.fixture, timeout: 2)
        return (try? probe.send(command: "list"))?.ok == true
    }

    // MARK: Commands

    /// Sends a command and returns its result; a failure response is an error.
    func send(_ command: String, _ params: [String: JSONValue] = [:]) throws -> JSONValue {
        let response: ControlResponse
        do {
            response = try client.send(command: command, params: params)
        } catch {
            var isRetryable = true
            if case ControlError.noServer = error { isRetryable = false }
            throw AcceptanceFailure(
                "fixture command '\(command)' failed: \(error.localizedDescription)",
                isRetryable: isRetryable)
        }
        guard response.ok else {
            throw AcceptanceFailure(
                "fixture command '\(command)' was refused: \(response.error ?? "no reason given")")
        }
        return response.result ?? .null
    }

    /// Opens a titled window `id` at `frame` (canonical coordinates). The constraints apply
    /// to the window frame, as Accessibility sees it.
    @discardableResult
    func open(
        id: String,
        frame: CGRect,
        minSize: CGSize? = nil,
        maxSize: CGSize? = nil,
        resizeIncrements: CGSize? = nil,
        resizable: Bool? = nil
    ) throws -> FixtureWindow {
        var params: [String: JSONValue] = ["id": .string(id), "frame": JSONValue(rect: frame)]
        if let minSize { params["minSize"] = Self.json(minSize) }
        if let maxSize { params["maxSize"] = Self.json(maxSize) }
        if let resizeIncrements { params["resizeIncrements"] = Self.json(resizeIncrements) }
        if let resizable { params["resizable"] = .bool(resizable) }
        return try Self.window(from: try send("open", params))
    }

    func list() throws -> [FixtureWindow] {
        guard let entries = try send("list").arrayValue else {
            throw AcceptanceFailure("fixture command 'list' did not return an array")
        }
        return try entries.map(Self.window(from:))
    }

    /// Asks the fixture to activate and make the window key. This is a request: the system
    /// may refuse to activate the app. See ``Focus`` for the verified version.
    func requestFocus(id: String) throws {
        _ = try send("focus", ["id": .string(id)])
    }

    func close(id: String) throws {
        _ = try send("close", ["id": .string(id)])
    }

    func closeAll() throws {
        _ = try send("closeAll")
    }

    // MARK: Decoding

    private static func json(_ size: CGSize) -> JSONValue {
        .object(["width": .double(size.width), "height": .double(size.height)])
    }

    private static func window(from value: JSONValue) throws -> FixtureWindow {
        guard let id = value["id"]?.stringValue,
            let number = value["windowNumber"]?.intValue,
            let frame = value["frame"]?.rectValue
        else {
            throw AcceptanceFailure("the fixture returned a malformed window: \(serialize(value))")
        }
        return FixtureWindow(
            id: id, windowNumber: number, frame: frame, isKey: value["isKey"]?.boolValue ?? false)
    }

    private static func serialize(_ value: JSONValue) -> String {
        (try? value.serialized()) ?? "\(value)"
    }
}
