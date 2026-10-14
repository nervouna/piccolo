import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore

/// The commands about holding a shortcut and the destination preview.
extension PiccoloClient {
    /// What `preview.state` answers.
    struct PreviewState: Equatable {
        struct Last: Equatable {
            var bindingID: UUID
            /// `"ran"` or `"cancelled"`.
            var result: String
            var previewShown: Bool
        }

        /// Whether the highlight is on screen, and the frames it is drawn at.
        var visible: Bool
        var frames: [CGRect]
        /// The window each frame is for, for an arrangement or a divider move.
        var windows: [Int]?
        /// The binding whose shortcut is down.
        var heldBindingID: UUID?
        var escapeRegistered: Bool
        var planningError: String?
        var last: Last?
    }

    /// `preview.state`.
    func previewState() throws -> PreviewState {
        let result = try send("preview.state")
        guard let visible = result["visible"]?.boolValue,
            let frames = result["frames"]?.arrayValue?.map({ $0.rectValue }),
            let escapeRegistered = result["escapeRegistered"]?.boolValue
        else {
            throw AcceptanceFailure("Piccolo's preview.state answer is malformed: \(result)")
        }
        guard frames.allSatisfy({ $0 != nil }) else {
            throw AcceptanceFailure("preview.state lists a frame that is not a rectangle: \(result)")
        }
        var last: PreviewState.Last?
        if let entry = result["last"], entry != .null {
            guard let idText = entry["bindingID"]?.stringValue, let id = UUID(uuidString: idText),
                let outcome = entry["result"]?.stringValue, let shown = entry["previewShown"]?.boolValue
            else {
                throw AcceptanceFailure("preview.state has a malformed last: \(entry)")
            }
            last = PreviewState.Last(bindingID: id, result: outcome, previewShown: shown)
        }
        return PreviewState(
            visible: visible,
            frames: frames.compactMap { $0 },
            windows: result["windows"]?.arrayValue?.compactMap { $0.intValue },
            heldBindingID: result["heldBindingID"]?.stringValue.flatMap { UUID(uuidString: $0) },
            escapeRegistered: escapeRegistered,
            planningError: result["planningError"]?.stringValue,
            last: last)
    }

    /// `hotkey.press`: posts the key-down of the binding's shortcut and answers once the hotkey has
    /// fired. With `autorepeat`, that many more key-downs flagged as auto-repeat follow, and the
    /// answer is how many presses the app saw in all.
    @discardableResult
    func pressHotkey(_ id: UUID, autorepeat: Int? = nil) throws -> Int? {
        var params: [String: JSONValue] = ["id": .string(id.uuidString)]
        if let autorepeat { params["autorepeat"] = .int(autorepeat) }
        let result = try send("hotkey.press", params)
        guard result["fired"]?.boolValue == true else {
            throw AcceptanceFailure("hotkey.press for \(id) did not report the hotkey as fired: \(result)")
        }
        return result["presses"]?.intValue
    }

    /// `hotkey.release`: posts the key-up of the binding's shortcut and answers once the app saw the
    /// hotkey released. With `modifiersFirst` the modifiers go up before the key.
    func releaseHotkey(_ id: UUID, modifiersFirst: Bool = false) throws {
        var params: [String: JSONValue] = ["id": .string(id.uuidString)]
        if modifiersFirst { params["modifiersFirst"] = .bool(true) }
        let result = try send("hotkey.release", params)
        guard result["released"]?.boolValue == true else {
            throw AcceptanceFailure("hotkey.release for \(id) did not report the hotkey as released: \(result)")
        }
    }

    /// `hotkey.release` that must be refused, or that the app never sees. Returns the reason.
    func releaseHotkeyExpectingRefusal(_ id: UUID, modifiersFirst: Bool = false) throws -> String {
        var params: [String: JSONValue] = ["id": .string(id.uuidString)]
        if modifiersFirst { params["modifiersFirst"] = .bool(true) }
        let response = try sendRaw("hotkey.release", params)
        guard !response.ok else {
            throw AcceptanceFailure("hotkey.release accepted binding \(id); it answered \(String(describing: response.result))")
        }
        return response.error ?? "no reason given"
    }

    /// `hotkey.escape`: presses and releases Escape with the modifiers of the shortcut that is held.
    func pressEscape() throws {
        let result = try send("hotkey.escape")
        guard result["fired"]?.boolValue == true else {
            throw AcceptanceFailure("hotkey.escape did not report the Escape hotkey as fired: \(result)")
        }
    }

    /// `hotkey.escape` that must be refused (nothing is held). Returns the reason.
    func pressEscapeExpectingRefusal() throws -> String {
        let response = try sendRaw("hotkey.escape")
        guard !response.ok else {
            throw AcceptanceFailure("hotkey.escape was accepted with nothing held; it answered \(String(describing: response.result))")
        }
        return response.error ?? "no reason given"
    }
}

extension FixtureApp {
    /// The key codes of the key-down events the window received, oldest first (`keyEvents`).
    func keyEvents(id: String) throws -> [Int] {
        let result = try send("keyEvents", ["id": .string(id)])
        guard let codes = result["keyCodes"]?.arrayValue else {
            throw AcceptanceFailure("the fixture's keyEvents answer for '\(id)' has no keyCodes: \(result)")
        }
        return codes.compactMap { $0.intValue }
    }
}

/// The windows Piccolo shows as highlight, seen from the window server (CGWindowList) and not from
/// Piccolo.
enum PiccoloOverlays {
    /// One window of Piccolo on screen.
    struct Entry: Equatable {
        var number: Int
        var layer: Int
        var frame: CGRect
        var alpha: Double
    }

    /// Every window `pid` has on screen, whatever its layer, except the menu bar item.
    static func onScreen(pid: pid_t) -> [Entry] {
        guard
            let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard (entry[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                let number = entry[kCGWindowNumber as String] as? Int,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                frame.width >= 40, frame.height >= 40
            else { return nil }
            return Entry(
                number: number, layer: layer, frame: frame,
                alpha: entry[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }

    /// Waits until a window of `pid` is on screen at each of `frames` (within the usual tolerance), and
    /// returns them in the order of `frames`.
    static func waitForHighlights(pid: pid_t, at frames: [CGRect], timeout: TimeInterval = 5) async throws -> [Entry] {
        try await eventually(
            "windows of Piccolo (pid \(pid)) on screen at \(frames.map(describe))", timeout: timeout
        ) { () -> Observation<[Entry]> in
            let present = onScreen(pid: pid)
            var found: [Entry] = []
            for frame in frames {
                guard let entry = present.first(where: { framesMatch($0.frame, frame) }) else {
                    return .unsatisfied("Piccolo has windows at \(present.map { describe($0.frame) })")
                }
                found.append(entry)
            }
            return .satisfied(found)
        }
    }

    /// Waits until `pid` has no window on screen at any of `frames`.
    static func waitForNoHighlight(pid: pid_t, at frames: [CGRect], timeout: TimeInterval = 5) async throws {
        try await eventually(
            "no window of Piccolo (pid \(pid)) at \(frames.map(describe))", timeout: timeout
        ) { () -> Observation<Void> in
            let present = onScreen(pid: pid).filter { entry in frames.contains { framesMatch(entry.frame, $0) } }
            return present.isEmpty ? .satisfied(()) : .unsatisfied("windows at \(present.map { describe($0.frame) })")
        }
    }
}
