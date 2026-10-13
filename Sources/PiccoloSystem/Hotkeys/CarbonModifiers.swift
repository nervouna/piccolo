import Carbon.HIToolbox
import PiccoloCore

/// The modifier flags Carbon's `RegisterEventHotKey` takes.
public enum CarbonModifiers {
    /// The Carbon flag of one modifier (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    public static func flag(for modifier: Modifier) -> UInt32 {
        switch modifier {
        case .command: UInt32(cmdKey)
        case .option: UInt32(optionKey)
        case .control: UInt32(controlKey)
        case .shift: UInt32(shiftKey)
        }
    }

    /// The flags of all `modifiers` combined; 0 for none.
    public static func flags(for modifiers: Set<Modifier>) -> UInt32 {
        modifiers.reduce(0) { $0 | flag(for: $1) }
    }
}
