import PiccoloCore

/// Why the system refused to register a shortcut, in words for a log line or an issue list.
public struct HotkeyRefusal: Error, Equatable, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

/// The calls a ``HotkeyRegistrar`` makes into the system, so that its replace and failure logic
/// runs against a fake in tests. ``CarbonHotkeyBackend`` is the real one.
///
/// Everything happens on the main thread: that is where Carbon delivers hotkey events.
@MainActor
public protocol HotkeyBackend: AnyObject {
    /// Called with the `hotkeyID` given to ``register(_:hotkeyID:)`` each time that shortcut is
    /// pressed. The backend calls it on the main thread.
    var onPress: (@MainActor (UInt32) -> Void)? { get set }

    /// Registers `shortcut` as a global hotkey under `hotkeyID`, a number the caller chose.
    ///
    /// - Throws: ``HotkeyRefusal`` when the system will not take the shortcut. Nothing is
    ///   registered then.
    func register(_ shortcut: Shortcut, hotkeyID: UInt32) throws(HotkeyRefusal)

    /// Releases the shortcut registered under `hotkeyID`. An unknown ID does nothing.
    func unregister(hotkeyID: UInt32)
}
