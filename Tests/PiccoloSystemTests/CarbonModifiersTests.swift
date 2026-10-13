import Testing

import PiccoloCore

@testable import PiccoloSystem

@Suite("Carbon modifier flags")
struct CarbonModifiersTests {
    // The values of cmdKey, shiftKey, optionKey and controlKey in Carbon.HIToolbox, written out:
    // they are a stable part of the system interface, and a typo in the mapping must not hide
    // behind the same constants being read twice.
    private static let command: UInt32 = 0x0100
    private static let shift: UInt32 = 0x0200
    private static let option: UInt32 = 0x0800
    private static let control: UInt32 = 0x1000

    @Test("each modifier maps to its own Carbon flag")
    func singleModifiers() {
        #expect(CarbonModifiers.flag(for: .command) == Self.command)
        #expect(CarbonModifiers.flag(for: .shift) == Self.shift)
        #expect(CarbonModifiers.flag(for: .option) == Self.option)
        #expect(CarbonModifiers.flag(for: .control) == Self.control)
    }

    @Test("the four flags are distinct single bits")
    func flagsAreDistinctBits() {
        let flags = Modifier.allCases.map { CarbonModifiers.flag(for: $0) }
        #expect(Set(flags).count == flags.count)
        #expect(flags.allSatisfy { $0.nonzeroBitCount == 1 })
    }

    @Test("no modifier gives no flags")
    func noModifiers() {
        #expect(CarbonModifiers.flags(for: []) == 0)
    }

    @Test("every combination of modifiers maps to the OR of its flags")
    func everyCombination() {
        let all = Modifier.allCases
        #expect(all.count == 4)

        var seen: Set<UInt32> = []
        for mask in 0..<(1 << all.count) {
            let modifiers = Set(all.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            var expected: UInt32 = 0
            if modifiers.contains(.command) { expected |= Self.command }
            if modifiers.contains(.shift) { expected |= Self.shift }
            if modifiers.contains(.option) { expected |= Self.option }
            if modifiers.contains(.control) { expected |= Self.control }

            let flags = CarbonModifiers.flags(for: modifiers)
            #expect(flags == expected, "modifiers \(modifiers.map(\.rawValue).sorted()) gave \(flags), expected \(expected)")
            seen.insert(flags)
        }
        // Different combinations never collide.
        #expect(seen.count == 16)
    }
}
