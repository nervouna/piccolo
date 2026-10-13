import Carbon.HIToolbox
import Testing

@testable import PiccoloSystem

/// Only the part of the Carbon backend that does not talk to the system. Registering real
/// hotkeys is covered by the desktop acceptance tests.
@MainActor
@Suite("Carbon hotkey backend")
struct CarbonHotkeyBackendTests {
    @Test("a shortcut that is already taken says so, with the status code")
    func alreadyTaken() {
        let reason = CarbonHotkeyBackend.reason(forRegistrationStatus: OSStatus(eventHotKeyExistsErr))
        #expect(reason.contains("already taken"))
        #expect(reason.contains("\(eventHotKeyExistsErr)"))
    }

    @Test("an invalid shortcut says so, with the status code")
    func invalid() {
        let reason = CarbonHotkeyBackend.reason(forRegistrationStatus: OSStatus(eventHotKeyInvalidErr))
        #expect(reason.contains("invalid"))
        #expect(reason.contains("\(eventHotKeyInvalidErr)"))
    }

    @Test("any other status is reported with its code")
    func other() {
        let reason = CarbonHotkeyBackend.reason(forRegistrationStatus: -9868)
        #expect(reason.contains("-9868"))
    }
}
