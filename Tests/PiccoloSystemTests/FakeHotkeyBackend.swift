import PiccoloCore

@testable import PiccoloSystem

/// A stand-in for the system's hotkey registry. Like the real one, it refuses a shortcut that is
/// already registered, so a registrar that registers before it releases fails against it.
@MainActor
final class FakeHotkeyBackend: HotkeyBackend {
    enum Call: Equatable {
        case register(Shortcut, hotkeyID: UInt32)
        case unregister(hotkeyID: UInt32)
    }

    var onPress: (@MainActor (UInt32) -> Void)?
    var onRelease: (@MainActor (UInt32) -> Void)?

    /// Shortcuts the "system" refuses whatever happens, with the reason it gives.
    private var refusals: [(shortcut: Shortcut, reason: String)] = []

    func refuse(_ shortcut: Shortcut, reason: String) {
        refusals.append((shortcut, reason))
    }

    private(set) var calls: [Call] = []
    /// What is registered right now, by the ID the registrar chose.
    private(set) var live: [UInt32: Shortcut] = [:]

    /// The shortcuts that are registered right now, in the order they were registered.
    var liveShortcuts: [Shortcut] {
        live.sorted { $0.key < $1.key }.map(\.value)
    }

    func register(_ shortcut: Shortcut, hotkeyID: UInt32) throws(HotkeyRefusal) {
        calls.append(.register(shortcut, hotkeyID: hotkeyID))
        if let refusal = refusals.first(where: { $0.shortcut == shortcut }) {
            throw HotkeyRefusal(reason: refusal.reason)
        }
        if live.values.contains(shortcut) {
            throw HotkeyRefusal(reason: "already registered")
        }
        live[hotkeyID] = shortcut
    }

    func unregister(hotkeyID: UInt32) {
        calls.append(.unregister(hotkeyID: hotkeyID))
        live[hotkeyID] = nil
    }

    /// The user presses `shortcut`. Nothing happens when it is not registered, as in the system.
    func press(_ shortcut: Shortcut) {
        guard let hotkeyID = live.first(where: { $0.value == shortcut })?.key else { return }
        onPress?(hotkeyID)
    }

    /// The user lets go of the key of `shortcut`. Nothing happens when it is not registered, as in the
    /// system.
    func release(_ shortcut: Shortcut) {
        guard let hotkeyID = live.first(where: { $0.value == shortcut })?.key else { return }
        onRelease?(hotkeyID)
    }

    /// The system delivers a release for `hotkeyID` that is no longer registered, for example one for
    /// a key that went down before the shortcut was replaced.
    func releaseStale(hotkeyID: UInt32) {
        onRelease?(hotkeyID)
    }

    /// The system delivers a press for `hotkeyID` that is no longer registered, for example one
    /// it had queued before the shortcut was released.
    func pressStale(hotkeyID: UInt32) {
        onPress?(hotkeyID)
    }

    /// The ID the registrar chose for `shortcut`.
    func hotkeyID(of shortcut: Shortcut) -> UInt32? {
        live.first(where: { $0.value == shortcut })?.key
    }
}
