import AppKit
import Foundation
import Testing

@testable import PiccoloSystem

/// What ends a hold when the system goes away: the notifications it posts when it sleeps, powers off,
/// locks the screen or switches the session away. The live source listens to the workspace's and the
/// distributed notification centers; here it listens to two plain ones, in which the tests post the
/// notifications, so that the names and the wiring are the real ones.
@MainActor
@Suite("System hold interruptions")
struct SystemHoldInterruptionsTests {
    private final class Count {
        var value = 0
    }

    private let workspace = NotificationCenter()
    private let distributed = NotificationCenter()
    private let count = Count()

    private func source() -> SystemHoldInterruptions {
        SystemHoldInterruptions(workspaceCenter: workspace, distributedCenter: distributed)
    }

    private func started() -> SystemHoldInterruptions {
        let source = source()
        let count = count
        source.start { count.value += 1 }
        return source
    }

    /// Waits until the handler has been called `expected` times; notifications are delivered through
    /// the main queue.
    private func waitForCount(_ expected: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while count.value < expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("going to sleep, the displays sleeping, the session resigning and powering off each interrupt", arguments: [
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.willPowerOffNotification,
    ])
    func workspaceNotifications(name: Notification.Name) async throws {
        let source = started()
        workspace.post(name: name, object: nil)
        try await waitForCount(1)
        #expect(count.value == 1, "\(name.rawValue) did not interrupt")
        withExtendedLifetime(source) {}
    }

    @Test("the screen being locked interrupts", arguments: SystemHoldInterruptions.distributedNames)
    func lockNotifications(name: Notification.Name) async throws {
        let source = started()
        distributed.post(name: name, object: nil)
        try await waitForCount(1)
        #expect(count.value == 1, "\(name.rawValue) did not interrupt")
        withExtendedLifetime(source) {}
    }

    @Test("the lock notification is the one the system posts: com.apple.screenIsLocked")
    func lockNameIsTheSystemsOwn() {
        #expect(SystemHoldInterruptions.distributedNames.contains(Notification.Name("com.apple.screenIsLocked")))
    }

    @Test("other notifications do not interrupt")
    func otherNotifications() async throws {
        let source = started()
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        distributed.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        // A name of one center is not a name of the other.
        distributed.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)

        try await Task.sleep(for: .milliseconds(100))
        #expect(count.value == 0)
        withExtendedLifetime(source) {}
    }

    @Test("every notification interrupts again")
    func everyTime() async throws {
        let source = started()
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        try await waitForCount(3)
        #expect(count.value == 3)
        withExtendedLifetime(source) {}
    }

    @Test("a source that is gone interrupts no more")
    func goneSourceIsQuiet() async throws {
        var source: SystemHoldInterruptions? = started()
        source = nil
        _ = source
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)

        try await Task.sleep(for: .milliseconds(100))
        #expect(count.value == 0)
    }

    @Test("starting twice listens once")
    func startTwice() async throws {
        let source = source()
        let count = count
        source.start { count.value += 1 }
        source.start { count.value += 10 }

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await waitForCount(1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(count.value == 10, "only the handler of the second start is called, and once")
    }
}
