import CoreGraphics
import Testing

import PiccoloCore

@testable import PiccoloUI

@Suite("Action glyph kind")
struct ActionGlyphKindTests {
    @Test("a preset, a custom frame and a grid are windows on a small screen")
    func frames() {
        #expect(
            ActionGlyphKind(.placeWindow(.preset(.leftHalf)), fillOrder: .rows)
                == .frames([CGRect(x: 0, y: 0, width: 0.5, height: 1)]))
        let area = FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)
        #expect(
            ActionGlyphKind(.placeWindow(.custom(area)), fillOrder: .rows)
                == .frames([CGRect(x: 0.25, y: 0, width: 0.5, height: 1)]))
        #expect(
            ActionGlyphKind(.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)), fillOrder: .rows)
                == .frames([
                    CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                    CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                ]))
    }

    @Test("the cells of a grid are in the current fill order")
    func fillOrder() {
        let grid = Action.arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2))
        #expect(
            ActionGlyphKind(grid, fillOrder: .rows)
                == .frames([
                    CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                    CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
                ]))
        #expect(
            ActionGlyphKind(grid, fillOrder: .columns)
                == .frames([
                    CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                    CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
                ]))
    }

    @Test("a grid that cannot be drawn is an empty screen and does not crash")
    func impossibleGrid() {
        #expect(ActionGlyphKind(.arrangeGrid(GridSpec(count: 0, rows: 2, columns: 2)), fillOrder: .rows) == .frames([]))
    }

    @Test("the other actions have a mark of their own, with their direction")
    func marks() {
        for direction in DisplayDirection.allCases {
            #expect(ActionGlyphKind(.moveToDisplay(direction), fillOrder: .rows) == .display(direction))
        }
        for direction in Direction.allCases {
            #expect(ActionGlyphKind(.moveDivider(direction), fillOrder: .rows) == .divider(direction))
            #expect(ActionGlyphKind(.swapWindow(direction), fillOrder: .rows) == .swap(direction))
        }
        #expect(ActionGlyphKind(.restoreWindow, fillOrder: .rows) == .restore)
    }

    @Test("every built-in action has a glyph, and a preset's windows lie inside the screen")
    func everyBuiltInAction() {
        for action in BuiltInActions.all {
            let kind = ActionGlyphKind(action, fillOrder: .rows)
            if case .frames(let rects) = kind {
                #expect(rects.count == 1, "\(action)")
                for rect in rects {
                    #expect(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -1e-9, dy: -1e-9).contains(rect), "\(action)")
                }
            }
        }
    }

    @Test("a display has a bar-ended arrow for the next and previous display and a plain arrow for a side")
    func displaySymbols() {
        #expect(ActionGlyphKind.displaySymbol(.next) == "arrow.right.to.line")
        #expect(ActionGlyphKind.displaySymbol(.previous) == "arrow.left.to.line")
        #expect(Set(DisplayDirection.allCases.map(ActionGlyphKind.displaySymbol)).count == DisplayDirection.allCases.count)
    }

    @Test("the halves of a divider or a swap are split along the direction")
    func halves() {
        #expect(ActionGlyphKind.halves(split: .left) == ActionGlyphKind.halves(split: .right))
        #expect(ActionGlyphKind.halves(split: .up) == ActionGlyphKind.halves(split: .down))
        #expect(ActionGlyphKind.halves(split: .left).map(\.width) == [0.5, 0.5])
        #expect(ActionGlyphKind.halves(split: .up).map(\.height) == [0.5, 0.5])
        #expect(Set(Direction.allCases.map(ActionGlyphKind.arrowSymbol)).count == 4)
    }
}
