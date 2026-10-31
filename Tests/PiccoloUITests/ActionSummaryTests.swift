import Testing

import PiccoloCore

@testable import PiccoloUI

@Suite("Action summaries")
struct ActionSummaryTests {
    @Test("every preset has its own name", arguments: [
        (Preset.leftHalf, "Left Half"),
        (.rightHalf, "Right Half"),
        (.topHalf, "Top Half"),
        (.bottomHalf, "Bottom Half"),
        (.topLeft, "Top Left"),
        (.topRight, "Top Right"),
        (.bottomLeft, "Bottom Left"),
        (.bottomRight, "Bottom Right"),
        (.leftThird, "Left Third"),
        (.centerThird, "Center Third"),
        (.rightThird, "Right Third"),
        (.leftTwoThirds, "Left Two Thirds"),
        (.rightTwoThirds, "Right Two Thirds"),
        (.maximize, "Maximize"),
        (.center, "Center"),
    ] as [(Preset, String)])
    func presetNames(_ preset: Preset, _ name: String) {
        #expect(ActionSummary.text(for: .placeWindow(.preset(preset))) == name)
        #expect(ActionSummary.name(of: preset) == name)
    }

    @Test("the table covers every preset, and the names are distinct")
    func presetNamesAreComplete() {
        let names = Preset.allCases.map { ActionSummary.name(of: $0) }
        #expect(names.count == 15)
        #expect(Set(names).count == names.count)
    }

    @Test("a custom frame lists its four percentages")
    func customFrame() {
        let frame = FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)
        #expect(ActionSummary.text(for: .placeWindow(.custom(frame))) == "Custom (25%, 0%, 50% × 100%)")
    }

    @Test("a custom frame with fractions of a percent shows up to two decimals")
    func customFrameDecimals() {
        let frame = FractionalRect(x: 1.0 / 3.0, y: 0.125, width: 2.0 / 3.0, height: 0.1)
        #expect(ActionSummary.text(for: .placeWindow(.custom(frame))) == "Custom (33.33%, 12.5%, 66.67% × 10%)")
    }

    @Test("display moves")
    func displays() {
        #expect(ActionSummary.text(for: .moveToDisplay(.next)) == "Next Display")
        #expect(ActionSummary.text(for: .moveToDisplay(.previous)) == "Previous Display")
    }

    @Test("the four geometric display directions", arguments: [
        (DisplayDirection.left, "Display to the Left"),
        (.right, "Display to the Right"),
        (.up, "Display Above"),
        (.down, "Display Below"),
    ] as [(DisplayDirection, String)])
    func geometricDisplays(_ direction: DisplayDirection, _ text: String) {
        #expect(ActionSummary.text(for: .moveToDisplay(direction)) == text)
        #expect(ActionSummary.name(of: direction) == text)
    }

    @Test("a grid says how many windows go in how many rows and columns")
    func grids() {
        #expect(ActionSummary.text(for: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))) == "Arrange 4 in 2 × 2")
        #expect(ActionSummary.text(for: .arrangeGrid(GridSpec(count: 3, rows: 1, columns: 3))) == "Arrange 3 in 1 × 3")
        #expect(ActionSummary.text(for: .arrangeGrid(GridSpec(count: 1, rows: 1, columns: 1))) == "Arrange 1 in 1 × 1")
    }

    @Test("every divider direction", arguments: [
        (Direction.left, "Move Divider Left"),
        (.right, "Move Divider Right"),
        (.up, "Move Divider Up"),
        (.down, "Move Divider Down"),
    ] as [(Direction, String)])
    func dividers(_ direction: Direction, _ text: String) {
        #expect(ActionSummary.text(for: .moveDivider(direction)) == text)
    }

    @Test("every swap direction", arguments: [
        (Direction.left, "Swap Window Left"),
        (.right, "Swap Window Right"),
        (.up, "Swap Window Up"),
        (.down, "Swap Window Down"),
    ] as [(Direction, String)])
    func swaps(_ direction: Direction, _ text: String) {
        #expect(ActionSummary.text(for: .swapWindow(direction)) == text)
    }

    @Test("percentages")
    func percentages() {
        #expect(ActionSummary.percent(0) == "0%")
        #expect(ActionSummary.percent(1) == "100%")
        #expect(ActionSummary.percent(0.05) == "5%")
        #expect(ActionSummary.percent(0.1) == "10%")
        #expect(ActionSummary.percent(0.3333) == "33.33%")
        #expect(ActionSummary.percent(0.125) == "12.5%")
        #expect(ActionSummary.percent(0.0001) == "0.01%")
        #expect(ActionSummary.percentNumber(0.25) == "25")
    }

    @Test("a number that is not finite does not crash the summary")
    func percentNotFinite() {
        #expect(!ActionSummary.percent(.nan).isEmpty)
        #expect(!ActionSummary.percent(.infinity).isEmpty)
    }

    @Test("every action kind has a title and a default action of its own kind")
    func kinds() {
        #expect(ActionKind.allCases.count == 6)
        #expect(Set(ActionKind.allCases.map(\.title)).count == 6)
        for kind in ActionKind.allCases {
            #expect(ActionKind(kind.defaultAction) == kind)
        }
        #expect(Action.newBindingDefault == .placeWindow(.preset(.leftHalf)))
        #expect(ActionKind.arrangeGrid.defaultAction == .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))
    }

    @Test("Restore Window is a kind of its own, with the same text as its summary and no parameters")
    func restoreWindow() throws {
        #expect(ActionKind(.restoreWindow) == .restoreWindow)
        #expect(ActionKind.restoreWindow.defaultAction == .restoreWindow)
        #expect(ActionKind.restoreWindow.configName == "restoreWindow")
        #expect(ActionSummary.text(for: .restoreWindow, bundle: AppLanguage.en.textBundle!) == "Restore Window")
        #expect(ActionKind.restoreWindow.title(bundle: AppLanguage.en.textBundle!) == "Restore Window")
        #expect(ActionPreview.rects(for: .restoreWindow) == nil)
    }

    @Test("Swap Window is a kind of its own, with a direction that defaults to left")
    func swapWindow() throws {
        #expect(ActionKind(.swapWindow(.down)) == .swapWindow)
        #expect(ActionKind.swapWindow.defaultAction == .swapWindow(.left))
        #expect(ActionKind.swapWindow.configName == "swapWindow")
        #expect(ActionKind.swapWindow.title(bundle: AppLanguage.en.textBundle!) == "Swap Window")
        #expect(ActionPreview.rects(for: .swapWindow(.left)) == nil)
    }
}
