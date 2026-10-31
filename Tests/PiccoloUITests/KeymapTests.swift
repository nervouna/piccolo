import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

@Suite("Keymap")
struct KeymapTests {
    private let english = AppLanguage.en.textBundle!

    private func make(_ bindings: [KeyBinding], _ query: String = "") -> [KeymapGroup] {
        Keymap.make(bindings: bindings, query: query, bundle: english) { code in
            ["0": "a"][String(code)]
        }
    }

    private func binding(_ action: Action, _ shortcut: Shortcut? = nil) -> KeyBinding {
        KeyBinding(action: action, shortcut: shortcut)
    }

    private func rows(_ section: KeymapSection, in groups: [KeymapGroup]) -> [KeymapRow] {
        groups.first { $0.section == section }?.rows ?? []
    }

    private let arrow = Shortcut(keyCode: 123, modifiers: [.control, .option])  // ⌃⌥←
    private let leftHalfRow = KeymapRowID.builtIn(.placeWindow(.preset(.leftHalf)))
    private let grid = Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))
    private let area = Action.placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)))

    // MARK: Sections and rows

    @Test("an empty config has the nine sections in order, every built-in row unbound, and no layout rows")
    func emptyConfig() {
        let groups = make([])

        #expect(groups.map(\.section) == KeymapSection.allCases)
        #expect(
            groups.map(\.rows.count) == [4, 4, 5, 3, 6, 0, 4, 4, 0],
            "the rows per section are \(groups.map(\.rows.count))")
        let builtIn = groups.flatMap(\.rows)
        #expect(builtIn.map(\.id) == BuiltInActions.all.map { KeymapRowID.builtIn($0) })
        #expect(builtIn.map(\.action) == BuiltInActions.all)
        #expect(builtIn.allSatisfy { $0.bindings.isEmpty && !$0.isEditable })
    }

    @Test("a row is named by the summary of its action")
    func rowNames() {
        let groups = make([])
        #expect(rows(.halves, in: groups).map(\.name) == ["Left Half", "Right Half", "Top Half", "Bottom Half"])
        #expect(
            rows(.thirds, in: groups).map(\.name)
                == ["Left Third", "Center Third", "Right Third", "Left Two Thirds", "Right Two Thirds"])
        #expect(rows(.other, in: groups).map(\.name) == ["Maximize", "Center", "Restore Window"])
        #expect(
            rows(.displays, in: groups).map(\.name)
                == [
                    "Next Display", "Previous Display", "Display to the Left", "Display to the Right",
                    "Display Above", "Display Below",
                ])
        #expect(
            rows(.dividers, in: groups).map(\.name)
                == ["Move Divider Left", "Move Divider Right", "Move Divider Up", "Move Divider Down"])
        #expect(
            rows(.swaps, in: groups).map(\.name)
                == ["Swap Window Left", "Swap Window Right", "Swap Window Up", "Swap Window Down"])
    }

    @Test("a built-in row holds every binding with its action, in file order, bound or not")
    func builtInRowBindings() {
        let first = binding(.placeWindow(.preset(.leftHalf)), arrow)
        let other = binding(.placeWindow(.preset(.rightHalf)), Shortcut(keyCode: 124, modifiers: [.control]))
        let second = binding(.placeWindow(.preset(.leftHalf)), Shortcut(keyCode: 0, modifiers: [.command]))
        let unbound = binding(.placeWindow(.preset(.leftHalf)))

        let groups = make([first, other, second, unbound])

        let left = rows(.halves, in: groups)[0]
        #expect(left.id == .builtIn(.placeWindow(.preset(.leftHalf))))
        #expect(left.bindings.map(\.id) == [first.id, second.id, unbound.id])
        #expect(left.primaryBinding?.id == first.id)
        #expect(rows(.halves, in: groups)[1].bindings.map(\.id) == [other.id])
        #expect(rows(.halves, in: groups)[2].bindings.isEmpty)
    }

    @Test("a built-in binding without a shortcut is in its row and counts as no shortcut")
    func bindingWithoutShortcut() {
        let unbound = binding(.moveToDisplay(.next))

        let groups = make([unbound])

        let row = rows(.displays, in: groups)[0]
        #expect(row.bindings == [unbound])
        #expect(row.shortcut == nil)
        // No shortcut text to find: an empty-looking query part never matches it.
        #expect(make([unbound], "⌃").isEmpty)
    }

    @Test("grids and custom areas have one editable row per binding, in file order")
    func layoutRows() {
        let leftHalf = binding(.placeWindow(.preset(.leftHalf)))
        let secondGrid = binding(.arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), arrow)
        let firstGrid = binding(grid)
        let firstArea = binding(area)
        let secondArea = binding(.placeWindow(.custom(FractionalRect(x: 0, y: 0, width: 0.5, height: 0.5))))

        let groups = make([secondGrid, leftHalf, firstArea, firstGrid, secondArea])

        let grids = rows(.grids, in: groups)
        #expect(grids.map(\.id) == [.layout(secondGrid.id), .layout(firstGrid.id)])
        #expect(grids.map(\.action) == [secondGrid.action, firstGrid.action])
        #expect(grids.map(\.name) == ["Arrange 2 in 1 × 2", "Arrange 4 in 2 × 2"])
        #expect(grids.map(\.bindings) == [[secondGrid], [firstGrid]])
        #expect(grids.allSatisfy { $0.isEditable })

        let areas = rows(.customAreas, in: groups)
        #expect(areas.map(\.id) == [.layout(firstArea.id), .layout(secondArea.id)])
        #expect(areas.map(\.name) == ["Custom (25%, 0%, 50% × 100%)", "Custom (0%, 0%, 50% × 50%)"])
        #expect(areas.allSatisfy { $0.isEditable })

        // The built-in rows do not take layout bindings.
        #expect(rows(.halves, in: groups)[0].bindings == [leftHalf])
        #expect(groups.map(\.section) == KeymapSection.allCases)
    }

    @Test("the row of a binding is found by its ID, and a layout ID of a built-in binding finds none")
    func rowLookup() {
        let leftHalf = binding(.placeWindow(.preset(.leftHalf)), arrow)
        let gridBinding = binding(grid)
        let bindings = [leftHalf, gridBinding]

        let left = Keymap.row(.builtIn(.placeWindow(.preset(.leftHalf))), in: bindings, bundle: english)
        #expect(left?.bindings == [leftHalf])
        #expect(Keymap.row(.builtIn(.restoreWindow), in: bindings, bundle: english)?.bindings == [])
        let layout = Keymap.row(.layout(gridBinding.id), in: bindings, bundle: english)
        #expect(layout?.action == grid)
        #expect(layout?.isEditable == true)

        #expect(Keymap.row(.layout(leftHalf.id), in: bindings, bundle: english) == nil)
        #expect(Keymap.row(.layout(UUID()), in: bindings, bundle: english) == nil)
        #expect(Keymap.row(.builtIn(grid), in: bindings, bundle: english) == nil)
    }

    @Test("the row ID of a binding is its action for a built-in one and its own ID for a layout")
    func rowIDOfBinding() {
        let leftHalf = binding(.placeWindow(.preset(.leftHalf)))
        let gridBinding = binding(grid)
        let areaBinding = binding(area)
        #expect(KeymapRowID(leftHalf) == .builtIn(.placeWindow(.preset(.leftHalf))))
        #expect(KeymapRowID(gridBinding) == .layout(gridBinding.id))
        #expect(KeymapRowID(areaBinding) == .layout(areaBinding.id))
    }

    // MARK: Row names

    @Test("the names of the built-in rows are the control channel's: placeWindow.<preset>, moveToDisplay.<direction>, ...")
    func builtInRowNames() {
        let names = BuiltInActions.all.map { KeymapRowID.builtIn($0).name }
        #expect(
            names == [
                "placeWindow.leftHalf", "placeWindow.rightHalf", "placeWindow.topHalf", "placeWindow.bottomHalf",
                "placeWindow.topLeft", "placeWindow.topRight", "placeWindow.bottomLeft", "placeWindow.bottomRight",
                "placeWindow.leftThird", "placeWindow.centerThird", "placeWindow.rightThird",
                "placeWindow.leftTwoThirds", "placeWindow.rightTwoThirds", "placeWindow.maximize",
                "placeWindow.center", "restoreWindow",
                "moveToDisplay.next", "moveToDisplay.previous", "moveToDisplay.left", "moveToDisplay.right",
                "moveToDisplay.up", "moveToDisplay.down",
                "moveDivider.left", "moveDivider.right", "moveDivider.up", "moveDivider.down",
                "swapWindow.left", "swapWindow.right", "swapWindow.up", "swapWindow.down",
            ])
    }

    @Test("a layout row is named by its binding's UUID")
    func layoutRowName() {
        let id = UUID()
        #expect(KeymapRowID.layout(id).name == id.uuidString)
    }

    @Test("a name finds its row ID again, and an unknown name finds none")
    func rowNameRoundTrip() {
        for action in BuiltInActions.all {
            let row = KeymapRowID.builtIn(action)
            #expect(KeymapRowID(name: row.name) == row, "\(row.name)")
        }
        let id = UUID()
        #expect(KeymapRowID(name: id.uuidString) == .layout(id))
        #expect(KeymapRowID(name: id.uuidString.lowercased()) == .layout(id))
        #expect(KeymapRowID(name: "placeWindow.nowhere") == nil)
        #expect(KeymapRowID(name: "arrangeGrid") == nil)
        #expect(KeymapRowID(name: "") == nil)
    }

    @Test("row IDs are hashable, and equal IDs are one key")
    func rowIDsHash() {
        let id = UUID()
        let set: Set<KeymapRowID> = [
            .builtIn(.restoreWindow), .builtIn(.restoreWindow), .layout(id), .layout(id),
            .builtIn(.placeWindow(.preset(.leftHalf))),
        ]
        #expect(set.count == 3)
    }

    // MARK: Search

    @Test("the query matches the name without regard to case, and a section left without a row is left out")
    func nameMatch() {
        let groups = make([], "LEFT hal")

        #expect(groups.map(\.section) == [.halves])
        #expect(groups[0].rows.map(\.name) == ["Left Half"])
    }

    @Test("the query is trimmed, and a query of only whitespace is the empty query")
    func trimmedQuery() {
        #expect(make([], "  left half \n").flatMap(\.rows).map(\.name) == ["Left Half"])
        #expect(make([], "  \t").map(\.section) == KeymapSection.allCases)
    }

    @Test("the query ignores diacritics in both directions")
    func diacritics() {
        let french = AppLanguage.fr.textBundle!
        let name = ActionSummary.text(for: .placeWindow(.preset(.leftHalf)), bundle: french)
        let plain = name.folding(options: .diacriticInsensitive, locale: nil)
        let hit = Keymap.make(bindings: [], query: plain.uppercased(), bundle: french)
        #expect(hit.flatMap(\.rows).map(\.name).contains(name))

        // An accented query finds an unaccented name.
        #expect(make([], "Lèft Hàlf").flatMap(\.rows).map(\.name) == ["Left Half"])
    }

    @Test("the query matches the text of a shortcut, of any binding of the row")
    func shortcutMatch() {
        let first = binding(.placeWindow(.preset(.leftHalf)), arrow)
        let second = binding(.placeWindow(.preset(.leftHalf)), Shortcut(keyCode: 0, modifiers: [.command, .option]))
        let other = binding(.moveToDisplay(.next), Shortcut(keyCode: 0, modifiers: [.control]))

        #expect(make([first, second, other], "⌃⌥←").flatMap(\.rows).map(\.id) == [leftHalfRow])
        #expect(make([first, second, other], "⌥⌘a").flatMap(\.rows).map(\.id) == [leftHalfRow])
        #expect(make([first, second, other], "⌃a").flatMap(\.rows).map(\.id) == [.builtIn(.moveToDisplay(.next))])
    }

    @Test("a matching layout row stays with its section, and the others of the section are left out")
    func layoutRowMatch() {
        let match = binding(grid, arrow)
        let nonMatch = binding(.arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)))
        let matchingArea = binding(area)

        let byName = make([match, nonMatch, matchingArea], "4 in 2")
        #expect(byName.map(\.section) == [.grids])
        #expect(byName[0].rows.map(\.id) == [.layout(match.id)])

        let byShortcut = make([match, nonMatch, matchingArea], "⌃⌥←")
        #expect(byShortcut.flatMap(\.rows).map(\.id).contains(.layout(match.id)))
        #expect(!byShortcut.flatMap(\.rows).map(\.id).contains(.layout(nonMatch.id)))

        let custom = make([match, nonMatch, matchingArea], "Custom")
        #expect(custom.map(\.section) == [.customAreas])
        #expect(custom[0].rows.map(\.id) == [.layout(matchingArea.id)])
    }

    @Test("with an empty query the grids and custom areas are present without rows; with a query they are not")
    func emptySectionsOnlyWithoutQuery() {
        #expect(rows(.grids, in: make([])).isEmpty)
        #expect(make([]).contains { $0.section == .grids })
        #expect(make([]).contains { $0.section == .customAreas })

        #expect(make([], "xyz-nothing").isEmpty)
        #expect(!make([], "Left").contains { $0.section == .grids || $0.section == .customAreas })
    }
}
