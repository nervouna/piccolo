import Foundation
import PiccoloControl

/// The fixture's control commands.
///
/// Control handlers run on the server's own queue, not on the main thread, while every
/// AppKit call must run on the main thread. Each handler therefore decodes its params
/// on the server's queue, runs the window operation on the main thread and waits for
/// it, so that the response is only sent once the operation has taken effect.
enum FixtureCommands {
    nonisolated static func makeRouter(windows: FixtureWindows) -> ControlRouter {
        var router = ControlRouter()

        router.register("open") { params in
            let request = try params.decode(OpenRequest.self)
            try request.validate()
            return try onMain { try windows.open(request) }
        }

        router.register("focus") { params in
            let id = try params.decode(WindowID.self).id
            return try onMain { try windows.focus(id: id) }
        }

        router.register("list") { _ in
            onMain { windows.list() }
        }

        router.register("close") { params in
            let id = try params.decode(WindowID.self).id
            return try onMain { try windows.close(id: id) }
        }

        router.register("miniaturize") { params in
            let id = try params.decode(WindowID.self).id
            return try onMain { try windows.miniaturize(id: id) }
        }

        router.register("deminiaturize") { params in
            let id = try params.decode(WindowID.self).id
            return try onMain { try windows.deminiaturize(id: id) }
        }

        router.register("closeAll") { _ in
            onMain { windows.closeAll() }
        }

        router.register("quit") { _ in
            // Reply first: the process ends shortly after, and a client must not see
            // the connection drop instead of an answer.
            onMain { FixtureQuit.scheduleTermination() }
            return ["quitting": true]
        }

        return router
    }
}

/// Runs `body` on the main thread and waits for its result.
///
/// Only called from the control server's queue, which is never the main thread, so
/// the synchronous hop cannot deadlock.
private func onMain<T: Sendable>(_ body: @MainActor () throws -> T) rethrows -> T {
    try DispatchQueue.main.sync {
        try MainActor.assumeIsolated { try body() }
    }
}

// MARK: - Params

struct WindowID: Decodable {
    var id: String
}

struct SizeParams: Decodable {
    var width: Double
    var height: Double

    var isValid: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

struct FrameParams: Decodable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
}

/// Parameters of `open`. Every size constraint is in points and applies to the
/// window's frame (title bar included), the same quantity Accessibility reports.
struct OpenRequest: Decodable {
    var id: String
    /// In canonical coordinates (global, top-left origin, y down).
    var frame: FrameParams
    var minSize: SizeParams?
    var maxSize: SizeParams?
    var resizeIncrements: SizeParams?
    /// Defaults to true.
    var resizable: Bool?

    func validate() throws {
        guard !id.isEmpty else {
            throw ControlCommandError.invalidParams("id must not be empty")
        }
        guard frame.isValid else {
            throw ControlCommandError.invalidParams(
                "frame needs finite x and y and a positive width and height")
        }
        for (name, size) in [
            ("minSize", minSize), ("maxSize", maxSize), ("resizeIncrements", resizeIncrements),
        ] {
            if let size, !size.isValid {
                throw ControlCommandError.invalidParams(
                    "\(name) needs a positive width and height")
            }
        }
    }
}
