import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem
import Testing

/// Acceptance tests for the window animation: the installed Debug Piccolo moves windows of the
/// fixture app over a duration, and the window server shows the frames in between.
///
/// While `action.run` runs on a thread of its own, this process reads the frames of the windows
/// from the window server (CGWindowList, as `Measure` does) as often as it can. What a window
/// showed, in order and without repeats, is its path. An intermediate frame is one that is within
/// neither a point of the start nor of the target. The animation moves every edge one way only, so
/// the distance of each of x, y, width and height to the target must not grow from one frame to the
/// next, apart from the rounding of edges to whole points (1 pt for a position, 2 pt for a size,
/// which is the difference of two rounded edges).
///
/// This is a nested suite: it inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch from the
/// suite it extends, so that it never runs at the same time as another acceptance test.
extension DesktopAcceptanceTests {
    @Suite("Window animation")
    struct WindowAnimationAcceptance {
        private let piccolo = PiccoloClient()
        private var client: PiccoloClient { piccolo }

        // MARK: 1. placeWindow, slow

        @Test("animation 1. placeWindow with animation slow glides: 3 or more frames between start and target, monotonic, 0.4 s, ends on the target")
        func slowPlaceWindow() async throws {
            let (start, target) = try placement()

            try await withFixture { fixture in
                let window = try await openFocused(fixture, id: "slow-place", frame: start)

                let observed = try observing(windows: [window.windowNumber]) { [client = client] in
                    try client.runAction(.placeWindow(.preset(.leftHalf)), animation: "slow")
                }

                try expectGlide(of: window, in: observed, from: start, to: target, atLeast: 3, duration: 0.4)
                let achieved = try placed(observed.result, "placeWindow slow")
                #expect(
                    framesMatch(achieved.target, target),
                    "the response targets \(describe(achieved.target)), the left half is \(describe(target))")
                _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: target)
            }
        }

        // MARK: 2. arrangeGrid, slow

        @Test("animation 2. arrangeGrid of 3 windows with animation slow: every window glides, and the final frames are those of animation off")
        func slowArrangeGrid() async throws {
            let screen = try await ArrangeRun.screens()[0]
            let grid = GridSpec(count: 3, rows: 2, columns: 2)
            let ids = ["W1", "W2", "W3"]

            try await withFixture { fixture in
                let run = ArrangeRun(fixture: fixture)
                let pid = try fixture.processID()

                // The same arrangement without animation first: the frames to compare with.
                var windows = try await run.open(ids, on: screen)
                try await run.focus(windows)
                let offResult = try piccolo.arrangeGrid(grid, onlyPid: pid, animation: "off")
                var off: [CGRect] = []
                for entry in offResult {
                    off.append(try await Measure.waitForFrame(ofWindow: entry.window, matching: entry.achieved))
                }
                #expect(offResult.map(\.window) == windows.reversed().map(\.windowNumber))

                // The same windows in the same places, and the same focus order, again.
                try fixture.closeAll()
                windows = try await run.open(ids, on: screen)
                try await run.focus(windows)
                let starts = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowNumber, $0.frame) })

                let observed = try observing(windows: windows.map(\.windowNumber)) { [client = client] in
                    try client.arrangeGrid(grid, onlyPid: pid, animation: "slow")
                }

                let slow = observed.result
                let inCellOrder = Array(windows.reversed())
                #expect(slow.map(\.window) == inCellOrder.map(\.windowNumber))
                // One clock for all windows: they travel together, not one after the other.
                #expect(
                    observed.elapsed >= 0.4 && observed.elapsed < 0.9,
                    "the arrangement of three windows took \(observed.elapsed) s: one glide of 0.4 s was expected, not three in a row"
                )
                for (index, entry) in slow.enumerated() {
                    let start = try #require(starts[entry.window])
                    try expectGlide(
                        window: entry.window, name: inCellOrder[index].id, in: observed, from: start,
                        to: entry.target, atLeast: 3, duration: nil)
                    let final = try await Measure.waitForFrame(ofWindow: entry.window, matching: entry.achieved)
                    #expect(
                        framesMatch(final, off[index]),
                        "window \(inCellOrder[index].id) ends at \(describe(final)) after the slow arrangement and at \(describe(off[index])) after the arrangement without animation"
                    )
                    #expect(framesMatch(entry.achieved, offResult[index].achieved))
                }
            }
        }

        // MARK: 3. The config decides

        @Test("animation 3. with animation slow in the config, action.run without the param glides")
        func configDecides() async throws {
            let (start, target) = try placement()

            try await withConfigDirectory { config in
                let url = config.file()
                try ConfigStore(url: url).save(Config.frameTest(animation: .slow))
                let loaded = try piccolo.loadConfig(at: url)
                #expect(loaded.issues.isEmpty, "loading the config reported \(loaded.issues)")

                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "config-slow", frame: start)

                    let observed = try observing(windows: [window.windowNumber]) { [client = client] in
                        try client.runAction(.placeWindow(.preset(.leftHalf)))
                    }

                    try expectGlide(of: window, in: observed, from: start, to: target, atLeast: 3, duration: 0.4)
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: target)
                }
            }
        }

        @Test("animation 4. a config without animation means Medium: the glide lasts 0.25 s")
        func defaultIsMedium() async throws {
            let (start, target) = try placement()

            try await withConfigDirectory { config in
                let url = config.file()
                // No animation key at all. The gap is set to 0 so that the target is the left half itself.
                try Data(#"{"version": 1, "gap": 0, "bindings": []}"#.utf8).write(to: url)
                let loaded = try piccolo.loadConfig(at: url)
                #expect(loaded.issues.isEmpty, "loading the config reported \(loaded.issues)")

                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "config-fast", frame: start)

                    let observed = try observing(windows: [window.windowNumber]) { [client = client] in
                        try client.runAction(.placeWindow(.preset(.leftHalf)))
                    }

                    try expectGlide(of: window, in: observed, from: start, to: target, atLeast: 2, duration: 0.25)
                    #expect(
                        observed.elapsed < 0.25 + 0.3,
                        "a Medium glide of 0.25 s took \(observed.elapsed) s")
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: target)
                }
            }
        }

        // MARK: 4. The param

        @Test("animation 5. the param overrides the config: off jumps although the config says slow, an unknown value is refused")
        func paramOverridesConfig() async throws {
            let (start, target) = try placement()

            try await withConfigDirectory { config in
                let url = config.file()
                try ConfigStore(url: url).save(Config.frameTest(animation: .slow))
                _ = try piccolo.loadConfig(at: url)

                try await withFixture { fixture in
                    let window = try await openFocused(fixture, id: "param", frame: start)

                    // Refused before anything moves.
                    for value: JSONValue in ["turbo", 1, true, ""] {
                        var params = try placeParams(.placeWindow(.preset(.leftHalf)))
                        params["animation"] = value
                        let message = try piccolo.runActionExpectingRefusal(params: params)
                        #expect(
                            message.contains("animation") && message.contains("slow"),
                            "the refusal of animation \(value) is \"\(message)\", it should name the param and the values")
                        let measured = Measure.frame(ofWindow: window.windowNumber)
                        #expect(
                            measured.map { framesMatch($0, start) } == true,
                            "after the refused animation \(value) the window is measured at \(measured.map { describe($0) } ?? "nowhere"), it should still be at \(describe(start))"
                        )
                    }

                    // "off" overrides the config's slow: the window jumps, within the three steps of
                    // a placement, not over 0.4 s.
                    let observed = try observing(windows: [window.windowNumber]) { [client = client] in
                        try client.runAction(.placeWindow(.preset(.leftHalf)), animation: "off")
                    }
                    let path = Path(observed.samples, window: window.windowNumber)
                    let between = path.between(start: start, target: target)
                    #expect(
                        between.count <= 2,
                        "with animation off the window showed \(between.count) frames between the start and the target: \(between.map { describe($0) })"
                    )
                    #expect(
                        observed.elapsed < 0.4,
                        "with animation off the call took \(observed.elapsed) s, the config's slow glide is 0.4 s")
                    _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: target)
                }
            }
        }

        // MARK: Helpers

        /// A start frame on the primary display and the left half of its visible frame.
        private func placement() throws -> (start: CGRect, target: CGRect) {
            let screens = try Layout.screens()
            let start = Layout.frame(
                in: screens[0], offset: CGPoint(x: 120, y: 80), size: CGSize(width: 640, height: 420))
            let target = FrameResolver.frame(
                for: .preset(.leftHalf), visibleFrame: screens[0].visibleFrame, currentFrame: start)
            return (start, target)
        }

        /// Opens a window at `frame`, waits until it is there and brings it into focus, which is what
        /// a Piccolo action acts on.
        private func openFocused(_ fixture: FixtureApp, id: String, frame: CGRect) async throws -> FixtureWindow {
            let window = try fixture.open(id: id, frame: frame)
            _ = try await Measure.waitForFrame(ofWindow: window.windowNumber, matching: frame)
            try await Focus.bring(window, of: fixture)
            return window
        }

        private func placeParams(_ action: Action) throws -> [String: JSONValue] {
            try JSONValue(encoding: action).objectValue ?? [:]
        }

        private func placed(_ result: PiccoloClient.ActionResult, _ what: String) throws -> (target: CGRect, achieved: CGRect) {
            guard case .placed(let target, let achieved) = result else {
                throw AcceptanceFailure("\(what) answered \(result), expected a placement")
            }
            return (target, achieved)
        }

        private func expectGlide(
            of window: FixtureWindow, in observed: Observed<some Any>, from start: CGRect, to target: CGRect,
            atLeast minimum: Int, duration: TimeInterval?
        ) throws {
            try expectGlide(
                window: window.windowNumber, name: window.id, in: observed, from: start, to: target,
                atLeast: minimum, duration: duration)
        }

        /// Checks what one window showed during the call: frames between start and target, moving
        /// towards the target only; and, when `duration` is given, a call that took at least that long.
        /// Where the window ends is not checked here: the window server shows the last frame a few
        /// milliseconds after the call returned, so the tests poll for it (`Measure.waitForFrame`).
        private func expectGlide(
            window: Int, name: String, in observed: Observed<some Any>, from start: CGRect, to target: CGRect,
            atLeast minimum: Int, duration: TimeInterval?
        ) throws {
            let path = Path(observed.samples, window: window)
            let between = path.between(start: start, target: target)
            #expect(
                between.count >= minimum,
                "window '\(name)' showed \(between.count) frames between \(describe(start)) and \(describe(target)), expected at least \(minimum) (\(observed.samples.count) samples in \(observed.elapsed) s; path: \(path.frames.map { describe($0) }))"
            )
            let regressions = path.regressions(towards: target)
            #expect(
                regressions.isEmpty,
                "window '\(name)' did not move monotonically towards \(describe(target)): \(regressions)")
            if let duration {
                #expect(
                    observed.elapsed >= duration,
                    "the call took \(observed.elapsed) s, a glide of \(duration) s was expected")
            }
        }
    }
}

// MARK: - Observing a window during a call

/// A window's frame as the window server showed it, and when (seconds since the call began).
private struct Sample {
    var time: TimeInterval
    var window: Int
    var frame: CGRect
}

/// What a call answered, how long it took, and what the windows showed meanwhile.
private struct Observed<Result> {
    var result: Result
    var elapsed: TimeInterval
    var samples: [Sample]
}

private final class Finish<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: (result: Result<Value, Error>, elapsed: TimeInterval)?

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return outcome != nil
    }

    func finish(_ result: Result<Value, Error>, elapsed: TimeInterval) {
        lock.lock()
        outcome = (result, elapsed)
        lock.unlock()
    }

    func take() -> (result: Result<Value, Error>, elapsed: TimeInterval)? {
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }
}

/// Runs `work` on a thread of its own and reads the frames of `windows` from the window server, over
/// and over, until it has returned. Returns its result with the time it took and every frame read.
private func observing<Result: Sendable>(
    windows: [Int], during work: @escaping @Sendable () throws -> Result
) throws -> Observed<Result> {
    let finish = Finish<Result>()
    let origin = ProcessInfo.processInfo.systemUptime
    let thread = Thread {
        let started = ProcessInfo.processInfo.systemUptime
        let result = Swift.Result { try work() }
        finish.finish(result, elapsed: ProcessInfo.processInfo.systemUptime - started)
    }
    var samples: [Sample] = []
    func look() {
        for window in windows {
            if let frame = Measure.frame(ofWindow: window) {
                samples.append(
                    Sample(time: ProcessInfo.processInfo.systemUptime - origin, window: window, frame: frame))
            }
        }
    }
    look()
    thread.start()
    while !finish.isFinished { look() }
    look()
    guard let outcome = finish.take() else {
        throw AcceptanceFailure("the observed call did not finish")
    }
    return Observed(result: try outcome.result.get(), elapsed: outcome.elapsed, samples: samples)
}

/// The frames one window showed, in order, each shown once however often it was seen.
private struct Path {
    let frames: [CGRect]

    init(_ samples: [Sample], window: Int) {
        var frames: [CGRect] = []
        for sample in samples where sample.window == window && frames.last != sample.frame {
            frames.append(sample.frame)
        }
        self.frames = frames
    }

    /// The distinct frames that are within a point of neither the start nor the target.
    func between(start: CGRect, target: CGRect) -> [CGRect] {
        var found: [CGRect] = []
        for frame in frames where !framesMatch(frame, start) && !framesMatch(frame, target) && !found.contains(frame) {
            found.append(frame)
        }
        return found
    }

    /// Where the window moved away from the target between two frames it showed, one per mistake.
    /// The distance of x, y, width and height to the target may not grow, but for the rounding of
    /// the edges (1 pt for a position, 2 pt for a size).
    func regressions(towards target: CGRect) -> [String] {
        let components: [(name: String, value: KeyPath<CGRect, CGFloat>, tolerance: CGFloat)] = [
            ("x", \.minX, 1), ("y", \.minY, 1), ("width", \.width, 2), ("height", \.height, 2),
        ]
        var found: [String] = []
        for (earlier, later) in zip(frames, frames.dropFirst()) {
            for component in components {
                let before = abs(earlier[keyPath: component.value] - target[keyPath: component.value])
                let after = abs(later[keyPath: component.value] - target[keyPath: component.value])
                if after > before + component.tolerance {
                    found.append("\(component.name) went from \(describe(earlier)) to \(describe(later))")
                }
            }
        }
        return found
    }
}

// MARK: - The commands

extension PiccoloClient {
    /// `action.run` with an action and an `animation` that replaces the config's for this call.
    fileprivate func runAction(_ action: Action, animation: String) throws -> ActionResult {
        var params = try JSONValue(encoding: action).objectValue ?? [:]
        params["animation"] = .string(animation)
        return try runAction(params: params)
    }

    /// One window of an arrangement, as `action.run` reports it.
    fileprivate struct Arranged {
        var window: Int
        var target: CGRect
        var achieved: CGRect
    }

    /// `action.run` with an `arrangeGrid` action restricted to one process and an `animation`. The
    /// windows in the order the answer lists them (the one in the top-left cell first); a window that
    /// could not be moved is an error.
    fileprivate func arrangeGrid(_ grid: GridSpec, onlyPid: pid_t, animation: String) throws -> [Arranged] {
        var params = try JSONValue(encoding: Action.arrangeGrid(grid)).objectValue ?? [:]
        params["onlyPid"] = .int(Int(onlyPid))
        params["animation"] = .string(animation)
        let result = try send("action.run", params)
        guard let entries = result["windows"]?.arrayValue else {
            throw AcceptanceFailure("Piccolo's arrangeGrid answer has no windows: \(result)")
        }
        return try entries.map { entry in
            guard let window = entry["window"]?.intValue, let target = entry["target"]?.rectValue else {
                throw AcceptanceFailure("Piccolo's arrangeGrid answer lists a malformed window: \(entry)")
            }
            guard let achieved = entry["achieved"]?.rectValue else {
                throw AcceptanceFailure("window \(window) could not be moved: \(entry["error"]?.stringValue ?? "no reason given")")
            }
            return Arranged(window: window, target: target, achieved: achieved)
        }
    }
}
