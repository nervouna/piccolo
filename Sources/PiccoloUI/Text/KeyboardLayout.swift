import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// The characters keys produce on the current keyboard layout.
///
/// The Text Input Sources API must be used from the main thread: asking it from another one
/// stops the process.
@MainActor
public enum KeyboardLayout {
    /// The character that the key `keyCode` produces on the current keyboard layout without
    /// modifiers, or `nil` when it produces none (or the layout has no character data).
    ///
    /// The layout is the one selected, not the input method: with a Chinese input method on, the
    /// keyboard layout under it (ABC, U.S.) is read. A layout without character data, such as
    /// some input methods, gives way to the most recent ASCII-capable layout.
    public static func character(forKeyCode keyCode: Int) -> String? {
        guard let code = UInt16(exactly: keyCode), let layout = layoutData() else { return nil }

        var deadKeyState: UInt32 = 0
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        let status: OSStatus = layout.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                code,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                buffer.count,
                &length,
                &buffer)
        }
        guard status == noErr, length > 0 else { return nil }

        let text = String(utf16CodeUnits: buffer, count: length)
        // Keys without a visible character answer with control characters.
        guard text.unicodeScalars.contains(where: { !$0.properties.generalCategory.isControlOrSeparator })
        else { return nil }
        return text
    }

    private static func layoutData() -> Data? {
        for source in [
            TISCopyCurrentKeyboardLayoutInputSource(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource(),
        ] {
            guard let layout = source?.takeRetainedValue() else { continue }
            if let property = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) {
                let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
                return data as Data
            }
        }
        return nil
    }
}

extension Unicode.GeneralCategory {
    fileprivate var isControlOrSeparator: Bool {
        switch self {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .unassigned:
            true
        default:
            false
        }
    }
}
