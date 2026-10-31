import CoreGraphics
import Foundation
import Testing

@testable import PiccoloCore

private enum RestoreRig {
    static let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 970))
    static let secondary = Display(
        frame: CGRect(x: 1600, y: 100, width: 1200, height: 800),
        visibleFrame: CGRect(x: 1600, y: 130, width: 1200, height: 770))
    static let both = [primary, secondary]

    static let origin = CGRect(x: 100, y: 120, width: 600, height: 400)
    static let left = CGRect(x: 0, y: 30, width: 800, height: 970)
}

@Suite("Action: restoreWindow in the config")
struct RestoreActionCodingTests {
    @Test("it decodes from {\"type\": \"restoreWindow\"} with no parameters")
    func decode() throws {
        let action = try JSONDecoder().decode(Action.self, from: Data(#"{"type": "restoreWindow"}"#.utf8))
        #expect(action == .restoreWindow)
    }

    @Test("it encodes as the type alone and round-trips")
    func encode() throws {
        let data = try JSONEncoder().encode(Action.restoreWindow)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.count == 1)
        #expect(object["type"] as? String == "restoreWindow")
        #expect(try JSONDecoder().decode(Action.self, from: data) == .restoreWindow)
    }

    @Test("a config written before it loads unchanged, and a config with it round-trips")
    func config() throws {
        let before = Config.defaultShortcuts
        let data = try JSONEncoder().encode(before)
        #expect(try JSONDecoder().decode(Config.self, from: data) == before)
        #expect(before.bindings.contains { $0.action == .restoreWindow })
        #expect(throws: Never.self) { try Action.restoreWindow.validate() }
    }

    @Test("the defaults bind it to control + option + Delete, in 33 bindings")
    func defaultBinding() throws {
        let bindings = Config.defaultShortcuts.bindings
        #expect(bindings.count == 33)
        let restore = try #require(bindings.first { $0.action == .restoreWindow })
        #expect(restore.shortcut == Shortcut(keyCode: 51, modifiers: [.control, .option]))
    }
}

@Suite("ActionPlanner: restoreWindow")
struct RestorePlanTests {
    private func plan(_ frame: CGRect, record: WindowRecord?) throws -> ActionPlan {
        try ActionPlanner.plan(.restoreWindow, windowFrame: frame, displays: RestoreRig.both, record: record)
    }

    @Test("a window where Piccolo left it goes back to its origin, on the display that holds most of it")
    func withRecord() throws {
        let record = WindowRecord(origin: RestoreRig.origin, lastAchieved: RestoreRig.left)
        #expect(
            try plan(RestoreRig.left, record: record)
                == .place(target: RestoreRig.origin, visibleFrame: RestoreRig.primary.visibleFrame))

        // An origin on the second display is planned against that display.
        let farOrigin = CGRect(x: 1700, y: 200, width: 500, height: 300)
        let far = WindowRecord(origin: farOrigin, lastAchieved: RestoreRig.left)
        #expect(
            try plan(RestoreRig.left, record: far)
                == .place(target: farOrigin, visibleFrame: RestoreRig.secondary.visibleFrame))
    }

    @Test("within 2 pt of the achieved frame counts as where Piccolo left it")
    func tolerance() throws {
        let record = WindowRecord(origin: RestoreRig.origin, lastAchieved: RestoreRig.left)
        let near = RestoreRig.left.insetBy(dx: 2, dy: 2)
        #expect(try plan(near, record: record) != .nothingToDo)
        let off = RestoreRig.left.insetBy(dx: 3, dy: 3)
        #expect(try plan(off, record: record) == .nothingToDo)
    }

    @Test("without a record there is nothing to restore")
    func noRecord() throws {
        #expect(try plan(RestoreRig.left, record: nil) == .nothingToDo)
    }

    @Test("a window the user moved since has nothing to restore")
    func moved() throws {
        let record = WindowRecord(origin: RestoreRig.origin, lastAchieved: RestoreRig.left)
        let moved = RestoreRig.left.offsetBy(dx: 40, dy: 10)
        #expect(try plan(moved, record: record) == .nothingToDo)
    }

    @Test("an origin on no current display is centred at its size on the window's current display")
    func originOffScreen() throws {
        let gone = CGRect(x: 5000, y: 100, width: 700, height: 500)
        let record = WindowRecord(origin: gone, lastAchieved: RestoreRig.left)

        let plan = try plan(RestoreRig.left, record: record)

        let visible = RestoreRig.primary.visibleFrame
        let expected = CGRect(
            x: visible.midX - 350, y: visible.midY - 250, width: 700, height: 500)
        guard case .place(let target, let visibleFrame) = plan else {
            Issue.record("expected a placement, got \(plan)")
            return
        }
        #expect(visibleFrame == visible)
        #expect(FrameTolerance.matches(target, expected, tolerance: 1), "\(target) is not near \(expected)")
        #expect(target.size == gone.size)
    }
}
