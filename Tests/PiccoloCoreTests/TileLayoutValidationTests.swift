import Testing

@testable import PiccoloCore

@Suite("TileLayout validation")
struct TileLayoutValidationTests {
    /// A layout that `validate()` rejects, with the error it should throw.
    struct Rejected: Sendable, CustomTestStringConvertible {
        let name: String
        let layout: TileLayout
        let error: TileLayoutError

        var testDescription: String { name }
    }

    private static func row(_ height: Double, _ widths: [Double]) -> TileLayout.Row {
        TileLayout.Row(height: height, widths: widths)
    }

    static let rejected: [Rejected] = [
        Rejected(name: "no rows", layout: TileLayout(rows: []), error: .noRows),
        Rejected(
            name: "an empty row",
            layout: TileLayout(rows: [row(1, [])]),
            error: .emptyRow(row: 0)),
        Rejected(
            name: "an empty second row",
            layout: TileLayout(rows: [row(0.5, [1]), row(0.5, [])]),
            error: .emptyRow(row: 1)),
        Rejected(
            name: "a zero height",
            layout: TileLayout(rows: [row(0, [1]), row(1, [1])]),
            error: .invalidHeight(row: 0)),
        Rejected(
            name: "a negative height",
            layout: TileLayout(rows: [row(-0.5, [1]), row(1.5, [1])]),
            error: .invalidHeight(row: 0)),
        Rejected(
            name: "a NaN height",
            layout: TileLayout(rows: [row(.nan, [1])]),
            error: .invalidHeight(row: 0)),
        Rejected(
            name: "an infinite height",
            layout: TileLayout(rows: [row(.infinity, [1])]),
            error: .invalidHeight(row: 0)),
        Rejected(
            name: "a zero width",
            layout: TileLayout(rows: [row(1, [0, 1])]),
            error: .invalidWidth(row: 0, column: 0)),
        Rejected(
            name: "a negative width",
            layout: TileLayout(rows: [row(1, [1.5, -0.5])]),
            error: .invalidWidth(row: 0, column: 1)),
        Rejected(
            name: "a NaN width",
            layout: TileLayout(rows: [row(1, [.nan])]),
            error: .invalidWidth(row: 0, column: 0)),
        Rejected(
            name: "an infinite width",
            layout: TileLayout(rows: [row(1, [.infinity])]),
            error: .invalidWidth(row: 0, column: 0)),
        Rejected(
            name: "heights that sum to less than 1",
            layout: TileLayout(rows: [row(0.5, [1]), row(0.4, [1])]),
            error: .heightsDoNotSumToOne),
        Rejected(
            name: "heights that sum to more than 1",
            layout: TileLayout(rows: [row(0.6, [1]), row(0.6, [1])]),
            error: .heightsDoNotSumToOne),
        Rejected(
            name: "widths that sum to less than 1",
            layout: TileLayout(rows: [row(1, [0.5, 0.4])]),
            error: .widthsDoNotSumToOne(row: 0)),
        Rejected(
            name: "widths that sum to more than 1 in a later row",
            layout: TileLayout(rows: [row(0.5, [1]), row(0.5, [0.6, 0.6])]),
            error: .widthsDoNotSumToOne(row: 1)),
    ]

    @Test("every built grid is valid", arguments: TileLayoutSupport.gridExamples)
    func builtGridsAreValid(example: TileLayoutSupport.GridExample) throws {
        try example.layout.validate()
    }

    @Test("the hand-built layout with unequal fractions is valid")
    func handBuiltIsValid() throws {
        try TileLayoutSupport.handBuilt.validate()
    }

    @Test("an invalid layout is rejected with the matching error", arguments: rejected)
    func rejects(example: Rejected) {
        #expect(throws: example.error) {
            try example.layout.validate()
        }
    }

    @Test("heights and widths may miss 1 by up to 1e-9")
    func sumTolerance() {
        let withinTolerance = TileLayout(rows: [
            Self.row(0.5, [0.5, 0.5 - 1e-10]),
            Self.row(0.5 + 1e-10, [1]),
        ])
        #expect((try? withinTolerance.validate()) != nil)

        let beyondTolerance = TileLayout(rows: [
            Self.row(0.5, [0.5, 0.5 - 1e-8]),
            Self.row(0.5, [1]),
        ])
        #expect(throws: TileLayoutError.widthsDoNotSumToOne(row: 0)) {
            try beyondTolerance.validate()
        }

        let heightBeyondTolerance = TileLayout(rows: [
            Self.row(0.5, [1]),
            Self.row(0.5 + 1e-8, [1]),
        ])
        #expect(throws: TileLayoutError.heightsDoNotSumToOne) {
            try heightBeyondTolerance.validate()
        }
    }
}
