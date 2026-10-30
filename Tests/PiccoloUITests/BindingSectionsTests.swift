import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

@Suite("Binding sections")
struct BindingSectionsTests {
    private let english = AppLanguage.en.textBundle!

    private func binding(_ action: Action, _ shortcut: Shortcut? = nil) -> KeyBinding {
        KeyBinding(action: action, shortcut: shortcut)
    }

    private func make(_ bindings: [KeyBinding], _ query: String = "") -> [BindingSection] {
        BindingSections.make(bindings: bindings, query: query, bundle: english) { code in
            ["0": "a"][String(code)]
        }
    }

    private let arrow = Shortcut(keyCode: 123, modifiers: [.control, .option])  // ⌃⌥←

    @Test("sections follow the order of the kinds, and bindings keep the file order inside")
    func orderOfKinds() {
        let divider = binding(.moveDivider(.left))
        let grid = binding(.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))
        let right = binding(.placeWindow(.preset(.rightHalf)))
        let display = binding(.moveToDisplay(.next))
        let left = binding(.placeWindow(.preset(.leftHalf)))

        let sections = make([divider, grid, right, display, left])

        #expect(sections.map(\.kind) == [.placeWindow, .moveToDisplay, .arrangeGrid, .moveDivider])
        #expect(sections[0].bindings.map(\.id) == [right.id, left.id])
        #expect(sections[1].bindings.map(\.id) == [display.id])
    }

    @Test("a kind without a binding has no section")
    func emptySectionsAreHidden() {
        let sections = make([binding(.moveToDisplay(.next)), binding(.moveDivider(.up))])
        #expect(sections.map(\.kind) == [.moveToDisplay, .moveDivider])
        #expect(make([]).isEmpty)
    }

    @Test("the query matches the summary without regard to case, and hides sections left empty")
    func summaryMatch() {
        let left = binding(.placeWindow(.preset(.leftHalf)))
        let display = binding(.moveToDisplay(.next))

        let sections = make([left, display], "LEFT hal")

        #expect(sections.map(\.kind) == [.placeWindow])
        #expect(sections[0].bindings.map(\.id) == [left.id])
    }

    @Test("the query matches the shortcut text")
    func shortcutMatch() {
        let withArrow = binding(.placeWindow(.preset(.leftHalf)), arrow)
        let without = binding(.placeWindow(.preset(.rightHalf)))
        let letter = binding(.moveToDisplay(.next), Shortcut(keyCode: 0, modifiers: [.command, .option]))

        #expect(make([withArrow, without, letter], "⌃⌥←").flatMap(\.bindings).map(\.id) == [withArrow.id])
        #expect(make([withArrow, without, letter], "⌥⌘a").flatMap(\.bindings).map(\.id) == [letter.id])
    }

    @Test("the query ignores diacritics")
    func diacritics() {
        let french = AppLanguage.fr.textBundle!
        let binding = binding(.placeWindow(.preset(.leftHalf)))
        let summary = ActionSummary.text(for: binding.action, bundle: french)
        let plain = summary.folding(options: .diacriticInsensitive, locale: nil)
        let hit = BindingSections.make(bindings: [binding], query: plain.uppercased(), bundle: french)
        #expect(hit.flatMap(\.bindings).map(\.id) == [binding.id])

        // And the other way round: an accented query finds an unaccented text.
        let miss = BindingSections.make(bindings: [binding], query: "Lèft", bundle: english)
        #expect(miss.flatMap(\.bindings).map(\.id) == [binding.id])
    }

    @Test("whitespace around the query is ignored, and an empty query shows everything")
    func trimming() {
        let all = [binding(.placeWindow(.preset(.leftHalf))), binding(.moveToDisplay(.next))]
        #expect(make(all, "  left half \n").flatMap(\.bindings).count == 1)
        #expect(make(all, "   ").flatMap(\.bindings).count == 2)
        #expect(make(all, "").flatMap(\.bindings).count == 2)
    }

    @Test("a query nothing matches gives no section")
    func noMatch() {
        #expect(make([binding(.placeWindow(.preset(.leftHalf)))], "zzz").isEmpty)
    }

    @Test("the kinds have the names the config file writes")
    func configNames() {
        #expect(ActionKind.allCases.map(\.configName) == ["placeWindow", "moveToDisplay", "arrangeGrid", "moveDivider"])
    }
}
