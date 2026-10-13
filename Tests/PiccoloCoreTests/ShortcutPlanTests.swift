import Foundation
import Testing

@testable import PiccoloCore

@Suite("Shortcut plan")
struct ShortcutPlanTests {
    /// The part of the issue text that says what a registrable shortcut needs.
    private static let notRegistrableText = "command, option or control, or a function key"

    /// A key code that is not a function key (A).
    private let aKey = 0
    /// A key code that is not a function key (Space).
    private let spaceKey = 49

    private func shortcut(_ keyCode: Int, _ modifiers: Modifier...) -> Shortcut {
        Shortcut(keyCode: keyCode, modifiers: Set(modifiers))
    }

    /// A binding with a fresh ID. The action does not matter to the rules under test.
    private func binding(_ shortcut: Shortcut?) -> KeyBinding {
        KeyBinding(action: .moveDivider(.left), shortcut: shortcut)
    }

    /// The registration a binding with a shortcut must produce.
    private func registration(_ binding: KeyBinding) -> ShortcutPlan.Registration {
        ShortcutPlan.Registration(id: binding.id, shortcut: binding.shortcut!)
    }

    // MARK: Empty input and missing shortcuts

    @Test("no bindings give an empty plan")
    func noBindings() {
        let plan = ShortcutPlan.resolve([])
        #expect(plan.registrations.isEmpty)
        #expect(plan.issues.isEmpty)
    }

    @Test("bindings without a shortcut are skipped silently")
    func bindingsWithoutShortcut() {
        let plan = ShortcutPlan.resolve([binding(nil), binding(nil)])
        #expect(plan.registrations.isEmpty)
        #expect(plan.issues.isEmpty)
    }

    // MARK: Registration

    @Test("a registrable shortcut is registered under the ID of its binding")
    func registrableShortcut() {
        let bound = binding(shortcut(aKey, .command))
        let plan = ShortcutPlan.resolve([bound])
        #expect(plan.registrations == [registration(bound)])
        #expect(plan.issues.isEmpty)
    }

    @Test("a function key without modifiers is registered")
    func functionKeyWithoutModifiers() {
        let bound = binding(shortcut(FunctionKey.f5))
        let plan = ShortcutPlan.resolve([bound])
        #expect(plan.registrations == [registration(bound)])
        #expect(plan.issues.isEmpty)
    }

    // MARK: Shortcuts that cannot be registered

    @Test("shift with an ordinary key is skipped with an issue that names its index")
    func shiftOnlyIsSkipped() {
        let plan = ShortcutPlan.resolve([binding(shortcut(aKey, .shift))])
        #expect(plan.registrations.isEmpty)
        #expect(plan.issues.count == 1)
        #expect(plan.issues.first?.contains("bindings[0]") == true)
        #expect(plan.issues.first?.contains(Self.notRegistrableText) == true)
    }

    @Test("an ordinary key with no modifiers is skipped with an issue")
    func noModifiersIsSkipped() {
        let plan = ShortcutPlan.resolve([binding(shortcut(spaceKey))])
        #expect(plan.registrations.isEmpty)
        #expect(plan.issues.count == 1)
        #expect(plan.issues.first?.contains("bindings[0]") == true)
        #expect(plan.issues.first?.contains(Self.notRegistrableText) == true)
    }

    @Test("a shortcut that is not registrable never counts as a duplicate")
    func unregistrableIsNotAccepted() {
        // The third binding equals the first, but the first was never accepted, so the
        // third is reported for being unregistrable, not as a duplicate.
        let plan = ShortcutPlan.resolve([
            binding(shortcut(aKey, .shift)),
            binding(shortcut(aKey, .command)),
            binding(shortcut(aKey, .shift)),
        ])
        #expect(plan.registrations.count == 1)
        #expect(plan.issues.count == 2)
        #expect(plan.issues.first?.contains("bindings[0]") == true)
        #expect(plan.issues.last?.contains("bindings[2]") == true)
        #expect(plan.issues.allSatisfy { $0.contains(Self.notRegistrableText) })
        #expect(plan.issues.allSatisfy { !$0.contains("bindings[1]") })
    }

    // MARK: Duplicates

    @Test("a duplicate is skipped, the first one wins, and the issue names both indices")
    func duplicateFirstWins() {
        let first = binding(shortcut(aKey, .command))
        let second = binding(shortcut(spaceKey, .option))
        let duplicate = binding(shortcut(aKey, .command))
        let plan = ShortcutPlan.resolve([first, second, duplicate])
        #expect(plan.registrations == [registration(first), registration(second)])
        #expect(plan.issues.count == 1)
        #expect(plan.issues.first?.contains("bindings[2]") == true)
        #expect(plan.issues.first?.contains("bindings[0]") == true)
    }

    @Test("a duplicate function key is skipped and the issue names both indices")
    func duplicateFunctionKey() {
        let first = binding(shortcut(FunctionKey.f5))
        let duplicate = binding(shortcut(FunctionKey.f5))
        let plan = ShortcutPlan.resolve([first, duplicate])
        #expect(plan.registrations == [registration(first)])
        #expect(plan.issues.count == 1)
        #expect(plan.issues.first?.contains("bindings[1]") == true)
        #expect(plan.issues.first?.contains("bindings[0]") == true)
    }

    @Test("the same key with different modifier sets is accepted every time")
    func sameKeyDifferentModifiers() {
        let bindings = [
            binding(shortcut(aKey, .command)),
            binding(shortcut(aKey, .command, .shift)),
            binding(shortcut(aKey, .option)),
            binding(shortcut(aKey, .command, .option)),
            binding(shortcut(aKey, .control)),
        ]
        let plan = ShortcutPlan.resolve(bindings)
        #expect(plan.registrations == bindings.map { registration($0) })
        #expect(plan.issues.isEmpty)
    }

    // MARK: Mixed input

    @Test("a mix of every rule keeps binding order for registrations and issues")
    func mixedInput() {
        let command = binding(shortcut(aKey, .command))
        let f1 = binding(shortcut(FunctionKey.f1))
        let commandShift = binding(shortcut(aKey, .command, .shift))
        let shiftF1 = binding(shortcut(FunctionKey.f1, .shift))
        let controlOption = binding(shortcut(spaceKey, .control, .option))

        let plan = ShortcutPlan.resolve([
            binding(nil),
            command,
            binding(shortcut(spaceKey, .shift)),  // 2: not registrable
            f1,
            binding(shortcut(aKey, .command)),  // 4: duplicate of 1
            binding(nil),
            commandShift,
            shiftF1,
            binding(shortcut(FunctionKey.f1)),  // 8: duplicate of 3
            controlOption,
        ])

        #expect(
            plan.registrations == [
                registration(command),
                registration(f1),
                registration(commandShift),
                registration(shiftF1),
                registration(controlOption),
            ])

        let expectedFragments = [
            ["bindings[2]", Self.notRegistrableText],
            ["bindings[4]", "bindings[1]"],
            ["bindings[8]", "bindings[3]"],
        ]
        #expect(plan.issues.count == expectedFragments.count)
        for (issue, fragments) in zip(plan.issues, expectedFragments) {
            for fragment in fragments {
                #expect(issue.contains(fragment), "issue \"\(issue)\" must contain \(fragment)")
            }
        }
    }

    // MARK: Positions in the file

    @Test("without positions, the issues name the position in the list, as they always did")
    func listPositionsByDefault() {
        let first = binding(shortcut(aKey, .command))
        let duplicate = binding(shortcut(aKey, .command))
        let bindings = [binding(nil), first, duplicate]

        let plan = ShortcutPlan.resolve(bindings)

        #expect(
            plan.issues == [
                "bindings[2] has the same shortcut as bindings[1], which keeps it; bindings[2] is not registered"
            ])
        #expect(ShortcutPlan.resolve(bindings, sourceIndices: [:]) == plan)
    }

    @Test("with positions, every issue names the position in the file, not the position in the list")
    func filePositions() {
        // The file had a binding at index 1 that was skipped, so each position is one more than
        // the list position of the binding that follows the gap.
        let command = binding(shortcut(aKey, .command))  // file 0
        let shiftA = binding(shortcut(aKey, .shift))  // file 2: not registrable
        let f2 = binding(shortcut(FunctionKey.f2))  // file 3
        let f2Duplicate = binding(shortcut(FunctionKey.f2))  // file 4
        let positions = [command.id: 0, shiftA.id: 2, f2.id: 3, f2Duplicate.id: 4]

        let plan = ShortcutPlan.resolve([command, shiftA, f2, f2Duplicate], sourceIndices: positions)

        #expect(plan.registrations == [registration(command), registration(f2)])
        #expect(
            plan.issues == [
                "bindings[2] shortcut needs command, option or control, or a function key; it is not registered",
                "bindings[4] has the same shortcut as bindings[3], which keeps it; bindings[4] is not registered",
            ])
    }

    @Test("a binding missing from the positions is named by its position in the list")
    func missingPositionFallsBack() {
        let first = binding(shortcut(FunctionKey.f5))
        let duplicate = binding(shortcut(FunctionKey.f5))

        let plan = ShortcutPlan.resolve([first, duplicate], sourceIndices: [first.id: 7])

        #expect(
            plan.issues == [
                "bindings[1] has the same shortcut as bindings[7], which keeps it; bindings[1] is not registered"
            ])
    }
}
