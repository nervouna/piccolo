import Observation
import PiccoloSystem

/// Observable Accessibility trust state for the menu.
@MainActor
@Observable
final class AccessibilityStatus {
    /// The state the menu and the Settings window both show.
    static let shared = AccessibilityStatus()

    private(set) var isTrusted: Bool

    @ObservationIgnored private let permission: AccessibilityPermission
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(permission: AccessibilityPermission = AccessibilityPermission()) {
        self.permission = permission
        self.isTrusted = permission.isTrusted
    }

    /// Call once at launch. While the process is not trusted, shows the system
    /// prompt a single time and polls until the grant arrives, so the menu
    /// updates without a relaunch.
    func start() {
        guard !isTrusted, pollTask == nil else { return }
        permission.requestPrompt()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.refresh() { return }
            }
        }
    }

    /// Re-reads the trust state and returns it.
    @discardableResult
    private func refresh() -> Bool {
        isTrusted = permission.isTrusted
        return isTrusted
    }
}
