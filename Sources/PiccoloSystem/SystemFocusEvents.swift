import AppKit
import ApplicationServices
import Foundation
import OSLog

/// The focus events of the live system.
///
/// - Workspace notifications: an application became active, an application quit, the active Space
///   changed.
/// - Accessibility notifications from the active application: its focused window or its main window
///   changed. Only the active application is observed. When another application becomes active the
///   observer moves to it, and the one of an application that quits is removed.
///
/// All state is confined to a serial queue. Accessibility notifications arrive on the run loop of a
/// thread of their own, so that a slow application never blocks the main thread; the C callback
/// does no work except hop to the queue. It is deliberately not isolated to any actor: an isolated
/// callback traps when the system calls it from another thread.
final class SystemFocusEvents: FocusEventSource, @unchecked Sendable {
    private struct Observed {
        var pid: pid_t
        var observer: AXObserver
        var application: AXUIElement
    }

    private let queue = DispatchQueue(label: "io.damao.piccolo.focus-events")
    private let logger = Logger(subsystem: "io.damao.piccolo", category: "focus")
    // Everything below is only touched on `queue`.
    private var onChange: (@Sendable () -> Void)?
    private var observed: Observed?
    private var runLoop: CFRunLoop?
    private var workspaceObservers: [any NSObjectProtocol] = []

    func start(onChange: @escaping @Sendable () -> Void) {
        queue.async {
            guard self.onChange == nil else { return }
            self.onChange = onChange
            self.subscribeToWorkspace()
            if let pid = FrontmostApplication.current()?.pid {
                self.observe(pid: pid)
            }
        }
    }

    // MARK: Workspace

    private func subscribeToWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        // The handlers run on the thread that posts the notification (the main thread); they only
        // read the pid and hop to the queue.
        workspaceObservers = [
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
            ) { [self] note in
                let pid = Self.processIdentifier(in: note)
                queue.async {
                    if let pid { self.observe(pid: pid) }
                    self.onChange?()
                }
            },
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil
            ) { [self] note in
                let pid = Self.processIdentifier(in: note)
                queue.async {
                    if let pid, self.observed?.pid == pid { self.stopObserving() }
                    self.onChange?()
                }
            },
            center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil
            ) { [self] _ in
                queue.async { self.onChange?() }
            },
        ]
    }

    private static func processIdentifier(in note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
            .processIdentifier
    }

    // MARK: Accessibility

    /// Observes the focused window and main window of `pid`, and no other application.
    ///
    /// An application that has only just launched may not accept an observer yet. A failure is
    /// retried a few times, for as long as the application stays active, and a successful retry
    /// looks again, because focus may have changed in the meantime.
    private func observe(pid: pid_t, attempt: Int = 0) {
        if observed?.pid == pid { return }
        stopObserving()
        guard pid != ProcessInfo.processInfo.processIdentifier, AXIsProcessTrusted() else { return }

        if let failure = install(pid: pid) {
            logger.notice(
                "cannot observe pid \(pid, privacy: .public) (attempt \(attempt + 1, privacy: .public)): \(failure, privacy: .public)"
            )
            guard attempt < Self.retryDelays.count else { return }
            queue.asyncAfter(deadline: .now() + Self.retryDelays[attempt]) { [self] in
                guard observed?.pid != pid, FrontmostApplication.current()?.pid == pid else { return }
                observe(pid: pid, attempt: attempt + 1)
                if observed?.pid == pid { onChange?() }
            }
        }
    }

    /// Seconds to wait before each retry of ``observe(pid:attempt:)``.
    private static let retryDelays: [TimeInterval] = [0.2, 0.5, 1, 2, 4]

    /// Installs the observer for `pid`. Returns why it could not, or `nil` on success.
    private func install(pid: pid_t) -> String? {
        var created: AXObserver?
        let createError = AXObserverCreate(pid, focusChanged, &created)
        guard createError == .success, let observer = created else {
            return "AXObserverCreate failed with AXError \(createError.rawValue)"
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 1)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]
        for notification in notifications {
            let error = AXObserverAddNotification(observer, application, notification as CFString, refcon)
            guard error == .success || error == .notificationAlreadyRegistered else {
                for added in notifications {
                    _ = AXObserverRemoveNotification(observer, application, added as CFString)
                }
                return "adding \(notification) failed with AXError \(error.rawValue)"
            }
        }

        CFRunLoopAddSource(
            observerRunLoop(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.commonModes)
        observed = Observed(pid: pid, observer: observer, application: application)
        return nil
    }

    private func stopObserving() {
        guard let previous = observed else { return }
        observed = nil
        for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            // Fails for an application that is gone, which is fine.
            _ = AXObserverRemoveNotification(
                previous.observer, previous.application, notification as CFString)
        }
        if let runLoop {
            CFRunLoopRemoveSource(
                runLoop, AXObserverGetRunLoopSource(previous.observer), CFRunLoopMode.commonModes)
        }
    }

    /// Called by the C callback, on the observer thread.
    fileprivate func accessibilityEvent() {
        queue.async { self.onChange?() }
    }

    /// The run loop of the observer thread, which is started on first use.
    private func observerRunLoop() -> CFRunLoop {
        if let runLoop { return runLoop }
        let loop = ObserverThread.start()
        runLoop = loop
        return loop
    }
}

/// The callback of the Accessibility observer. A plain function: it captures nothing and is isolated
/// to nothing.
private func focusChanged(
    observer: AXObserver, element: AXUIElement, notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<SystemFocusEvents>.fromOpaque(refcon).takeUnretainedValue().accessibilityEvent()
}

/// A thread that does nothing but run a run loop, for Accessibility notifications to arrive on.
private enum ObserverThread {
    private final class Box: @unchecked Sendable {
        var runLoop: CFRunLoop?
    }

    static func start() -> CFRunLoop {
        let box = Box()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.runLoop = CFRunLoopGetCurrent()
            // A run loop with no source returns at once; this one only keeps it alive.
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, CFRunLoopMode.defaultMode)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "io.damao.piccolo.focus-observer"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
        // Set before `ready` was signalled, and never changed afterwards.
        return box.runLoop!
    }
}
