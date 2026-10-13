import AppKit
import OSLog
import PiccoloControl

/// Hosts the fixture's control server for the lifetime of the app.
@MainActor
final class FixtureAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "io.damao.piccolo.fixture", category: "control")
    private let windows = FixtureWindows()
    private var server: ControlServer?
    private var activity: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The fixture is often hidden behind other windows while tests wait for it. Keep
        // the system from napping or terminating it, which would delay control requests.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiatedAllowingIdleSystemSleep,
                .automaticTerminationDisabled,
                .suddenTerminationDisabled,
            ],
            reason: "Serving acceptance tests")

        let router = FixtureCommands.makeRouter(windows: windows)
        do {
            // Handlers run on the server's own queue and hop to the main thread for
            // AppKit work (see FixtureCommands).
            server = try ControlServer(serviceName: ControlServiceName.fixture) {
                router.handle($0)
            }
            logger.info("control server listening on \(ControlServiceName.fixture, privacy: .public)")
        } catch {
            logger.error("control server not started: \(error.localizedDescription, privacy: .public)")
            // Without a server the fixture is useless, and a silent half-working app
            // would only show up as a confusing timeout in the tests.
            exit(1)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
