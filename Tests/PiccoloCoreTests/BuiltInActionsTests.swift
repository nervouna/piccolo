import Foundation
import Testing

@testable import PiccoloCore

/// The built-in actions of the keymap and the sections they and the layouts fall into.
@Suite("Built-in actions")
struct BuiltInActionsTests {
    /// The 30 actions of the Shortcuts tab, in the order it lists them, with their section.
    private static let table: [(action: Action, section: KeymapSection)] = [
        (.placeWindow(.preset(.leftHalf)), .halves),
        (.placeWindow(.preset(.rightHalf)), .halves),
        (.placeWindow(.preset(.topHalf)), .halves),
        (.placeWindow(.preset(.bottomHalf)), .halves),
        (.placeWindow(.preset(.topLeft)), .quarters),
        (.placeWindow(.preset(.topRight)), .quarters),
        (.placeWindow(.preset(.bottomLeft)), .quarters),
        (.placeWindow(.preset(.bottomRight)), .quarters),
        (.placeWindow(.preset(.leftThird)), .thirds),
        (.placeWindow(.preset(.centerThird)), .thirds),
        (.placeWindow(.preset(.rightThird)), .thirds),
        (.placeWindow(.preset(.leftTwoThirds)), .thirds),
        (.placeWindow(.preset(.rightTwoThirds)), .thirds),
        (.placeWindow(.preset(.maximize)), .other),
        (.placeWindow(.preset(.center)), .other),
        (.restoreWindow, .other),
        (.moveToDisplay(.next), .displays),
        (.moveToDisplay(.previous), .displays),
        (.moveToDisplay(.left), .displays),
        (.moveToDisplay(.right), .displays),
        (.moveToDisplay(.up), .displays),
        (.moveToDisplay(.down), .displays),
        (.moveDivider(.left), .dividers),
        (.moveDivider(.right), .dividers),
        (.moveDivider(.up), .dividers),
        (.moveDivider(.down), .dividers),
        (.swapWindow(.left), .swaps),
        (.swapWindow(.right), .swaps),
        (.swapWindow(.up), .swaps),
        (.swapWindow(.down), .swaps),
    ]

    @Test("there are nine sections, in the order of the keymap")
    func sectionOrder() {
        #expect(
            KeymapSection.allCases == [
                .halves, .quarters, .thirds, .other, .displays, .grids, .dividers, .swaps, .customAreas,
            ])
        #expect(
            KeymapSection.allCases.map(\.rawValue) == [
                "halves", "quarters", "thirds", "other", "displays", "grids", "dividers", "swaps", "customAreas",
            ])
    }

    @Test("the 30 built-in actions are listed in the order of the keymap")
    func order() {
        #expect(BuiltInActions.all.count == 30)
        #expect(BuiltInActions.all == Self.table.map(\.action))
    }

    @Test("no action is listed twice, and every preset and direction is in the list")
    func completeAndUnique() {
        for (index, action) in BuiltInActions.all.enumerated() {
            #expect(!BuiltInActions.all[(index + 1)...].contains(action), "\(action) is listed twice")
        }
        for preset in Preset.allCases {
            #expect(BuiltInActions.all.contains(.placeWindow(.preset(preset))), "\(preset) is missing")
        }
        for direction in DisplayDirection.allCases {
            #expect(BuiltInActions.all.contains(.moveToDisplay(direction)), "\(direction) is missing")
        }
        for direction in Direction.allCases {
            #expect(BuiltInActions.all.contains(.moveDivider(direction)), "divider \(direction) is missing")
            #expect(BuiltInActions.all.contains(.swapWindow(direction)), "swap \(direction) is missing")
        }
        #expect(BuiltInActions.all.contains(.restoreWindow))
    }

    @Test("every built-in action is in its section, and the list runs through the sections in order")
    func sections() {
        for row in Self.table {
            #expect(KeymapSection(of: row.action) == row.section, "\(row.action)")
        }
        let order = BuiltInActions.all.map { KeymapSection.allCases.firstIndex(of: KeymapSection(of: $0))! }
        #expect(order == order.sorted(), "the list does not follow the order of the sections")
    }

    @Test("a grid is in the grids section and a custom frame in the custom areas")
    func layoutSections() {
        #expect(KeymapSection(of: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))) == .grids)
        #expect(
            KeymapSection(of: .placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1))))
                == .customAreas)
    }

    @Test("an action is built in unless it is a grid or a custom frame")
    func isBuiltIn() {
        for action in BuiltInActions.all {
            #expect(action.isBuiltIn, "\(action)")
        }
        #expect(!Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)).isBuiltIn)
        #expect(!Action.placeWindow(.custom(FractionalRect(x: 0, y: 0, width: 1, height: 1))).isBuiltIn)
        // A custom frame that equals a preset is still a custom frame.
        #expect(!Action.placeWindow(.custom(FractionalRect(x: 0, y: 0, width: 0.5, height: 1))).isBuiltIn)
    }
}
