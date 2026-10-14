import AppKit
import PiccoloControl
import PiccoloCore

/// A titled window that remembers the id it was opened with, and the key-down events it receives.
final class FixtureWindow: NSWindow {
    private(set) var fixtureID = ""
    /// The key codes of the key-down events this window received, in order. A key that a global
    /// hotkey took never gets here, which is what the tests of Escape rely on.
    private(set) var keyDownCodes: [Int] = []

    convenience init(id: String, resizable: Bool) {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: style, backing: .buffered, defer: false)
        fixtureID = id
        title = id
        // The registry owns the window; AppKit must not release it behind its back.
        isReleasedWhenClosed = false
        isRestorable = false
        // The open and close animations briefly report a slightly larger frame to the
        // window server, which makes measurements right after a command unreliable.
        animationBehavior = .none
        contentView = Self.makeContent(showing: id)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            keyDownCodes.append(Int(event.keyCode))
        }
        super.sendEvent(event)
    }

    private static func makeContent(showing id: String) -> NSView {
        let label = NSTextField(labelWithString: id)
        label.font = .systemFont(ofSize: 32, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        return content
    }
}

/// The windows the fixture has opened, by id, and the operations on them.
///
/// Frames cross this boundary in canonical coordinates (global, top-left origin, y
/// down), the space Accessibility and the window server use. AppKit's own space is
/// converted at the edge.
@MainActor
final class FixtureWindows {
    private var windows: [String: FixtureWindow] = [:]
    private let delegate = FixtureWindowDelegate()

    init() {
        delegate.onClose = { [weak self] window in
            guard let window = window as? FixtureWindow else { return }
            self?.windows[window.fixtureID] = nil
        }
    }

    func open(_ request: OpenRequest) throws -> JSONValue {
        guard windows[request.id] == nil else {
            throw ControlCommandError.failed("a window with id '\(request.id)' is already open")
        }
        let frame = CGRect(
            x: request.frame.x, y: request.frame.y,
            width: request.frame.width, height: request.frame.height)
        let appKitFrame = try appKitFrame(fromCanonical: frame)

        let window = FixtureWindow(id: request.id, resizable: request.resizable ?? true)
        window.delegate = delegate
        if let size = request.minSize { window.minSize = size.cgSize }
        if let size = request.maxSize { window.maxSize = size.cgSize }
        if let size = request.resizeIncrements { window.resizeIncrements = size.cgSize }

        windows[request.id] = window
        window.setFrame(appKitFrame, display: true)
        // The fixture is usually not the active app, and a plain orderFront would
        // leave its windows behind everything else.
        window.orderFrontRegardless()
        waitUntilOnScreen(window)
        return .object(describe(window))
    }

    func focus(id: String) throws -> JSONValue {
        let window = try window(id)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is asynchronous; report what the app ended up with instead of
        // assuming. Callers verify focus independently.
        spinMainRunLoop(until: 1.5) { NSApp.isActive && window.isKeyWindow }
        var result = describe(window)
        result["isKey"] = .bool(window.isKeyWindow)
        result["isActive"] = .bool(NSApp.isActive)
        return .object(result)
    }

    func list() -> JSONValue {
        let ordered = windows.values.sorted { $0.fixtureID < $1.fixtureID }
        return .array(
            ordered.map { window in
                var entry = describe(window)
                entry["isKey"] = .bool(window.isKeyWindow)
                entry["isMiniaturized"] = .bool(window.isMiniaturized)
                return .object(entry)
            })
    }

    /// Minimizes the window into the Dock and waits (bounded) until the window server no longer
    /// lists it as on screen, which is after the system's own animation.
    func miniaturize(id: String) throws -> JSONValue {
        let window = try window(id)
        window.miniaturize(nil)
        spinMainRunLoop(until: 5) {
            window.isMiniaturized && windowServerBounds(of: window.windowNumber) == nil
        }
        guard window.isMiniaturized else {
            throw ControlCommandError.failed("window '\(id)' did not minimize")
        }
        var result = describe(window)
        result["isMiniaturized"] = .bool(true)
        return .object(result)
    }

    /// Brings a minimized window back and waits (bounded) until the window server lists it at
    /// its frame again. A window that is not minimized is left as it is.
    func deminiaturize(id: String) throws -> JSONValue {
        let window = try window(id)
        if window.isMiniaturized {
            window.deminiaturize(nil)
            waitUntilOnScreen(window)
        }
        guard !window.isMiniaturized else {
            throw ControlCommandError.failed("window '\(id)' did not come back from the Dock")
        }
        var result = describe(window)
        result["isMiniaturized"] = .bool(false)
        return .object(result)
    }

    /// The key codes of the key-down events the window received so far, oldest first.
    func keyEvents(id: String) throws -> JSONValue {
        let window = try window(id)
        return ["keyCodes": .array(window.keyDownCodes.map { .int($0) })]
    }

    func close(id: String) throws -> JSONValue {
        let window = try window(id)
        let number = window.windowNumber
        window.close()
        windows[id] = nil
        waitUntilOffScreen([number])
        return ["id": .string(id)]
    }

    func closeAll() -> JSONValue {
        let all = Array(windows.values)
        let numbers = all.map(\.windowNumber)
        for window in all { window.close() }
        windows.removeAll()
        waitUntilOffScreen(numbers)
        return ["closed": .int(all.count)]
    }

    // MARK: Helpers

    private func window(_ id: String) throws -> FixtureWindow {
        guard let window = windows[id] else {
            throw ControlCommandError.failed("no window with id '\(id)'")
        }
        return window
    }

    private func describe(_ window: FixtureWindow) -> [String: JSONValue] {
        [
            "id": .string(window.fixtureID),
            "windowNumber": .int(window.windowNumber),
            "frame": JSONValue(rect: canonicalFrame(of: window)),
        ]
    }

    private func primaryDisplayHeight() throws -> CGFloat {
        // The first screen is the one with the menu bar, whose height anchors the
        // conversion between AppKit and canonical space.
        guard let primary = NSScreen.screens.first else {
            throw ControlCommandError.failed("no display is attached")
        }
        return primary.frame.height
    }

    private func appKitFrame(fromCanonical frame: CGRect) throws -> CGRect {
        ScreenSpace.appKitRect(fromCanonical: frame, primaryDisplayHeight: try primaryDisplayHeight())
    }

    private func canonicalFrame(of window: NSWindow) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return ScreenSpace.canonicalRect(fromAppKit: window.frame, primaryDisplayHeight: height)
    }

    /// Waits (bounded) until the window server lists the window at its frame, so that a
    /// caller who measures right after the response sees the window.
    private func waitUntilOnScreen(_ window: FixtureWindow) {
        spinMainRunLoop(until: 2) {
            guard let bounds = windowServerBounds(of: window.windowNumber) else { return false }
            let frame = canonicalFrame(of: window)
            return abs(bounds.minX - frame.minX) <= 1 && abs(bounds.minY - frame.minY) <= 1
                && abs(bounds.width - frame.width) <= 1 && abs(bounds.height - frame.height) <= 1
        }
    }

    /// Waits (bounded) until the window server no longer lists the windows as on screen.
    private func waitUntilOffScreen(_ windowNumbers: [Int]) {
        spinMainRunLoop(until: 2) {
            windowNumbers.allSatisfy { windowServerBounds(of: $0) == nil }
        }
    }
}

/// Runs the main run loop in short slices until `condition` holds or `seconds` pass.
@MainActor
private func spinMainRunLoop(until seconds: TimeInterval, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}

/// The frame the window server reports for a window that it lists as on screen.
private func windowServerBounds(of windowNumber: Int) -> CGRect? {
    guard windowNumber > 0,
        let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber))
            as? [[String: Any]],
        let entry = info.first(where: { ($0[kCGWindowNumber as String] as? Int) == windowNumber }),
        entry[kCGWindowIsOnscreen as String] as? Bool == true,
        let bounds = entry[kCGWindowBounds as String] as? NSDictionary
    else { return nil }
    return CGRect(dictionaryRepresentation: bounds as CFDictionary)
}

extension SizeParams {
    fileprivate var cgSize: CGSize { CGSize(width: width, height: height) }
}

/// Reacts to windows closing by their own means (the close button, a Cmd-W).
@MainActor
final class FixtureWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: ((NSWindow) -> Void)?

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        onClose?(window)
    }
}

/// Ends the app after the control reply has had time to go out.
enum FixtureQuit {
    @MainActor
    static func scheduleTermination() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
            // Terminate can be vetoed (a sheet, a delegate); the fixture has none, but
            // the quit command must not leave a process behind.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
        }
    }
}
