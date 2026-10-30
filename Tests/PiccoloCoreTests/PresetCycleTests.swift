import CoreGraphics
import Foundation
import Testing

@testable import PiccoloCore

/// A display whose origin is not at zero, so that anchoring to an edge is observable.
private enum CycleRig {
    static let display = Display(
        frame: CGRect(x: 1440, y: -200, width: 1800, height: 1100),
        visibleFrame: CGRect(x: 1440, y: -170, width: 1800, height: 1050))
    static let visible = display.visibleFrame
    static let displays = [display]
    static let halves: [Preset] = [.leftHalf, .rightHalf, .topHalf, .bottomHalf]

    /// A window nowhere near a half.
    static let elsewhere = CGRect(x: 1600, y: 0, width: 500, height: 400)

    static func plan(
        _ preset: Preset, from frame: CGRect, record: WindowRecord? = nil
    ) throws -> CGRect {
        let plan = try ActionPlanner.plan(
            .placeWindow(.preset(preset)), windowFrame: frame, displays: displays, record: record)
        guard case .place(let target, let visibleFrame) = plan else {
            Issue.record("expected a placement, got \(plan)")
            return .zero
        }
        #expect(visibleFrame == visible)
        return target
    }
}

@Suite("PresetCycle: the steps of the four halves")
struct PresetCycleStepTests {
    private let visible = CycleRig.visible

    @Test("each half has three steps: 1/2, 2/3 and 1/3 along its axis, anchored to its edge", arguments: CycleRig.halves)
    func steps(preset: Preset) throws {
        let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
        for (step, fraction) in fractions.enumerated() {
            let frame = try #require(PresetCycle.frame(of: preset, step: step, in: visible))
            switch preset {
            case .leftHalf:
                #expect(frame.minX == visible.minX)
                expectClose(frame.width, visible.width * fraction)
                #expect(frame.minY == visible.minY && frame.height == visible.height)
            case .rightHalf:
                #expect(frame.maxX == visible.maxX)
                expectClose(frame.width, visible.width * fraction)
                #expect(frame.minY == visible.minY && frame.height == visible.height)
            case .topHalf:
                #expect(frame.minY == visible.minY)
                expectClose(frame.height, visible.height * fraction)
                #expect(frame.minX == visible.minX && frame.width == visible.width)
            case .bottomHalf:
                #expect(frame.maxY == visible.maxY)
                expectClose(frame.height, visible.height * fraction)
                #expect(frame.minX == visible.minX && frame.width == visible.width)
            default:
                Issue.record("not a half")
            }
        }
    }

    @Test("step 0 is the frame of the preset itself", arguments: CycleRig.halves)
    func stepZero(preset: Preset) throws {
        let own = FrameResolver.frame(
            for: .preset(preset), visibleFrame: visible, currentFrame: CycleRig.elsewhere)
        #expect(PresetCycle.frame(of: preset, step: 0, in: visible) == own)
    }

    @Test("only the four halves cycle")
    func whichCycle() {
        #expect(Preset.allCases.filter(PresetCycle.cycles) == CycleRig.halves)
        #expect(PresetCycle.fractionalRect(of: .maximize, step: 0) == nil)
        #expect(PresetCycle.fractionalRect(of: .leftHalf, step: 3) == nil)
        #expect(PresetCycle.fractionalRect(of: .leftHalf, step: -1) == nil)
    }

    private func expectClose(_ value: CGFloat, _ expected: CGFloat) {
        #expect(abs(value - expected) <= 1, "\(value) is not within 1 pt of \(expected)")
    }
}

@Suite("ActionPlanner: cycling the halves")
struct PresetCyclePlanTests {
    private let visible = CycleRig.visible

    private func frame(_ preset: Preset, _ step: Int) -> CGRect {
        PresetCycle.frame(of: preset, step: step, in: visible)!
    }

    @Test("a window elsewhere goes to step 0", arguments: CycleRig.halves)
    func elsewhere(preset: Preset) throws {
        #expect(try CycleRig.plan(preset, from: CycleRig.elsewhere) == frame(preset, 0))
    }

    @Test("a window at step k goes to step k + 1, and after the last to step 0, from the computed frame", arguments: CycleRig.halves)
    func next(preset: Preset) throws {
        #expect(try CycleRig.plan(preset, from: frame(preset, 0)) == frame(preset, 1))
        #expect(try CycleRig.plan(preset, from: frame(preset, 1)) == frame(preset, 2))
        #expect(try CycleRig.plan(preset, from: frame(preset, 2)) == frame(preset, 0))
    }

    @Test("within 2 pt on every edge counts as at the step, 3 pt does not")
    func tolerance() throws {
        let near = frame(.leftHalf, 0).insetBy(dx: 2, dy: 2)
        #expect(try CycleRig.plan(.leftHalf, from: near) == frame(.leftHalf, 1))
        let off = frame(.leftHalf, 0).insetBy(dx: 3, dy: 3)
        #expect(try CycleRig.plan(.leftHalf, from: off) == frame(.leftHalf, 0))
    }

    @Test("a window that refused the exact size still cycles, by the achieved frame of the record")
    func recordedAchieved() throws {
        // The window refused 2/3 and stayed at 3/4 of the width.
        let refused = CGRect(
            x: visible.minX, y: visible.minY, width: visible.width * 0.75, height: visible.height)
        let record = WindowRecord(
            origin: CycleRig.elsewhere, lastAchieved: refused, cycle: CycleStep(preset: .leftHalf, step: 1))

        #expect(try CycleRig.plan(.leftHalf, from: refused, record: record) == frame(.leftHalf, 2))
        // Without the record the same window is at no step.
        #expect(try CycleRig.plan(.leftHalf, from: refused) == frame(.leftHalf, 0))
    }

    @Test("a record of another preset does not count for this one")
    func otherPreset() throws {
        let refused = CGRect(
            x: visible.minX, y: visible.minY, width: visible.width * 0.75, height: visible.height)
        let record = WindowRecord(
            origin: CycleRig.elsewhere, lastAchieved: refused, cycle: CycleStep(preset: .rightHalf, step: 1))
        #expect(try CycleRig.plan(.leftHalf, from: refused, record: record) == frame(.leftHalf, 0))
    }

    @Test("a record the window has left does not count")
    func recordLeft() throws {
        let record = WindowRecord(
            origin: CycleRig.elsewhere, lastAchieved: frame(.leftHalf, 1),
            cycle: CycleStep(preset: .leftHalf, step: 1))
        #expect(try CycleRig.plan(.leftHalf, from: CycleRig.elsewhere, record: record) == frame(.leftHalf, 0))
    }

    @Test("a window at step 2 of another half is at step 0 of this one")
    func differentHalf() throws {
        #expect(try CycleRig.plan(.rightHalf, from: frame(.leftHalf, 2)) == frame(.rightHalf, 0))
    }

    @Test("the other presets and custom frames do not cycle: a window at the target is placed there again")
    func noCycling() throws {
        for preset in [Preset.maximize, .topLeft, .leftThird, .leftTwoThirds] {
            let own = FrameResolver.frame(
                for: .preset(preset), visibleFrame: visible, currentFrame: CycleRig.elsewhere)
            #expect(try CycleRig.plan(preset, from: own) == own, "\(preset)")
        }
        let rect = FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)
        let custom = FrameResolver.frame(
            for: .custom(rect), visibleFrame: visible, currentFrame: CycleRig.elsewhere)
        let plan = try ActionPlanner.plan(
            .placeWindow(.custom(rect)), windowFrame: custom, displays: CycleRig.displays)
        #expect(plan == .place(target: custom, visibleFrame: visible))
    }

    @Test("the step a placement reached is found from its target")
    func stepOfTarget() {
        for step in 0..<PresetCycle.stepCount {
            #expect(PresetCycle.step(of: .topHalf, matching: frame(.topHalf, step), in: visible) == step)
        }
        #expect(PresetCycle.step(of: .topHalf, matching: CycleRig.elsewhere, in: visible) == nil)
    }
}
