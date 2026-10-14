import AppKit

/// Tells when the system goes away from under a held shortcut: it sleeps, the screen locks, the
/// session is switched away. The key-up of the shortcut may never reach Piccolo then, and a hold that
/// waits for it would keep the preview on screen and a temporary Escape registered. The shortcut
/// manager ends its hold (cancel-all) when the source calls the handler. ``SystemHoldInterruptions`` is
/// the real one; tests use a source of their own.
@MainActor
public protocol HoldInterruptionSource: AnyObject {
    /// Calls `handler`, on the main actor, each time the hold has to end. A second call replaces the
    /// handler of the first.
    func start(_ handler: @escaping @MainActor () -> Void)
}

/// The system's own notifications:
///
/// - `NSWorkspace` posts ``workspaceNames`` on its notification center: the Mac is about to sleep or to
///   power off, the displays went to sleep, the session is no longer the active one (fast user
///   switching, or the login window taking over).
/// - The screen being locked is announced on the distributed notification center as
///   `com.apple.screenIsLocked` (the name `loginwindow` posts; the `sessionagent` variant is listed
///   too). The workspace has no notification for a lock, so this is the only way to hear it.
///
/// The centers are parameters, so that a test posts the notifications into plain ones.
@MainActor
public final class SystemHoldInterruptions: HoldInterruptionSource {
    public nonisolated static let workspaceNames: [Notification.Name] = [
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.willPowerOffNotification,
    ]

    public nonisolated static let distributedNames: [Notification.Name] = [
        Notification.Name("com.apple.screenIsLocked"),
        Notification.Name("com.apple.sessionagent.screenIsLocked"),
    ]

    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    public init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
    }

    isolated deinit {
        stop()
    }

    public func start(_ handler: @escaping @MainActor () -> Void) {
        stop()
        for (center, names) in [(workspaceCenter, Self.workspaceNames), (distributedCenter, Self.distributedNames)] {
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated(handler)
                }
                observers.append((center, token))
            }
        }
    }

    private func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
    }
}
