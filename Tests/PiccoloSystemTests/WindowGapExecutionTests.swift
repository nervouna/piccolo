import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

/// The window gap through the executor: the settings the hotkey path hands over reach every action.
@Suite("ActionExecutor: window gap")
struct WindowGapExecutionTests {
    private static let visible = DeskRig.primary.visibleFrame

    @Test("an arrangement with a gap places its windows gap apart, and a divider move keeps the gap")
    func arrangeAndMove() throws {
        let desk = Desk()
        desk.openWindows(2)
        let settings = ActionSettings(resizeStep: 0.05, gap: 12)

        _ = try desk.executor.run(.arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), settings: settings)
        let arranged = try desk.frames(2)
        #expect(arranged == TileLayout.grid(windowCount: 2, rows: 1, columns: 2).frames(in: Self.visible, gap: 12))
        #expect(arranged[1].minX - arranged[0].maxX == 12)
        #expect(arranged[0].minX == Self.visible.minX + 12)

        desk.focused = 1
        _ = try desk.executor.run(.moveDivider(.right), settings: settings)
        let moved = try desk.frames(2)
        #expect(moved[1].minX - moved[0].maxX == 12)
        #expect(moved[0].width > arranged[0].width)
        #expect(moved[0].minX == Self.visible.minX + 12)
        #expect(moved[1].maxX == Self.visible.maxX - 12)
        #expect(desk.store.entries.count == 1)
    }

    @Test("a group arranged with one gap moves with the gap in effect when the key is pressed")
    func gapChangesBetween() throws {
        let desk = Desk()
        desk.openWindows(2)
        _ = try desk.executor.run(
            .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), settings: ActionSettings(gap: 12))
        desk.focused = 1

        let outcome = try desk.executor.run(.moveDivider(.right), settings: ActionSettings(resizeStep: 0.05, gap: 20))

        guard case .dividerMove(.moved) = outcome else {
            Issue.record("the group should hold and move, got \(outcome)")
            return
        }
        let moved = try desk.frames(2)
        #expect(moved[1].minX - moved[0].maxX == 20)
    }

    @Test("the destinations of the preview carry the gap")
    func destinations() throws {
        let desk = Desk()
        desk.openWindows(2)
        let settings = ActionSettings(gap: 12)

        let arrangement = try desk.executor.destinations(
            for: .arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), settings: settings)
        #expect(arrangement.map(\.frame) == TileLayout.grid(windowCount: 2, rows: 1, columns: 2).frames(in: Self.visible, gap: 12))

        desk.focused = 1
        let single = try desk.executor.destinations(for: .placeWindow(.preset(.maximize)), settings: settings)
        #expect(single.map(\.frame) == [CGRect(x: 12, y: 52, width: 1176, height: 776)])
    }

    @Test("a placeWindow with a gap records the cycle step, so that the next press moves on")
    func cycling() throws {
        let desk = Desk()
        desk.openWindows(1)
        let settings = ActionSettings(gap: 12)
        var targets: [CGRect] = []
        for _ in 0..<4 {
            guard case .placed(let target, _) = try desk.executor.run(.placeWindow(.preset(.leftHalf)), settings: settings)
            else {
                Issue.record("expected a placement")
                return
            }
            targets.append(target)
        }
        let steps = (0..<3).map { PresetCycle.frame(of: .leftHalf, step: $0, in: Self.visible, gap: 12) }
        #expect(targets == [steps[0], steps[1], steps[2], steps[0]])
    }
}
