import CoreGraphics
import Foundation
import Testing

@testable import PiccoloCore

/// What the column tests share.
enum ColumnLayoutSupport {
    /// The transpose of a rectangle: x and y swapped, width and height swapped. Written out here,
    /// independently of the code under test.
    static func transposed(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width)
    }

    /// A column-first grid to build, with the windows per column the issue gives for it.
    struct GridExample: Sendable, CustomTestStringConvertible {
        let windowCount: Int
        let rows: Int
        let columns: Int
        let cellsPerColumn: [Int]

        var layout: TileLayout {
            TileLayout.grid(windowCount: windowCount, rows: rows, columns: columns, fillOrder: .columns)
        }

        var testDescription: String {
            "\(windowCount) in \(rows)x\(columns) columns first"
        }
    }

    /// The examples of the issue (2 × 2 with 3, 2 × 3 with 5 and 4, 2 × 2 with 2, 1 × 3 with 2 and
    /// 2 × 2 with 4), then more with unused columns and one cell per column.
    static let gridExamples: [GridExample] = [
        GridExample(windowCount: 3, rows: 2, columns: 2, cellsPerColumn: [2, 1]),
        GridExample(windowCount: 5, rows: 2, columns: 3, cellsPerColumn: [2, 2, 1]),
        GridExample(windowCount: 4, rows: 2, columns: 3, cellsPerColumn: [2, 2]),
        GridExample(windowCount: 2, rows: 2, columns: 2, cellsPerColumn: [2]),
        GridExample(windowCount: 2, rows: 1, columns: 3, cellsPerColumn: [1, 1]),
        GridExample(windowCount: 4, rows: 2, columns: 2, cellsPerColumn: [2, 2]),
        GridExample(windowCount: 1, rows: 2, columns: 2, cellsPerColumn: [1]),
        GridExample(windowCount: 3, rows: 1, columns: 3, cellsPerColumn: [1, 1, 1]),
        GridExample(windowCount: 3, rows: 3, columns: 1, cellsPerColumn: [3]),
        GridExample(windowCount: 6, rows: 2, columns: 2, cellsPerColumn: [2, 2]),
        GridExample(windowCount: 4, rows: 3, columns: 3, cellsPerColumn: [3, 1]),
        GridExample(windowCount: 7, rows: 3, columns: 3, cellsPerColumn: [3, 3, 1]),
    ]

    /// An odd-sized visible frame at the origin.
    static let odd = CGRect(x: 0, y: 0, width: 1001, height: 501)

    static let visibleFrames = [TileLayoutSupport.primaryVisible, TileLayoutSupport.oddVisible, odd]

    /// A column layout with unequal fractions, built by hand: the transpose of
    /// `TileLayoutSupport.handBuilt`.
    static let handBuilt = TileLayout(columns: [
        TileLayout.Column(width: 0.3, heights: [0.25, 0.75]),
        TileLayout.Column(width: 0.7, heights: [1]),
    ])

    /// A layout to tile one visible frame.
    struct Scene: Sendable, CustomTestStringConvertible {
        let name: String
        let layout: TileLayout
        let visible: CGRect

        var cellsPerColumn: [Int] { layout.columns.map { $0.heights.count } }

        var testDescription: String { "\(name) on \(visible)" }
    }

    /// Every column-first grid example and the hand-built column layout, on every visible frame.
    static let scenes: [Scene] = visibleFrames.flatMap { visible in
        var scenes = gridExamples.map { Scene(name: $0.testDescription, layout: $0.layout, visible: visible) }
        scenes.append(Scene(name: "hand-built column layout", layout: handBuilt, visible: visible))
        return scenes
    }

    /// Every check that `frames` tile `visible` exactly, numbered column by column with
    /// `cellsPerColumn` cells in each column. One message per violation.
    static func tilingViolations(
        _ frames: [CGRect], cellsPerColumn: [Int], visible: CGRect
    ) -> [String] {
        // The checks that do not depend on the numbering run on the frames themselves.
        let anyOrder = TileLayoutSupport.wholeNumberViolations(frames)
            + TileLayoutSupport.overlapViolations(frames)
            + TileLayoutSupport.coverageViolations(frames, visible: visible)
            + TileLayoutSupport.areaViolations(frames, visible: visible)
            + TileLayoutSupport.sharedEdgeViolations(frames, visible: visible)
        // The numbering: the transposed frames are in row-major order of the transposed layout.
        return anyOrder
            + TileLayoutSupport.rowMajorViolations(frames.map(transposed), cellsPerRow: cellsPerColumn)
    }
}

@Suite("TileLayout column layouts")
struct TileLayoutColumnTests {
    typealias Example = ColumnLayoutSupport.GridExample

    // MARK: Representation

    @Test("a column layout reads back as its columns, and has no rows")
    func columnsRoundTrip() {
        let layout = ColumnLayoutSupport.handBuilt
        #expect(layout.orientation == .columns)
        #expect(layout.columns == [
            TileLayout.Column(width: 0.3, heights: [0.25, 0.75]),
            TileLayout.Column(width: 0.7, heights: [1]),
        ])
        #expect(layout.rows.isEmpty)
        #expect(layout.windowCount == 3)
    }

    @Test("a row layout is row based and has no columns")
    func rowLayoutHasNoColumns() {
        let layout = TileLayoutSupport.handBuilt
        #expect(layout.orientation == .rows)
        #expect(layout.columns.isEmpty)
        #expect(layout.rows.count == 2)
    }

    @Test("transposing swaps rows and columns, and transposing twice is the identity")
    func transposing() {
        let rows = TileLayoutSupport.handBuilt
        let columns = ColumnLayoutSupport.handBuilt
        #expect(rows.transposed == columns)
        #expect(columns.transposed == rows)
        #expect(rows.transposed.transposed == rows)
    }

    @Test("a row layout and a column layout with the same numbers are different layouts")
    func orientationMatters() {
        let rows = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.5, 0.5])])
        let columns = TileLayout(columns: [TileLayout.Column(width: 1, heights: [0.5, 0.5])])
        #expect(rows != columns)
    }

    // MARK: Coding

    private func encoded(_ layout: TileLayout) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(layout), as: UTF8.self)
    }

    @Test("a row layout is encoded as it always was, with the key rows")
    func rowLayoutEncoding() throws {
        let layout = TileLayout(rows: [TileLayout.Row(height: 1, widths: [0.5, 0.5])])
        #expect(try encoded(layout) == #"{"rows":[{"height":1,"widths":[0.5,0.5]}]}"#)
    }

    @Test("a column layout is encoded with the key columns")
    func columnLayoutEncoding() throws {
        let layout = TileLayout(columns: [TileLayout.Column(width: 1, heights: [0.5, 0.5])])
        #expect(try encoded(layout) == #"{"columns":[{"heights":[0.5,0.5],"width":1}]}"#)
    }

    @Test("a column-first grid and a hand-built column layout survive a round trip")
    func roundTrip() throws {
        let layouts = ColumnLayoutSupport.gridExamples.map(\.layout) + [ColumnLayoutSupport.handBuilt]
        for layout in layouts {
            let decoded = try JSONDecoder().decode(TileLayout.self, from: JSONEncoder().encode(layout))
            #expect(decoded == layout)
            #expect(decoded.orientation == .columns)
        }
    }

    @Test("a layout with both rows and columns, or with neither, does not decode")
    func ambiguousDecoding() {
        let both = #"{"rows":[{"height":1,"widths":[1]}],"columns":[{"width":1,"heights":[1]}]}"#
        let neither = "{}"
        for text in [both, neither] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(TileLayout.self, from: Data(text.utf8))
            }
        }
    }

    // MARK: Column-first grids

    @Test("windows per column follow the fill rule", arguments: ColumnLayoutSupport.gridExamples)
    func cellsPerColumn(example: Example) {
        let layout = example.layout
        #expect(layout.orientation == .columns)
        #expect(layout.columns.map { $0.heights.count } == example.cellsPerColumn)
        #expect(layout.windowCount == example.cellsPerColumn.reduce(0, +))
    }

    @Test(
        "used columns have equal widths, and the windows of a column have equal heights",
        arguments: ColumnLayoutSupport.gridExamples)
    func equalFractions(example: Example) {
        let usedColumns = example.cellsPerColumn.count
        for column in example.layout.columns {
            #expect(column.width == 1 / Double(usedColumns))
            for height in column.heights {
                #expect(height == 1 / Double(column.heights.count))
            }
        }
    }

    @Test("a column-first grid is valid", arguments: ColumnLayoutSupport.gridExamples)
    func validGrids(example: Example) throws {
        try example.layout.validate()
    }

    @Test("rows first is the default, and the explicit rows-first grid is the same layout")
    func rowsFirstIsTheDefault() {
        for example in TileLayoutSupport.gridExamples {
            let explicit = TileLayout.grid(
                windowCount: example.windowCount, rows: example.rows, columns: example.columns,
                fillOrder: .rows)
            #expect(explicit == example.layout)
            #expect(explicit.orientation == .rows)
        }
    }

    @Test("3 in 2×2 columns first: the two most recent windows stacked on the left, the third full height on the right")
    func threeInTwoByTwo() {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns)
        #expect(layout.columns == [
            TileLayout.Column(width: 0.5, heights: [0.5, 0.5]),
            TileLayout.Column(width: 0.5, heights: [1]),
        ])
        // Cell 0 top left, cell 1 bottom left, cell 2 the whole right column.
        #expect(layout.frames(in: TileLayoutSupport.primaryVisible) == [
            CGRect(x: 0, y: 25, width: 720, height: 438),
            CGRect(x: 0, y: 463, width: 720, height: 437),
            CGRect(x: 720, y: 25, width: 720, height: 875),
        ])
    }

    @Test("4 in 2×2 has the frames of rows first, with window 2 at the bottom left")
    func fourInTwoByTwoFrames() {
        let visible = ColumnLayoutSupport.odd
        let columnFirst = TileLayout.grid(windowCount: 4, rows: 2, columns: 2, fillOrder: .columns)
            .frames(in: visible)
        let rowFirst = TileLayout.grid(windowCount: 4, rows: 2, columns: 2).frames(in: visible)
        // The same four rectangles; cells 1 and 2 swap places.
        #expect(columnFirst[0] == rowFirst[0])
        #expect(columnFirst[1] == rowFirst[2])
        #expect(columnFirst[2] == rowFirst[1])
        #expect(columnFirst[3] == rowFirst[3])
        #expect(columnFirst[1].minX == visible.minX && columnFirst[1].minY > visible.minY)
    }

    @Test("2 in 2×2 columns first are stacked top and bottom at full width")
    func twoInTwoByTwoStacked() {
        let layout = TileLayout.grid(windowCount: 2, rows: 2, columns: 2, fillOrder: .columns)
        #expect(layout.frames(in: ColumnLayoutSupport.odd) == [
            CGRect(x: 0, y: 0, width: 1001, height: 251),
            CGRect(x: 0, y: 251, width: 1001, height: 250),
        ])
    }

    @Test("2 in 1×3 columns first are side by side, each the full height")
    func twoInOneByThree() {
        let layout = TileLayout.grid(windowCount: 2, rows: 1, columns: 3, fillOrder: .columns)
        #expect(layout.frames(in: ColumnLayoutSupport.odd) == [
            CGRect(x: 0, y: 0, width: 501, height: 501),
            CGRect(x: 501, y: 0, width: 500, height: 501),
        ])
    }

    @Test("3 in 2×2 columns first on an odd, negative-origin visible frame, frame by frame")
    func threeInTwoByTwoOddFrame() {
        let layout = TileLayout.grid(windowCount: 3, rows: 2, columns: 2, fillOrder: .columns)
        // x: -1728 + 863.5 rounds half up to -864, the right edge -1 is exact.
        // y: 355 + 542.5 rounds half up to 898, the bottom edge is 1440.
        #expect(layout.frames(in: TileLayoutSupport.oddVisible) == [
            CGRect(x: -1728, y: 355, width: 864, height: 543),
            CGRect(x: -1728, y: 898, width: 864, height: 542),
            CGRect(x: -864, y: 355, width: 863, height: 1085),
        ])
    }

    @Test("5 in 2×3 columns first on an odd visible frame, frame by frame")
    func fiveInTwoByThreeOddFrame() {
        let layout = TileLayout.grid(windowCount: 5, rows: 2, columns: 3, fillOrder: .columns)
        // Column edges: 1001 / 3 = 333.67 -> 334, 667.33 -> 667. Row edge: 250.5 -> 251.
        #expect(layout.frames(in: ColumnLayoutSupport.odd) == [
            CGRect(x: 0, y: 0, width: 334, height: 251),
            CGRect(x: 0, y: 251, width: 334, height: 250),
            CGRect(x: 334, y: 0, width: 333, height: 251),
            CGRect(x: 334, y: 251, width: 333, height: 250),
            CGRect(x: 667, y: 0, width: 334, height: 501),
        ])
    }

    @Test("a huge column-first grid does not overflow when computing its capacity")
    func hugeGrid() {
        let layout = TileLayout.grid(
            windowCount: 5, rows: Int.max, columns: Int.max, fillOrder: .columns)
        // Every column holds Int.max windows, so all five share the first column.
        #expect(layout.columns == [TileLayout.Column(width: 1, heights: [0.2, 0.2, 0.2, 0.2, 0.2])])
    }

    @Test("windowCount below 1 is a precondition failure when filling columns first")
    func windowCountPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = TileLayout.grid(windowCount: 0, rows: 2, columns: 2, fillOrder: .columns)
        }
    }

    @Test("rows below 1 is a precondition failure when filling columns first")
    func rowsPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = TileLayout.grid(windowCount: 1, rows: 0, columns: 2, fillOrder: .columns)
        }
    }

    @Test("columns below 1 is a precondition failure when filling columns first")
    func columnsPrecondition() async {
        await #expect(processExitsWith: .failure) {
            _ = TileLayout.grid(windowCount: 1, rows: 2, columns: 0, fillOrder: .columns)
        }
    }

    // MARK: Validation

    /// A layout that `validate()` rejects, with the error it should throw.
    struct Rejected: Sendable, CustomTestStringConvertible {
        let name: String
        let layout: TileLayout
        let error: TileLayoutError

        var testDescription: String { name }
    }

    private static func column(_ width: Double, _ heights: [Double]) -> TileLayout.Column {
        TileLayout.Column(width: width, heights: heights)
    }

    /// The transposed counterpart of every case of `TileLayoutValidationTests.rejected`.
    static let rejected: [Rejected] = [
        Rejected(name: "no columns", layout: TileLayout(columns: []), error: .noColumns),
        Rejected(
            name: "an empty column",
            layout: TileLayout(columns: [column(1, [])]),
            error: .emptyColumn(column: 0)),
        Rejected(
            name: "an empty second column",
            layout: TileLayout(columns: [column(0.5, [1]), column(0.5, [])]),
            error: .emptyColumn(column: 1)),
        Rejected(
            name: "a zero width",
            layout: TileLayout(columns: [column(0, [1]), column(1, [1])]),
            error: .invalidColumnWidth(column: 0)),
        Rejected(
            name: "a negative width",
            layout: TileLayout(columns: [column(-0.5, [1]), column(1.5, [1])]),
            error: .invalidColumnWidth(column: 0)),
        Rejected(
            name: "a NaN width",
            layout: TileLayout(columns: [column(.nan, [1])]),
            error: .invalidColumnWidth(column: 0)),
        Rejected(
            name: "an infinite width",
            layout: TileLayout(columns: [column(.infinity, [1])]),
            error: .invalidColumnWidth(column: 0)),
        Rejected(
            name: "a zero height",
            layout: TileLayout(columns: [column(1, [0, 1])]),
            error: .invalidCellHeight(column: 0, row: 0)),
        Rejected(
            name: "a negative height",
            layout: TileLayout(columns: [column(1, [1.5, -0.5])]),
            error: .invalidCellHeight(column: 0, row: 1)),
        Rejected(
            name: "a NaN height",
            layout: TileLayout(columns: [column(1, [.nan])]),
            error: .invalidCellHeight(column: 0, row: 0)),
        Rejected(
            name: "an infinite height",
            layout: TileLayout(columns: [column(1, [.infinity])]),
            error: .invalidCellHeight(column: 0, row: 0)),
        Rejected(
            name: "widths that sum to less than 1",
            layout: TileLayout(columns: [column(0.5, [1]), column(0.4, [1])]),
            error: .columnWidthsDoNotSumToOne),
        Rejected(
            name: "widths that sum to more than 1",
            layout: TileLayout(columns: [column(0.6, [1]), column(0.6, [1])]),
            error: .columnWidthsDoNotSumToOne),
        Rejected(
            name: "heights that sum to less than 1",
            layout: TileLayout(columns: [column(1, [0.5, 0.4])]),
            error: .cellHeightsDoNotSumToOne(column: 0)),
        Rejected(
            name: "heights that sum to more than 1 in a later column",
            layout: TileLayout(columns: [column(0.5, [1]), column(0.5, [0.6, 0.6])]),
            error: .cellHeightsDoNotSumToOne(column: 1)),
    ]

    @Test("the hand-built column layout is valid")
    func handBuiltIsValid() throws {
        try ColumnLayoutSupport.handBuilt.validate()
    }

    @Test("an invalid column layout is rejected with the matching error", arguments: rejected)
    func rejects(example: Rejected) {
        #expect(throws: example.error) {
            try example.layout.validate()
        }
    }

    @Test("the sums may miss 1 by up to 1e-9, for columns as for rows")
    func sumTolerance() {
        let withinTolerance = TileLayout(columns: [
            Self.column(0.5, [0.5, 0.5 - 1e-10]),
            Self.column(0.5 + 1e-10, [1]),
        ])
        #expect((try? withinTolerance.validate()) != nil)

        let heightsBeyond = TileLayout(columns: [
            Self.column(0.5, [0.5, 0.5 - 1e-8]),
            Self.column(0.5, [1]),
        ])
        #expect(throws: TileLayoutError.cellHeightsDoNotSumToOne(column: 0)) {
            try heightsBeyond.validate()
        }

        let widthsBeyond = TileLayout(columns: [
            Self.column(0.5, [1]),
            Self.column(0.5 + 1e-8, [1]),
        ])
        #expect(throws: TileLayoutError.columnWidthsDoNotSumToOne) {
            try widthsBeyond.validate()
        }
    }

    @Test("a layout is valid as a column layout exactly when its transpose is valid as a row layout")
    func validityFollowsTheTranspose() {
        for example in TileLayoutValidationTests.rejected {
            #expect((try? example.layout.transposed.validate()) == nil, "\(example.name), transposed")
        }
        for example in TileLayoutSupport.gridExamples {
            #expect((try? example.layout.transposed.validate()) != nil, "\(example.testDescription), transposed")
        }
    }
}

@Suite("TileLayout column frames")
struct TileLayoutColumnFramesTests {
    typealias Scene = ColumnLayoutSupport.Scene

    @Test("cells tile the visible frame exactly and are numbered column by column", arguments: ColumnLayoutSupport.scenes)
    func tilesExactly(scene: Scene) {
        let frames = scene.layout.frames(in: scene.visible)
        let violations = ColumnLayoutSupport.tilingViolations(
            frames, cellsPerColumn: scene.cellsPerColumn, visible: scene.visible)
        #expect(violations.isEmpty, "\(violations)")
    }

    @Test(
        "the frames of a column layout are the transposed frames of its transposed row layout",
        arguments: ColumnLayoutSupport.scenes)
    func transposeProperty(scene: Scene) {
        let direct = scene.layout.frames(in: scene.visible)
        let viaRows = scene.layout.transposed
            .frames(in: ColumnLayoutSupport.transposed(scene.visible))
            .map(ColumnLayoutSupport.transposed)
        #expect(direct == viaRows)
    }

    @Test(
        "the property holds the other way round: a row layout's frames are its transpose's frames, transposed",
        arguments: TileLayoutSupport.scenes)
    func transposePropertyOfRowLayouts(scene: TileLayoutSupport.Scene) {
        let direct = scene.layout.frames(in: scene.visible)
        let viaColumns = scene.layout.transposed
            .frames(in: ColumnLayoutSupport.transposed(scene.visible))
            .map(ColumnLayoutSupport.transposed)
        #expect(direct == viaColumns)
    }

    @Test("the hand-built column layout, frame by frame")
    func handBuiltFrames() {
        // x: 0.3 * 1440 = 432. y: 25 + 0.25 * 875 = 243.75, which rounds to 244.
        #expect(ColumnLayoutSupport.handBuilt.frames(in: TileLayoutSupport.primaryVisible) == [
            CGRect(x: 0, y: 25, width: 432, height: 219),
            CGRect(x: 0, y: 244, width: 432, height: 656),
            CGRect(x: 432, y: 25, width: 1008, height: 875),
        ])
    }
}
