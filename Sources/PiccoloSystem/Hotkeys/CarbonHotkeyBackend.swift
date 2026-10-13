import Carbon.HIToolbox
import Foundation
import PiccoloCore

/// Registers global hotkeys with Carbon's `RegisterEventHotKey`.
///
/// Carbon is the only public API for global hotkeys that needs no extra permission: the system
/// itself watches the keyboard and tells the app that registered a shortcut when it is pressed,
/// without the app seeing any other key. Events arrive on the main thread, through an event
/// handler installed on the application event target.
@MainActor
public final class CarbonHotkeyBackend: HotkeyBackend {
    public var onPress: (@MainActor (UInt32) -> Void)?

    private var references: [UInt32: EventHotKeyRef] = [:]
    private var handlerReference: EventHandlerRef?
    /// What the C callback talks to. The event handler owns one retain of it, balanced in
    /// `deinit`.
    private var sink: Unmanaged<HotkeySink>?

    public init() {}

    isolated deinit {
        for reference in references.values {
            UnregisterEventHotKey(reference)
        }
        if let handlerReference {
            RemoveEventHandler(handlerReference)
        }
        sink?.release()
    }

    public func register(_ shortcut: Shortcut, hotkeyID: UInt32) throws(HotkeyRefusal) {
        guard let keyCode = UInt32(exactly: shortcut.keyCode) else {
            throw HotkeyRefusal(reason: "key code \(shortcut.keyCode) is out of range")
        }
        try installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            CarbonModifiers.flags(for: shortcut.modifiers),
            EventHotKeyID(signature: hotkeySignature, id: hotkeyID),
            GetApplicationEventTarget(),
            OptionBits(0),
            &reference)
        guard status == noErr, let reference else {
            throw HotkeyRefusal(reason: Self.reason(forRegistrationStatus: status))
        }
        references[hotkeyID] = reference
    }

    public func unregister(hotkeyID: UInt32) {
        guard let reference = references.removeValue(forKey: hotkeyID) else { return }
        UnregisterEventHotKey(reference)
    }

    /// A line for an issue list that says what `RegisterEventHotKey` answered.
    static func reason(forRegistrationStatus status: OSStatus) -> String {
        switch Int(status) {
        case eventHotKeyExistsErr:
            "the system reports the shortcut as already taken, by the system or by another app (OSStatus \(status))"
        case eventHotKeyInvalidErr:
            "the system rejects the shortcut as invalid (OSStatus \(status))"
        default:
            "the system refused the shortcut (OSStatus \(status))"
        }
    }

    // MARK: Event handler

    private func installHandlerIfNeeded() throws(HotkeyRefusal) {
        guard handlerReference == nil else { return }

        // The callback cannot capture, so it reaches this object through a sink that the event
        // handler carries as its user data. The sink only ever hops to the main thread.
        let sink = HotkeySink { [weak self] hotkeyID in
            Self.runOnMainThread { self?.onPress?(hotkeyID) }
        }
        let retained = Unmanaged.passRetained(sink)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(), carbonHotkeyCallback, 1, &eventType,
            retained.toOpaque(), &reference)
        guard status == noErr, let reference else {
            retained.release()
            throw HotkeyRefusal(
                reason: "the hotkey event handler could not be installed (OSStatus \(status))")
        }
        self.sink = retained
        handlerReference = reference
    }

    /// Runs `work` on the main thread: at once when already there, so that the order of key
    /// presses is kept, otherwise as soon as the main queue gets to it.
    private nonisolated static func runOnMainThread(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated(work)
            }
        }
    }
}

/// Marks the hotkeys of this app in the `EventHotKeyID` of an event: 'PCLO'.
private let hotkeySignature: OSType = 0x5043_4C4F

/// Carries the hotkey ID from the C callback to the backend. Immutable, so it can be used from
/// whatever thread the system calls back on.
private final class HotkeySink: Sendable {
    let deliver: @Sendable (UInt32) -> Void

    init(deliver: @escaping @Sendable (UInt32) -> Void) {
        self.deliver = deliver
    }
}

/// The Carbon event handler. A C function pointer: it captures nothing, and it is not isolated
/// to the main actor, because the system decides which thread calls it. It reads the hotkey ID
/// out of the event and passes it on; the hop to the main thread is explicit, in the sink.
private let carbonHotkeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    guard hotKeyID.signature == hotkeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    Unmanaged<HotkeySink>.fromOpaque(userData).takeUnretainedValue().deliver(hotKeyID.id)
    return noErr
}
