import Foundation
import PiccoloCore

/// Keeps the set of global hotkeys in step with a list of registrations.
///
/// ``apply(_:onRelease:handler:)`` replaces everything at once, so the caller never has to work out
/// what changed. Pressing a registered shortcut calls the handler with the ID of its binding, and
/// letting go of its key calls the release handler, on the main thread. The handlers must return
/// quickly: they run inside the system's hotkey dispatch.
///
/// Besides the bindings there can be one temporary hotkey (``registerTemporary(_:onPress:)``): a
/// shortcut that is taken for a short while, such as Escape while a shortcut is held.
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

    private struct Temporary {
        let hotkeyID: UInt32
        let onPress: @MainActor () -> Void
    }

    private let backend: any HotkeyBackend
    private var active: [Active] = []
    private var temporary: Temporary?
    private var handler: (@MainActor (UUID) -> Void)?
    private var releaseHandler: (@MainActor (UUID) -> Void)?
    /// The numbers handed to the backend are never reused, so that a press the system queued for
    /// a shortcut that has since been replaced cannot be mistaken for a new one.
    private var nextHotkeyID: UInt32 = 1

    public init(backend: any HotkeyBackend) {
        self.backend = backend
        backend.onPress = { [weak self] hotkeyID in
            self?.pressed(hotkeyID)
        }
        backend.onRelease = { [weak self] hotkeyID in
            self?.released(hotkeyID)
        }
    }

    /// The shortcuts that are registered right now, in the order they were given to ``apply(_:handler:)``.
    public var registered: [ShortcutPlan.Registration] {
        active.map(\.registration)
    }

    /// Whether a temporary hotkey is registered right now.
    public var hasTemporary: Bool {
        temporary != nil
    }

    /// Replaces all registrations with `registrations`.
    ///
    /// Every earlier registration is released first, the temporary hotkey included, then each
    /// shortcut is registered in order. Afterwards ``registered`` holds exactly the shortcuts the
    /// system accepted. An empty list releases everything.
    ///
    /// - Parameters:
    ///   - onRelease: Called on the main thread with the binding ID when the key of its shortcut goes
    ///     up. It replaces the previous one; without it, releases are ignored.
    ///   - handler: Called on the main thread with the binding ID when its shortcut is pressed. It
    ///     replaces the previous handler.
    /// - Returns: The shortcuts the system refused, in input order.
    @discardableResult
    public func apply(
        _ registrations: [ShortcutPlan.Registration],
        onRelease: (@MainActor (UUID) -> Void)? = nil,
        handler: @escaping @MainActor (UUID) -> Void
    ) -> [Refusal] {
        unregisterTemporary()
        for entry in active {
            backend.unregister(hotkeyID: entry.hotkeyID)
        }
        active = []
        self.handler = handler
        self.releaseHandler = onRelease

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

    /// Registers `shortcut` for the time being, beside the bindings, until ``unregisterTemporary()``
    /// or the next ``apply(_:onRelease:handler:)``. Pressing it calls `onPress` and nothing else. At
    /// most one temporary hotkey exists: a second call releases the first.
    ///
    /// - Throws: ``HotkeyRefusal`` when the system will not take the shortcut, for example because a
    ///   binding has it. Nothing is registered then.
    public func registerTemporary(
        _ shortcut: Shortcut, onPress: @escaping @MainActor () -> Void
    ) throws(HotkeyRefusal) {
        unregisterTemporary()
        let hotkeyID = nextHotkeyID
        nextHotkeyID &+= 1
        try backend.register(shortcut, hotkeyID: hotkeyID)
        temporary = Temporary(hotkeyID: hotkeyID, onPress: onPress)
    }

    /// Releases the temporary hotkey. Does nothing when there is none.
    public func unregisterTemporary() {
        guard let entry = temporary else { return }
        temporary = nil
        backend.unregister(hotkeyID: entry.hotkeyID)
    }

    private func pressed(_ hotkeyID: UInt32) {
        if let temporary, temporary.hotkeyID == hotkeyID {
            temporary.onPress()
            return
        }
        guard let entry = active.first(where: { $0.hotkeyID == hotkeyID }) else { return }
        handler?(entry.registration.id)
    }

    private func released(_ hotkeyID: UInt32) {
        guard let entry = active.first(where: { $0.hotkeyID == hotkeyID }) else { return }
        releaseHandler?(entry.registration.id)
    }
}
