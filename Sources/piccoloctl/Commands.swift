import Foundation
import PiccoloControl
import PiccoloSystem

/// What a command prints and how the process exits.
struct Outcome {
    var output: String
    var exitCode: Int32

    static func success(_ value: JSONValue) -> Outcome {
        Outcome(output: serialize(value), exitCode: 0)
    }

    /// A failure in the same shape as a control response: `{"error": ..., "ok": false}`.
    static func failure(_ message: String, exitCode: Int32 = 1) -> Outcome {
        Outcome(output: serialize(.object(["ok": false, "error": .string(message)])), exitCode: exitCode)
    }

    private static func serialize(_ value: JSONValue) -> String {
        (try? value.serialized()) ?? #"{"error":"could not encode output","ok":false}"#
    }
}

enum Commands {
    static let usage = """
        usage: piccoloctl app <command> [--params '<json object>'] [--service <name>] [--timeout <seconds>]
               piccoloctl fixture <command> [--params '<json object>'] [--timeout <seconds>]
               piccoloctl windows
               piccoloctl screens
               piccoloctl frontmost
        """

    @MainActor
    static func run(arguments: [String]) -> Outcome {
        guard let command = arguments.first else {
            return .failure(usage, exitCode: 2)
        }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "app":
            return app(rest)
        case "fixture":
            // `app` aimed at the acceptance fixture: same options, other default service.
            return app(rest, defaultService: ControlServiceName.fixture)
        case "windows":
            return rest.isEmpty ? windows() : .failure(usage, exitCode: 2)
        case "screens":
            return rest.isEmpty ? screens() : .failure(usage, exitCode: 2)
        case "frontmost":
            return rest.isEmpty ? frontmost() : .failure(usage, exitCode: 2)
        case "-h", "--help", "help":
            return .success(["usage": .string(usage)])
        default:
            return .failure("unknown command '\(command)'\n\(usage)", exitCode: 2)
        }
    }

    // MARK: app

    private struct AppArguments {
        var command: String
        var params: [String: JSONValue] = [:]
        var service: String
        var timeout = ControlClient.defaultTimeout
    }

    private enum ArgumentError: Error {
        case message(String)
    }

    private static func parseAppArguments(
        _ arguments: [String], defaultService: String
    ) throws -> AppArguments {
        var command: String?
        var parsed = AppArguments(command: "", service: defaultService)
        var index = 0

        func value(for option: String) throws -> String {
            index += 1
            guard index < arguments.count else {
                throw ArgumentError.message("\(option) needs a value")
            }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--params":
                let text = try value(for: argument)
                do {
                    parsed.params = try JSONValue.parseObject(text)
                } catch {
                    throw ArgumentError.message("--params must be a JSON object: \(failureText(error))")
                }
            case "--service":
                parsed.service = try value(for: argument)
            case "--timeout":
                let text = try value(for: argument)
                guard let seconds = TimeInterval(text), seconds > 0, seconds.isFinite else {
                    throw ArgumentError.message("--timeout must be a positive number of seconds")
                }
                parsed.timeout = seconds
            case _ where argument.hasPrefix("--"):
                throw ArgumentError.message("unknown option '\(argument)'")
            default:
                guard command == nil else {
                    throw ArgumentError.message("unexpected argument '\(argument)'")
                }
                command = argument
            }
            index += 1
        }

        guard let command else { throw ArgumentError.message("missing <command>") }
        parsed.command = command
        return parsed
    }

    private static func app(
        _ arguments: [String], defaultService: String = ControlServiceName.piccolo
    ) -> Outcome {
        let parsed: AppArguments
        do {
            parsed = try parseAppArguments(arguments, defaultService: defaultService)
        } catch ArgumentError.message(let message) {
            return .failure("\(message)\n\(usage)", exitCode: 2)
        } catch {
            return .failure(failureText(error), exitCode: 2)
        }

        let client = ControlClient(serviceName: parsed.service, timeout: parsed.timeout)
        do {
            let response = try client.send(command: parsed.command, params: parsed.params)
            let text = String(decoding: try response.encoded(), as: UTF8.self)
            return Outcome(output: text, exitCode: response.ok ? 0 : 1)
        } catch let error as ControlError {
            var message = failureText(error)
            if case .noServer = error {
                switch parsed.service {
                case ControlServiceName.piccolo:
                    message += "; is Piccolo running, and is it a Debug build? Release builds have no control server"
                case ControlServiceName.fixture:
                    message += "; is the fixture running? scripts/accept.sh starts it, or open build/PiccoloFixture.app"
                default:
                    break
                }
            }
            return .failure(message)
        } catch {
            return .failure(failureText(error))
        }
    }

    // MARK: Local queries

    private static func windows() -> Outcome {
        let list = OnScreenWindows.list().map { window -> JSONValue in
            [
                "windowNumber": .int(window.windowNumber),
                "pid": .int(Int(window.pid)),
                "ownerName": .string(window.ownerName),
                "frame": JSONValue(rect: window.frame),
            ]
        }
        return .success(.array(list))
    }

    @MainActor
    private static func screens() -> Outcome {
        let list = Screens.current().map { screen -> JSONValue in
            [
                "index": .int(screen.index),
                "isPrimary": .bool(screen.isPrimary),
                "frame": JSONValue(rect: screen.frame),
                "visibleFrame": JSONValue(rect: screen.visibleFrame),
            ]
        }
        return .success(.array(list))
    }

    private static func frontmost() -> Outcome {
        guard let app = FrontmostApplication.current() else {
            return .failure("no application is frontmost")
        }
        return .success([
            "pid": .int(Int(app.pid)),
            "bundleID": app.bundleID.map { .string($0) } ?? .null,
            "name": app.name.map { .string($0) } ?? .null,
        ])
    }

    private static func failureText(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
