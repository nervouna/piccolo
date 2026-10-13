import Foundation
import Testing

@testable import PiccoloCore

@Suite("Config validation")
struct ConfigValidationTests {
    private func isValid(_ rect: FractionalRect) -> Bool {
        (try? rect.validate()) != nil
    }

    private func isValid(_ grid: GridSpec) -> Bool {
        (try? grid.validate()) != nil
    }

    private func isValid(_ shortcut: Shortcut) -> Bool {
        (try? shortcut.validate()) != nil
    }

    private func isValid(resizeStep: Double) -> Bool {
        (try? Config(resizeStep: resizeStep).validate()) != nil
    }

    // MARK: FractionalRect

    @Test("a rect may cover the whole screen or touch its far edges")
    func rectOnEdges() {
        #expect(isValid(FractionalRect(x: 0, y: 0, width: 1, height: 1)))
        #expect(isValid(FractionalRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        #expect(isValid(FractionalRect(x: 0.25, y: 0, width: 0.75, height: 1)))
    }

    @Test("x and y must not be negative")
    func rectOriginNotNegative() {
        #expect(isValid(FractionalRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        #expect(!isValid(FractionalRect(x: -0.000001, y: 0, width: 0.5, height: 0.5)))
        #expect(!isValid(FractionalRect(x: 0, y: -0.000001, width: 0.5, height: 0.5)))
        #expect(throws: ValidationError.outOfRange(field: "x", rule: "must be >= 0")) {
            try FractionalRect(x: -1, y: 0, width: 0.5, height: 0.5).validate()
        }
        #expect(throws: ValidationError.outOfRange(field: "y", rule: "must be >= 0")) {
            try FractionalRect(x: 0, y: -1, width: 0.5, height: 0.5).validate()
        }
    }

    @Test("width and height must be greater than zero")
    func rectSizePositive() {
        #expect(isValid(FractionalRect(x: 0, y: 0, width: 0.000001, height: 0.000001)))
        #expect(!isValid(FractionalRect(x: 0, y: 0, width: 0, height: 0.5)))
        #expect(!isValid(FractionalRect(x: 0, y: 0, width: 0.5, height: 0)))
        #expect(!isValid(FractionalRect(x: 0, y: 0, width: -0.5, height: 0.5)))
        #expect(!isValid(FractionalRect(x: 0, y: 0, width: 0.5, height: -0.5)))
        #expect(throws: ValidationError.outOfRange(field: "width", rule: "must be > 0")) {
            try FractionalRect(x: 0, y: 0, width: 0, height: 0.5).validate()
        }
        #expect(throws: ValidationError.outOfRange(field: "height", rule: "must be > 0")) {
            try FractionalRect(x: 0, y: 0, width: 0.5, height: 0).validate()
        }
    }

    @Test("x + width and y + height may exceed 1 only by the 1e-9 tolerance")
    func rectEdgesWithinTolerance() {
        // Exactly 1 is allowed.
        #expect(isValid(FractionalRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        // Rounding noise well inside the tolerance is allowed.
        #expect(isValid(FractionalRect(x: 0, y: 0, width: 1 + 1e-10, height: 1)))
        #expect(isValid(FractionalRect(x: 0, y: 0.5, width: 1, height: 0.5 + 1e-10)))
        // Clearly beyond the tolerance is not.
        #expect(!isValid(FractionalRect(x: 0, y: 0, width: 1 + 1e-8, height: 1)))
        #expect(!isValid(FractionalRect(x: 0, y: 0, width: 1, height: 1 + 1e-8)))
        #expect(!isValid(FractionalRect(x: 0.5, y: 0, width: 0.5001, height: 1)))
        #expect(!isValid(FractionalRect(x: 0, y: 0.5, width: 1, height: 0.5001)))
        #expect(throws: ValidationError.outOfRange(field: "x + width", rule: "must be <= 1")) {
            try FractionalRect(x: 0.5, y: 0, width: 0.75, height: 1).validate()
        }
        #expect(throws: ValidationError.outOfRange(field: "y + height", rule: "must be <= 1")) {
            try FractionalRect(x: 0, y: 0.5, width: 1, height: 0.75).validate()
        }
    }

    @Test("every rect value must be finite")
    func rectFinite() {
        #expect(throws: ValidationError.notFinite(field: "x")) {
            try FractionalRect(x: .nan, y: 0, width: 0.5, height: 0.5).validate()
        }
        #expect(throws: ValidationError.notFinite(field: "y")) {
            try FractionalRect(x: 0, y: .infinity, width: 0.5, height: 0.5).validate()
        }
        #expect(throws: ValidationError.notFinite(field: "width")) {
            try FractionalRect(x: 0, y: 0, width: -.infinity, height: 0.5).validate()
        }
        #expect(throws: ValidationError.notFinite(field: "height")) {
            try FractionalRect(x: 0, y: 0, width: 0.5, height: .nan).validate()
        }
    }

    // MARK: GridSpec

    @Test("rows and columns must be at least 1")
    func gridDimensions() {
        #expect(isValid(GridSpec(count: 1, rows: 1, columns: 1)))
        #expect(!isValid(GridSpec(count: 1, rows: 0, columns: 1)))
        #expect(!isValid(GridSpec(count: 1, rows: 1, columns: 0)))
        #expect(!isValid(GridSpec(count: 1, rows: -1, columns: 1)))
        #expect(throws: ValidationError.outOfRange(field: "rows", rule: "must be >= 1")) {
            try GridSpec(count: 1, rows: 0, columns: 1).validate()
        }
        #expect(throws: ValidationError.outOfRange(field: "columns", rule: "must be >= 1")) {
            try GridSpec(count: 1, rows: 1, columns: 0).validate()
        }
    }

    @Test("count must be between 1 and rows times columns")
    func gridCount() {
        #expect(isValid(GridSpec(count: 1, rows: 2, columns: 2)))
        #expect(isValid(GridSpec(count: 4, rows: 2, columns: 2)))
        #expect(!isValid(GridSpec(count: 0, rows: 2, columns: 2)))
        #expect(!isValid(GridSpec(count: -1, rows: 2, columns: 2)))
        #expect(!isValid(GridSpec(count: 5, rows: 2, columns: 2)))
        #expect(throws: ValidationError.outOfRange(field: "count", rule: "must be >= 1")) {
            try GridSpec(count: 0, rows: 2, columns: 2).validate()
        }
        #expect(throws: ValidationError.outOfRange(field: "count", rule: "must be <= rows * columns")) {
            try GridSpec(count: 5, rows: 2, columns: 2).validate()
        }
    }

    @Test("a very large grid is checked without overflowing")
    func gridOverflow() {
        #expect(isValid(GridSpec(count: 1, rows: Int.max, columns: Int.max)))
        #expect(isValid(GridSpec(count: 3, rows: Int.max, columns: 2)))
    }

    // MARK: Shortcut

    @Test("a key code must not be negative")
    func keyCodeNotNegative() {
        #expect(isValid(Shortcut(keyCode: 0, modifiers: [.command])))
        #expect(isValid(Shortcut(keyCode: 123, modifiers: [.control, .option])))
        #expect(!isValid(Shortcut(keyCode: -1, modifiers: [.command])))
        #expect(throws: ValidationError.outOfRange(field: "keyCode", rule: "must be >= 0")) {
            try Shortcut(keyCode: -1, modifiers: []).validate()
        }
    }

    // MARK: resizeStep

    @Test("resizeStep must be greater than 0 and at most 0.5")
    func resizeStepRange() {
        #expect(Config.defaultResizeStep == 0.05)
        #expect(isValid(resizeStep: 0.05))
        #expect(isValid(resizeStep: 0.000001))
        #expect(isValid(resizeStep: 0.5))
        #expect(!isValid(resizeStep: 0))
        #expect(!isValid(resizeStep: -0.05))
        #expect(!isValid(resizeStep: 0.5000001))
        #expect(!isValid(resizeStep: 0.6))
        #expect(throws: ValidationError.outOfRange(field: "resizeStep", rule: "must be > 0 and <= 0.5")) {
            try Config(resizeStep: 0).validate()
        }
    }

    @Test("resizeStep must be finite")
    func resizeStepFinite() {
        #expect(throws: ValidationError.notFinite(field: "resizeStep")) {
            try Config(resizeStep: .nan).validate()
        }
        #expect(throws: ValidationError.notFinite(field: "resizeStep")) {
            try Config(resizeStep: .infinity).validate()
        }
    }

    // MARK: Action, KeyBinding and Config

    @Test("an action is valid when its frame or grid is")
    func actionValidity() {
        #expect((try? Action.placeWindow(.preset(.center)).validate()) != nil)
        #expect((try? Action.moveDivider(.up).validate()) != nil)
        #expect((try? Action.placeWindow(.custom(FractionalRect(x: 0, y: 0, width: 2, height: 1))).validate()) == nil)
        #expect((try? Action.arrangeGrid(GridSpec(count: 9, rows: 2, columns: 2)).validate()) == nil)
    }

    @Test("a config with a version other than 1 is invalid")
    func unsupportedVersion() {
        #expect(throws: ValidationError.unsupportedVersion(2)) {
            try Config(version: 2).validate()
        }
        #expect(throws: ValidationError.unsupportedVersion(0)) {
            try Config(version: 0).validate()
        }
    }

    @Test("a config with two bindings sharing an ID is invalid")
    func duplicateIDs() {
        let config = Config(bindings: [
            KeyBinding(id: Fixture.idA, action: .moveToDisplay(.next)),
            KeyBinding(id: Fixture.idA, action: .moveToDisplay(.previous)),
        ])
        #expect(throws: ValidationError.duplicateBindingID(Fixture.idA)) {
            try config.validate()
        }
    }

    @Test("a config with an invalid binding is invalid")
    func invalidBindingMakesConfigInvalid() {
        let bad = KeyBinding(
            id: Fixture.idB,
            action: .placeWindow(.custom(FractionalRect(x: 0.9, y: 0, width: 0.2, height: 1))))
        #expect(throws: ValidationError.outOfRange(field: "x + width", rule: "must be <= 1")) {
            try Config(bindings: [KeyBinding(id: Fixture.idA, action: .moveDivider(.left)), bad]).validate()
        }
    }

    @Test("the default config and one binding of each kind are valid")
    func validExamples() {
        #expect((try? Config.default.validate()) != nil)
        #expect((try? Config(resizeStep: 0.5, bindings: allKindsBindings).validate()) != nil)
    }
}
