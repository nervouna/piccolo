import CoreGraphics

/// The three steps of Left, Right, Top and Bottom Half: pressing the same shortcut again takes the
/// window from 1/2 to 2/3 to 1/3 of the display and back to 1/2.
public enum PresetCycle {
    public static let stepCount = 3

    /// Whether `preset` cycles. The other presets and custom frames do not.
    public static func cycles(_ preset: Preset) -> Bool {
        switch preset {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: true
        default: false
        }
    }

    /// The frame of `preset` at `step` as fractions of a visible frame: its size along the preset's
    /// axis is 1/2, 2/3, then 1/3, anchored to the preset's edge, full size along the other axis.
    /// `nil` for a preset that does not cycle or a step outside 0..<3.
    public static func fractionalRect(of preset: Preset, step: Int) -> FractionalRect? {
        guard cycles(preset), (0..<stepCount).contains(step) else { return nil }
        let third = 1.0 / 3.0
        let twoThirds = 2.0 / 3.0
        let size = [0.5, twoThirds, third][step]
        // Where the frame starts when it is anchored to the far edge: the same Double values as the
        // thirds of the presets, so that the edges agree with them exactly.
        let farStart = [0.5, third, twoThirds][step]
        switch preset {
        case .leftHalf: return FractionalRect(x: 0, y: 0, width: size, height: 1)
        case .rightHalf: return FractionalRect(x: farStart, y: 0, width: size, height: 1)
        case .topHalf: return FractionalRect(x: 0, y: 0, width: 1, height: size)
        case .bottomHalf: return FractionalRect(x: 0, y: farStart, width: 1, height: size)
        default: return nil
        }
    }

    /// The frame of `preset` at `step` in `visibleFrame`, with the edge rounding rule.
    public static func frame(of preset: Preset, step: Int, in visibleFrame: CGRect) -> CGRect? {
        fractionalRect(of: preset, step: step).map {
            FrameResolver.fractionalFrame($0, in: visibleFrame)
        }
    }

    /// The step the window is at, or `nil` when it is at none: its frame is within 2 pt on every edge
    /// of the frame of the step, or of the achieved frame recorded for that step of this preset.
    public static func currentStep(
        of preset: Preset, windowFrame: CGRect, visibleFrame: CGRect, record: WindowRecord?
    ) -> Int? {
        if let record, let cycle = record.cycle, cycle.preset == preset, record.isInPlace(at: windowFrame) {
            return cycle.step
        }
        return (0..<stepCount).first { step in
            frame(of: preset, step: step, in: visibleFrame).map {
                FrameTolerance.matches(windowFrame, $0)
            } ?? false
        }
    }

    /// The step a press of `preset` takes the window to: the one after the step it is at, step 0
    /// after the last, and step 0 for a window that is at none.
    public static func nextStep(
        of preset: Preset, windowFrame: CGRect, visibleFrame: CGRect, record: WindowRecord?
    ) -> Int {
        guard
            let current = currentStep(
                of: preset, windowFrame: windowFrame, visibleFrame: visibleFrame, record: record)
        else { return 0 }
        return (current + 1) % stepCount
    }

    /// The step of `preset` whose frame in `visibleFrame` is `target`, for recording what a press
    /// placed.
    public static func step(of preset: Preset, matching target: CGRect, in visibleFrame: CGRect) -> Int? {
        (0..<stepCount).first { frame(of: preset, step: $0, in: visibleFrame) == target }
    }
}
