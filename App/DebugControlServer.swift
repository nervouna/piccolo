#if DEBUG
import CoreGraphics
import Foundation
import OSLog
import PiccoloControl
import PiccoloCore
import PiccoloSystem

/// The Debug-only control channel: lets scripts and tests query the running app and
/// trigger actions without keyboard input. `piccoloctl app <command>` talks to it.
///
/// This whole file is compiled out of Release builds, which therefore contain no
/// control server and never start one.
@MainActor
final class DebugControlServer {
    private let logger = Logger(subsystem: "io.damao.piccolo", category: "control")
    private var server: ControlServer?

    /// Starts serving under ``ControlServiceName/piccolo``. A failure (for example a
    /// second instance that finds the name taken) is logged and otherwise ignored:
    /// the app works without the channel.
    func start() {
        guard server == nil else { return }
        let router = Self.makeRouter()
        do {
            // Handlers run on the server's own queue, never on the main thread, so that
            // an unresponsive target app cannot freeze the menu bar UI.
            server = try ControlServer(serviceName: ControlServiceName.piccolo) {
                router.handle($0)
            }
            logger.info("control server listening on \(ControlServiceName.piccolo, privacy: .public)")
        } catch {
            logger.error("control server not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct FrameParams: Decodable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    nonisolated static func makeRouter(executor: ActionExecutor = .live) -> ControlRouter {
        var router = ControlRouter()
        registerConfigCommands(in: &router)
        registerSettingsCommands(in: &router)

        router.register("status") { _ in
            let report = SelfCheck.makeReport()
            return [
                "axTrusted": .bool(report.axTrusted),
                "version": .string(report.version),
                "build": .string(report.build),
                "bundlePath": .string(report.bundlePath),
                "pid": .int(Int(ProcessInfo.processInfo.processIdentifier)),
            ]
        }

        router.register("window.focusedFrame") { _ in
            let window = try FocusedWindow.current()
            return [
                "frame": JSONValue(rect: try window.frame()),
                "pid": .int(Int(window.pid)),
                "appName": .string(window.appName),
            ]
        }

        router.register("window.setFocusedFrame") { params in
            let frame = try params.decode(FrameParams.self)
            let values = [frame.x, frame.y, frame.width, frame.height]
            guard values.allSatisfy(\.isFinite), frame.width > 0, frame.height > 0 else {
                throw ControlCommandError.invalidParams(
                    "x and y must be finite, width and height must be positive")
            }
            let window = try FocusedWindow.current()
            let achieved = try window.setFrame(
                CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height))
            return ["frame": JSONValue(rect: achieved)]
        }

        // action.run and focus.history, in DebugArrangeCommands.swift.
        registerArrangeCommands(in: &router, executor: executor)
        return router
    }
}
#endif
