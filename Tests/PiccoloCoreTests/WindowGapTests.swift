import CoreGraphics
import Foundation
import Testing

@testable import PiccoloCore

/// The window gap: the config key, the rule that applies it, and every place that computes a frame.
private enum GapRig {
    static let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    /// An offset origin, an odd width and an odd height.
    static let odd = CGRect(x: 13, y: 29, width: 1001, height: 801)
    static let visibles = [visible, odd]

    static func edgeValues(_ frame: CGRect) -> [CGFloat] { [frame.minX, frame.minY, frame.maxX, frame.maxY] }

    /// The gap rule written out again for the tests, for an even gap: an edge on the visible frame's
    /// edge moves in by `gap`, any other by `gap / 2`.
    static func expected(_ frame: CGRect, gap: CGFloat, in visible: CGRect) -> CGRect {
        func inset(_ edge: CGFloat, on screenEdge: CGFloat, by sign: CGFloat) -> CGFloat {
            edge + sign * (abs(edge - screenEdge) <= 1 ? gap : gap / 2)
        }
        let left = inset(frame.minX, on: visible.minX, by: 1)
        let top = inset(frame.minY, on: visible.minY, by: 1)
        let right = inset(frame.maxX, on: visible.maxX, by: -1)
        let bottom = inset(frame.maxY, on: visible.maxY, by: -1)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Checks the cells of an arrangement: the nearest neighbours of each cell are exactly `gap` away,
    /// and the cells together span the visible frame taken in by `gap`.
    static func check(_ cells: [CGRect], gap: CGFloat, in visible: CGRect, _ label: String) {
        for a in cells {
            for b in cells where a != b {
                // b lies to the right of a, in the same band.
                if b.minX >= a.maxX, min(a.maxY, b.maxY) > max(a.minY, b.minY),
                    !cells.contains(where: { $0.minX >= a.maxX && $0.maxX <= b.minX && $0.minX < b.minX && $0 != a })
                {
                    #expect(b.minX - a.maxX == gap, "\(label): horizontal gap between \(a) and \(b)")
                }
                // b lies below a, in the same band.
                if b.minY >= a.maxY, min(a.maxX, b.maxX) > max(a.minX, b.minX),
                    !cells.contains(where: { $0.minY >= a.maxY && $0.maxY <= b.minY && $0.minY < b.minY && $0 != a })
                {
                    #expect(b.minY - a.maxY == gap, "\(label): vertical gap between \(a) and \(b)")
                }
            }
        }
        let union = cells.dropFirst().reduce(cells[0]) { $0.union($1) }
        let area = CGRect(
            x: visible.minX + gap, y: visible.minY + gap,
            width: visible.width - 2 * gap, height: visible.height - 2 * gap)
        #expect(union == area, "\(label): the cells span \(union), expected \(area)")
        for cell in cells {
            #expect(
                cell.minX == cell.minX.rounded() && cell.minY == cell.minY.rounded()
                    && cell.maxX == cell.maxX.rounded() && cell.maxY == cell.maxY.rounded(),
                "\(label): \(cell) is not on whole points")
        }
    }
}

@Suite("Window gap: config")
struct WindowGapConfigTests {
    private func load(_ json: String) throws -> LoadResult {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try Data(json.utf8).write(to: url)
            return try ConfigStore(url: url).load()
        }
    }

    @Test("a file without gap loads 0 without an issue")
    func missing() throws {
        let result = try load(#"{"bindings":[],"version":1}"#)
        #expect(result.config.gap == 0)
        #expect(result.issues.isEmpty)
        #expect(result.droppedEntries == false)
    }

    @Test("a gap from 0 to 64 loads", arguments: [0, 1, 12, 63, 64])
    func valid(_ gap: Int) throws {
        let result = try load(#"{"bindings":[],"gap":\#(gap),"version":1}"#)
        #expect(result.config.gap == gap)
        #expect(result.issues.isEmpty)
        #expect(result.droppedEntries == false)
    }

    @Test("a gap out of range or of the wrong type takes the default, with an issue naming it", arguments: [
        "-1", "65", "1000", "12.5", #""12""#, "true", "null", "[12]",
    ])
    func invalid(_ value: String) throws {
        let result = try load(#"{"bindings":[],"gap":\#(value),"resizeStep":0.1,"version":1}"#)
        #expect(result.config.gap == 0)
        #expect(result.config.resizeStep == 0.1)
        #expect(result.issues.count == 1)
        #expect(result.issues.first?.hasPrefix("gap ") == true, "\(result.issues)")
        #expect(result.droppedEntries == true)
    }

    @Test("every save writes gap, and a load reads it back")
    func written() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            let store = ConfigStore(url: url)
            try store.save(Config())
            #expect(try String(contentsOf: url, encoding: .utf8).contains(#""gap" : 0"#))

            let config = Config(gap: 12, bindings: allKindsBindings)
            try store.save(config)
            #expect(try String(contentsOf: url, encoding: .utf8).contains(#""gap" : 12"#))
            #expect(try store.load().config == config)
        }
    }

    @Test("a config with a gap out of range does not validate or save")
    func validation() throws {
        for gap in [-1, 65] {
            #expect(throws: ValidationError.self) { try Config(gap: gap).validate() }
        }
        try Config(gap: 64).validate()
        try withTemporaryDirectory { directory in
            #expect(throws: ConfigStoreError.self) {
                try ConfigStore(url: directory.appending(path: "config.json")).save(Config(gap: 65))
            }
        }
    }

    @Test("the action settings carry the gap")
    func actionSettings() {
        #expect(ActionSettings(Config(gap: 9)).gap == 9)
        #expect(ActionSettings.default.gap == 0)
        #expect(ActionSettings().gap == 0)
    }
}

@Suite("Window gap: the rule")
struct WindowGapRuleTests {
    private let visible = GapRig.visible

    @Test("gap 0 changes nothing")
    func zero() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 800)
        #expect(WindowGap.inset(frame, gap: 0, in: visible) == frame)
    }

    @Test("an edge on the visible frame moves in by the gap, any other by half of it, for 0 to 4 touching edges")
    func edges() {
        let gap: CGFloat = 12
        // Four edges touching.
        #expect(WindowGap.inset(visible, gap: 12, in: visible) == CGRect(x: 12, y: 12, width: 976, height: 776))
        // Three: left, top, bottom.
        #expect(
            WindowGap.inset(CGRect(x: 0, y: 0, width: 500, height: 800), gap: 12, in: visible)
                == CGRect(x: 12, y: 12, width: 482, height: 776))
        // Two: top left.
        #expect(
            WindowGap.inset(CGRect(x: 0, y: 0, width: 500, height: 400), gap: 12, in: visible)
                == CGRect(x: 12, y: 12, width: 482, height: 382))
        // One: top.
        #expect(
            WindowGap.inset(CGRect(x: 333, y: 0, width: 334, height: 400), gap: 12, in: visible)
                == CGRect(x: 339, y: 12, width: 322, height: 382))
        // None.
        #expect(
            WindowGap.inset(CGRect(x: 200, y: 100, width: 300, height: 200), gap: 12, in: visible)
                == CGRect(x: 206, y: 106, width: 288, height: 188))
        #expect(gap == 12)
    }

    @Test("an edge within 1 pt of the visible frame counts as on it")
    func tolerance() {
        let frame = CGRect(x: 1, y: 0, width: 499, height: 800)
        #expect(WindowGap.inset(frame, gap: 10, in: visible).minX == 11)
        let apart = CGRect(x: 2, y: 0, width: 498, height: 800)
        #expect(WindowGap.inset(apart, gap: 10, in: visible).minX == 7)
    }

    @Test("on a display with an offset origin the same frames come out, moved")
    func offsetOrigin() {
        let moved = CGRect(x: -1920, y: -240, width: 1920, height: 1055)
        let base = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        for rect in [FractionalRect(x: 0, y: 0, width: 0.5, height: 1), FractionalRect(x: 0.5, y: 0, width: 0.5, height: 0.5)] {
            let a = FrameResolver.fractionalFrame(rect, in: base, gap: 12)
            let b = FrameResolver.fractionalFrame(rect, in: moved, gap: 12)
            #expect(b == a.offsetBy(dx: moved.minX, dy: moved.minY))
        }
    }

    @Test("neighbours are exactly the gap apart for every gap, including odd ones, on an odd visible frame")
    func neighboursStayApart() {
        for visible in GapRig.visibles {
            for gap in 0...64 {
                let left = FrameResolver.fractionalFrame(
                    FractionalRect(x: 0, y: 0, width: 0.5, height: 1), in: visible, gap: gap)
                let right = FrameResolver.fractionalFrame(
                    FractionalRect(x: 0.5, y: 0, width: 0.5, height: 1), in: visible, gap: gap)
                #expect(right.minX - left.maxX == CGFloat(gap), "gap \(gap) in \(visible)")
                #expect(left.minX - visible.minX == CGFloat(gap))
                #expect(visible.maxX - right.maxX == CGFloat(gap))
                #expect(left.minY - visible.minY == CGFloat(gap))
                #expect(visible.maxY - left.maxY == CGFloat(gap))
                for frame in [left, right] {
                    #expect(frame.minX == frame.minX.rounded() && frame.maxX == frame.maxX.rounded())
                }
                // Thirds: three neighbours.
                let thirds = Preset.allCases.filter { [.leftThird, .centerThird, .rightThird].contains($0) }
                    .map { FrameResolver.frame(for: .preset($0), visibleFrame: visible, currentFrame: .zero, gap: gap) }
                    .sorted { $0.minX < $1.minX }
                #expect(thirds[1].minX - thirds[0].maxX == CGFloat(gap))
                #expect(thirds[2].minX - thirds[1].maxX == CGFloat(gap))
            }
        }
    }

    @Test("the gap is applied to the visible frame by taking it in on every side")
    func insetVisible() {
        #expect(WindowGap.inset(visible, by: 10) == CGRect(x: 10, y: 10, width: 980, height: 780))
        #expect(WindowGap.inset(visible, by: 0) == visible)
    }
}

@Suite("Window gap: presets and custom frames")
struct WindowGapPresetTests {
    @Test("every preset with gap 10 is the frame without a gap moved in by the rule", arguments: Preset.allCases)
    func presets(_ preset: Preset) {
        for visible in GapRig.visibles {
            let current = CGRect(x: visible.minX + 100, y: visible.minY + 60, width: 400, height: 300)
            let plain = FrameResolver.frame(for: .preset(preset), visibleFrame: visible, currentFrame: current)
            let gapped = FrameResolver.frame(for: .preset(preset), visibleFrame: visible, currentFrame: current, gap: 10)
            if preset == .center {
                // Keeps its size (it fits), stays centred.
                #expect(gapped.size == plain.size, "center keeps its size")
                #expect(gapped == plain)
                continue
            }
            #expect(gapped == GapRig.expected(plain, gap: 10, in: visible), "\(preset) in \(visible)")
        }
    }

    @Test("with gap 0 every preset is today's frame", arguments: Preset.allCases)
    func zeroGap(_ preset: Preset) {
        for visible in GapRig.visibles {
            let current = CGRect(x: visible.minX + 100, y: visible.minY + 60, width: 400, height: 300)
            let plain = FrameResolver.frame(for: .preset(preset), visibleFrame: visible, currentFrame: current)
            #expect(FrameResolver.frame(for: .preset(preset), visibleFrame: visible, currentFrame: current, gap: 0) == plain)
        }
        #expect(
            FrameResolver.frame(for: .preset(.leftHalf), visibleFrame: GapRig.visible, currentFrame: .zero, gap: 0)
                == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(
            FrameResolver.frame(for: .preset(.maximize), visibleFrame: GapRig.odd, currentFrame: .zero, gap: 0)
                == CGRect(x: 13, y: 29, width: 1001, height: 801))
    }

    @Test("maximize ends the gap from every edge")
    func maximize() {
        let frame = FrameResolver.frame(
            for: .preset(.maximize), visibleFrame: GapRig.visible, currentFrame: .zero, gap: 10)
        #expect(frame == CGRect(x: 10, y: 10, width: 980, height: 780))
    }

    @Test("center keeps its size, and a window that fills the screen is centred with the gap to every edge")
    func center() {
        let visible = GapRig.visible
        let small = FrameResolver.frame(
            for: .preset(.center), visibleFrame: visible, currentFrame: CGRect(x: 0, y: 0, width: 400, height: 300), gap: 10)
        #expect(small == CGRect(x: 300, y: 250, width: 400, height: 300))
        let big = FrameResolver.frame(
            for: .preset(.center), visibleFrame: visible, currentFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), gap: 10)
        #expect(big == CGRect(x: 10, y: 10, width: 980, height: 780))
    }

    @Test("a custom frame with gap 10 and gap 0")
    func custom() {
        let spec = FrameSpec.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1))
        let visible = GapRig.visible
        let plain = FrameResolver.frame(for: spec, visibleFrame: visible, currentFrame: .zero)
        #expect(plain == CGRect(x: 250, y: 0, width: 500, height: 800))
        #expect(FrameResolver.frame(for: spec, visibleFrame: visible, currentFrame: .zero, gap: 0) == plain)
        #expect(
            FrameResolver.frame(for: spec, visibleFrame: visible, currentFrame: .zero, gap: 10)
                == CGRect(x: 255, y: 10, width: 490, height: 780))
    }

    @Test("planning a placeWindow uses the gap, and keeps the whole visible frame to shift into")
    func plan() throws {
        let display = Display(frame: GapRig.visible, visibleFrame: GapRig.visible)
        let plan = try ActionPlanner.plan(
            .placeWindow(.preset(.rightHalf)), windowFrame: CGRect(x: 300, y: 300, width: 200, height: 200),
            displays: [display], gap: 12)
        #expect(plan == .place(target: CGRect(x: 506, y: 12, width: 482, height: 776), visibleFrame: GapRig.visible))
    }
}

@Suite("Window gap: cycling")
struct WindowGapCycleTests {
    private let display = Display(frame: GapRig.visible, visibleFrame: GapRig.visible)
    private let start = CGRect(x: 300, y: 300, width: 200, height: 200)

    private func target(_ frame: CGRect, gap: Int) throws -> CGRect {
        let plan = try ActionPlanner.plan(
            .placeWindow(.preset(.leftHalf)), windowFrame: frame, displays: [display], gap: gap)
        guard case .place(let target, _) = plan else {
            Issue.record("expected a placement")
            return .zero
        }
        return target
    }

    @Test("the three steps of leftHalf with a gap, and back to the first")
    func steps() throws {
        let first = try target(start, gap: 12)
        #expect(first == CGRect(x: 12, y: 12, width: 482, height: 776))
        let second = try target(first, gap: 12)
        // 2/3: the divider at 667 (666.67 rounded), 6 pt short of it.
        #expect(second == CGRect(x: 12, y: 12, width: 649, height: 776))
        let third = try target(second, gap: 12)
        // 1/3: the divider at 333.
        #expect(third == CGRect(x: 12, y: 12, width: 315, height: 776))
        #expect(try target(third, gap: 12) == first)
    }

    @Test("the next step is recognised from a gapped frame, and a frame without the gap is at no step")
    func recognised() {
        let visible = GapRig.visible
        let half = PresetCycle.frame(of: .leftHalf, step: 0, in: visible, gap: 12)
        #expect(half == CGRect(x: 12, y: 12, width: 482, height: 776))
        #expect(PresetCycle.currentStep(of: .leftHalf, windowFrame: half!, visibleFrame: visible, record: nil, gap: 12) == 0)
        #expect(PresetCycle.nextStep(of: .leftHalf, windowFrame: half!, visibleFrame: visible, record: nil, gap: 12) == 1)
        // The ungapped half is not the gapped half.
        let plain = PresetCycle.frame(of: .leftHalf, step: 0, in: visible)!
        #expect(PresetCycle.currentStep(of: .leftHalf, windowFrame: plain, visibleFrame: visible, record: nil, gap: 12) == nil)
        #expect(PresetCycle.step(of: .leftHalf, matching: half!, in: visible, gap: 12) == 0)
        #expect(PresetCycle.step(of: .leftHalf, matching: half!, in: visible) == nil)
    }

    @Test("with gap 0 the steps are today's")
    func zero() throws {
        let first = try target(start, gap: 0)
        #expect(first == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(try target(first, gap: 0) == CGRect(x: 0, y: 0, width: 667, height: 800))
    }

    @Test("right, top and bottom halves cycle with a gap too, and neighbours of the same step stay a gap apart")
    func otherHalves() throws {
        let visible = GapRig.odd
        for gap in [0, 7, 12] {
            let left = PresetCycle.frame(of: .leftHalf, step: 0, in: visible, gap: gap)!
            let right = PresetCycle.frame(of: .rightHalf, step: 0, in: visible, gap: gap)!
            #expect(right.minX - left.maxX == CGFloat(gap))
            let top = PresetCycle.frame(of: .topHalf, step: 0, in: visible, gap: gap)!
            let bottom = PresetCycle.frame(of: .bottomHalf, step: 0, in: visible, gap: gap)!
            #expect(bottom.minY - top.maxY == CGFloat(gap))
            // 2/3 left next to 1/3 right.
            let wide = PresetCycle.frame(of: .leftHalf, step: 1, in: visible, gap: gap)!
            let narrow = PresetCycle.frame(of: .rightHalf, step: 2, in: visible, gap: gap)!
            #expect(narrow.minX - wide.maxX == CGFloat(gap))
        }
    }
}

@Suite("Window gap: arrangements and divider moves")
struct WindowGapGridTests {
    @Test("grid cells keep the gap between them and to the screen edges", arguments: [7, 12, 24])
    func gridCells(_ gap: Int) {
        for visible in GapRig.visibles {
            let g = CGFloat(gap)
            let shapes: [(String, TileLayout)] = [
                ("1 × 2", .grid(windowCount: 2, rows: 1, columns: 2)),
                ("2 × 2", .grid(windowCount: 4, rows: 2, columns: 2)),
                ("3 in 2 × 2, rows", .grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .rows)),
                ("3 in 2 × 2, columns", .grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns)),
                ("2 × 1", .grid(windowCount: 2, rows: 2, columns: 1)),
            ]
            for (name, layout) in shapes {
                GapRig.check(layout.frames(in: visible, gap: gap), gap: g, in: visible, "\(name), gap \(gap), \(visible)")
            }
        }
    }

    @Test("with gap 0 the cells are today's")
    func zero() {
        for visible in GapRig.visibles {
            let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2)
            #expect(layout.frames(in: visible, gap: 0) == layout.frames(in: visible))
        }
    }

    @Test("the arrangement planner frames the cells with the gap")
    func planner() throws {
        let display = Display(frame: GapRig.visible, visibleFrame: GapRig.visible)
        let ids = (1...2).map { WindowID(rawValue: UInt32($0)) }
        var history = FocusHistory()
        for id in ids.reversed() { history.recordFocus(id) }
        let candidates = ids.map {
            WindowCandidate(
                id: $0, frame: CGRect(x: 100, y: 100, width: 300, height: 300), isStandard: true,
                isMinimized: false, isFullScreen: false)
        }
        let plan = try #require(
            try ArrangePlanner.plan(
                grid: GridSpec(count: 2, rows: 1, columns: 2), gap: 12, displayIndex: 0,
                candidates: candidates, history: history, displays: [display]))
        #expect(plan.assignments.map(\.frame) == [
            CGRect(x: 12, y: 12, width: 482, height: 776), CGRect(x: 506, y: 12, width: 482, height: 776),
        ])
    }

    @Test("a divider move keeps the gap between the windows that follow it, in rows and columns")
    func dividerMove() throws {
        for order in GridFillOrder.allCases {
            for visible in GapRig.visibles {
                for gap in [7, 12] {
                    var layout = TileLayout.grid(windowCount: 4, rows: 2, columns: 2, fillOrder: order)
                    for direction in [Direction.right, .right, .left, .down, .up] {
                        layout = try #require(
                            DividerMove.plan(layout: layout, focusedCell: 0, direction: direction, step: 0.05))
                        GapRig.check(
                            layout.frames(in: visible, gap: gap), gap: CGFloat(gap), in: visible,
                            "\(order) \(direction), gap \(gap)")
                    }
                }
            }
        }
    }

    @Test("a group reads back its dividers through the gap: reached dividers are recorded as asked, refused ones where they ended")
    func recordAchievedWithGap() throws {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2)
        let windows = (1...2).map { WindowID(rawValue: UInt32($0)) }
        var group = LayoutGroup(
            layout: layout, windows: windows, visibleFrame: visible, frames: layout.frames(in: visible, gap: 12))
        let requested = try #require(DividerMove.plan(layout: layout, focusedCell: 0, direction: .right, step: 0.05))
        let asked = group.targetFrames(for: requested, gap: 12)
        #expect(asked == [CGRect(x: 12, y: 12, width: 532, height: 476), CGRect(x: 556, y: 12, width: 432, height: 476)])
        #expect(asked[1].minX - asked[0].maxX == 12)

        // Everything reached its frame: the divider is exactly where it was asked.
        var reached = group
        reached.recordAchieved(requested: requested, achieved: asked, gap: 12)
        #expect(abs(reached.layout.rows[0].widths[0] - 0.55) < 1e-9)
        #expect(reached.frames == asked)

        // The right window refused to shrink below 500 points: it stays at 488 to 988. The divider is
        // recorded at the window's edge less half the gap.
        group.recordAchieved(
            requested: requested, achieved: [asked[0], CGRect(x: 488, y: 12, width: 500, height: 476)], gap: 12)
        #expect(abs(group.layout.rows[0].widths[0] - 0.482) < 1e-9)

        // The same without the gap would have given another divider, so the gap is part of the read-back.
        var plain = LayoutGroup(layout: layout, windows: windows, visibleFrame: visible, frames: layout.frames(in: visible))
        plain.recordAchieved(
            requested: requested, achieved: [asked[0], CGRect(x: 488, y: 12, width: 500, height: 476)])
        #expect(abs(plain.layout.rows[0].widths[0] - 0.488) < 1e-9)
    }

    @Test("a group arranged with one gap validates against its recorded frames whatever the gap is now")
    func recordedFramesValidate() throws {
        let visible = GapRig.visible
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 2)
        let windows = (1...2).map { WindowID(rawValue: UInt32($0)) }
        let arranged = layout.frames(in: visible, gap: 12)
        let group = LayoutGroup(layout: layout, windows: windows, visibleFrame: visible, frames: arranged)
        let current = Dictionary(uniqueKeysWithValues: zip(windows, arranged))
        #expect(group.isIntact(currentFrames: current))
        // A move with another gap targets the new gap; the validation does not look at it.
        #expect(group.targetFrames(for: layout, gap: 24) != arranged)
        #expect(group.breakage(currentFrames: current) == nil)
    }
}

@Suite("Window gap: moving between displays, restoring")
struct WindowGapDisplayTests {
    private let first = Display(
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 775))
    private let second = Display(
        frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 1000, y: 25, width: 1000, height: 775))

    @Test("a gapped half on one display is a gapped half on the other")
    func gappedHalf() throws {
        for gap in [0, 12] {
            for preset in [Preset.leftHalf, .rightHalf, .topHalf, .bottomHalf, .topLeft, .bottomRight] {
                let onFirst = FrameResolver.frame(
                    for: .preset(preset), visibleFrame: first.visibleFrame, currentFrame: .zero, gap: gap)
                let expected = FrameResolver.frame(
                    for: .preset(preset), visibleFrame: second.visibleFrame, currentFrame: .zero, gap: gap)
                let plan = try ActionPlanner.plan(
                    .moveToDisplay(.next), windowFrame: onFirst, displays: [first, second], gap: gap)
                #expect(plan == .place(target: expected, visibleFrame: second.visibleFrame), "\(preset), gap \(gap)")
            }
        }
    }

    @Test("with gap 0 a move is today's")
    func zero() {
        let window = CGRect(x: 100, y: 100, width: 300, height: 200)
        #expect(
            DisplayLayout.frame(moving: window, from: first, to: second, gap: 0)
                == DisplayLayout.frame(moving: window, from: first, to: second))
    }

    @Test("restoreWindow puts the window at its recorded origin, whatever the gap")
    func restore() throws {
        let origin = CGRect(x: 100, y: 120, width: 600, height: 400)
        let placed = CGRect(x: 12, y: 37, width: 482, height: 751)
        let record = WindowRecord(origin: origin, lastAchieved: placed)
        for gap in [0, 12, 64] {
            let plan = try ActionPlanner.plan(
                .restoreWindow, windowFrame: placed, displays: [first, second], record: record, gap: gap)
            #expect(plan == .place(target: origin, visibleFrame: first.visibleFrame))
        }
    }
}
