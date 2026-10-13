import Foundation
import PiccoloCore

/// Keeps the set of global hotkeys in step with a list of registrations.
///
/// ``apply(_:handler:)`` replaces everything at once, so the caller never has to work out what
/// changed. Pressing a registered shortcut calls the handler with the ID of its binding, on the
/// main thread. The handler must return quickly: it runs inside the system's hotkey dispatch.
@MainActor
public final class HotkeyRegistrar {
    /// A shortcut the system refused, and why. The other shortcuts of the same ``apply(_:handler:)``
    /// are registered regardless.
    public struct Refusal: Equatable, Sendable {
        public let id: UUID
        public let reason: String

        public init(id: UUID, reason: String) {
            self.id = id
            self.reason = reason
        }
    }

    private struct Active {
        let hotkeyID: UInt32
        let registration: ShortcutPlan.Registration
    }

    private let backend: any HotkeyBackend
    private var active: [Active] = []
    private var handler: (@MainActor (UUID) -> Void)?
    /// The numbers handed to the backend are never reused, so that a press the system queued for
    /// a shortcut that has since been replaced cannot be mistaken for a new one.
    private var nextHotkeyID: UInt32 = 1

    public init(backend: any HotkeyBackend) {
        self.backend = backend
        backend.onPress = { [weak self] hotkeyID in
            self?.pressed(hotkeyID)
        }
    }

    /// The shortcuts that are registered right now, in the order they were given to ``apply(_:handler:)``.
    public var registered: [ShortcutPlan.Registration] {
        active.map(\.registration)
    }

    /// Replaces all registrations with `registrations`.
    ///
    /// Every earlier registration is released first, then each shortcut is registered in order.
    /// Afterwards ``registered`` holds exactly the shortcuts the system accepted. An empty list
    /// releases everything.
    ///
    /// - Parameter handler: Called on the main thread with the binding ID when its shortcut is
    ///   pressed. It replaces the previous handler.
    /// - Returns: The shortcuts the system refused, in input order.
    @discardableResult
    public func apply(
        _ registrations: [ShortcutPlan.Registration],
        handler: @escaping @MainActor (UUID) -> Void
    ) -> [Refusal] {
        for entry in active {
            backend.unregister(hotkeyID: entry.hotkeyID)
        }
        active = []
        self.handler = handler

        var refusals: [Refusal] = []
        for registration in registrations {
            let hotkeyID = nextHotkeyID
            nextHotkeyID &+= 1
            do {
                try backend.register(registration.shortcut, hotkeyID: hotkeyID)
                active.append(Active(hotkeyID: hotkeyID, registration: registration))
            } catch {
                refusals.append(Refusal(id: registration.id, reason: error.reason))
            }
        }
        return refusals
    }

    private func pressed(_ hotkeyID: UInt32) {
        guard let entry = active.first(where: { $0.hotkeyID == hotkeyID }) else { return }
        handler?(entry.registration.id)
    }
}
