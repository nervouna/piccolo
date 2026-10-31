import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

/// The grid and custom area rows: what is wrong with a layout, adding and editing one, and the request
/// to open the sheet for one.
@MainActor
@Suite("Keymap layouts")
struct KeymapLayoutTests {
    private let english = AppLanguage.en.textBundle!

    private static func area(
        _ x: Double = 0.25, _ y: Double = 0, _ width: Double = 0.5, _ height: Double = 1
    ) -> Action {
        .placeWindow(.custom(FractionalRect(x: x, y: y, width: width, height: height)))
    }

    private static func grid(_ count: Int, _ rows: Int, _ columns: Int) -> Action {
        .arrangeGrid(GridSpec(count: count, rows: rows, columns: columns))
    }

    private let left = KeyBinding(action: .placeWindow(.preset(.leftHalf)), shortcut: UIFixture.f13)
    private let grid = KeyBinding(action: KeymapLayoutTests.grid(4, 2, 2), shortcut: UIFixture.f14)
    private let area = KeyBinding(action: KeymapLayoutTests.area(), shortcut: UIFixture.f15)

    private func make(
        _ bindings: [KeyBinding]? = nil
    ) -> (model: SettingsModel, backend: InMemorySettingsBackend) {
        let backend = InMemorySettingsBackend(config: Config(bindings: bindings ?? [left, grid, area]))
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage())
        return (model, backend)
    }

    private func problem(_ action: Action, editing id: UUID? = nil, in bindings: [KeyBinding] = []) -> LayoutProblem? {
        LayoutProblems.first(for: action, editing: id, in: bindings, bundle: english)
    }

    // MARK: What is wrong with a layout

    @Test("a valid grid or custom area has no problem")
    func validLayouts() {
        #expect(problem(Self.area()) == nil)
        #expect(problem(Self.area(0, 0, 1, 1)) == nil)
        #expect(problem(Self.area(0.5, 0.5, 0.5, 0.5)) == nil)
        #expect(problem(Self.grid(4, 2, 2)) == nil)
        #expect(problem(Self.grid(1, 1, 1)) == nil)
        #expect(problem(Self.grid(3, 2, 2)) == nil)
    }

    @Test("a built-in action has no problem")
    func builtInAction() {
        #expect(problem(.restoreWindow) == nil)
        #expect(problem(.placeWindow(.preset(.leftHalf))) == nil)
    }

    @Test("each rule of the config names the fields it is about, with the sentence of the window")
    func fieldsOfEachRule() {
        let cases: [(action: Action, fields: Set<LayoutField>, error: ValidationError)] = [
            (Self.area(-0.1), [.left], .outOfRange(field: "x", rule: "must be >= 0")),
            (Self.area(0.25, -0.1), [.top], .outOfRange(field: "y", rule: "must be >= 0")),
            (Self.area(0.25, 0, 0), [.width], .outOfRange(field: "width", rule: "must be > 0")),
            (Self.area(0.25, 0, 0.5, 0), [.height], .outOfRange(field: "height", rule: "must be > 0")),
            (Self.area(0.75, 0, 0.5), [.left, .width], .outOfRange(field: "x + width", rule: "must be <= 1")),
            (Self.area(0, 0.75, 1, 0.5), [.top, .height], .outOfRange(field: "y + height", rule: "must be <= 1")),
            (Self.area(.nan), [.left], .notFinite(field: "x")),
            (Self.area(0.25, 0, .infinity), [.width], .notFinite(field: "width")),
            (Self.grid(1, 0, 2), [.rows], .outOfRange(field: "rows", rule: "must be >= 1")),
            (Self.grid(1, 2, 0), [.columns], .outOfRange(field: "columns", rule: "must be >= 1")),
            (Self.grid(0, 2, 2), [.windows], .outOfRange(field: "count", rule: "must be >= 1")),
            (Self.grid(5, 2, 2), [.windows], .outOfRange(field: "count", rule: "must be <= rows * columns")),
        ]
        for item in cases {
            let found = problem(item.action)
            #expect(found?.fields == item.fields, "\(item.action): the fields are \(String(describing: found?.fields))")
            #expect(
                found?.message == SettingsMessages.describe(item.error, bundle: english),
                "\(item.action): the message is \(String(describing: found?.message))")
        }
    }

    @Test("the first problem is the one answered, in the order of the config's own validation")
    func firstProblem() {
        // Left is below 0 and the width is 0: left comes first.
        #expect(problem(Self.area(-1, 0, 0))?.fields == [.left])
        // Rows come before columns and the number of windows.
        #expect(problem(Self.grid(0, 0, 0))?.fields == [.rows])
        #expect(problem(Self.grid(0, 2, 0))?.fields == [.columns])
        // The number of windows comes last.
        #expect(problem(Self.grid(9, 2, 2))?.fields == [.windows])
    }

    @Test("an equal grid or custom area in another binding is a problem without fields")
    func duplicates() {
        let grid = KeyBinding(action: Self.grid(4, 2, 2))
        let area = KeyBinding(action: Self.area())
        let bindings = [grid, area]

        let duplicateGrid = problem(Self.grid(4, 2, 2), in: bindings)
        #expect(duplicateGrid?.fields == [])
        #expect(duplicateGrid?.message == "There is already a grid like this.")

        let duplicateArea = problem(Self.area(), in: bindings)
        #expect(duplicateArea?.fields == [])
        #expect(duplicateArea?.message == "There is already a custom area like this.")

        // Not equal: another count, another rectangle.
        #expect(problem(Self.grid(3, 2, 2), in: bindings) == nil)
        #expect(problem(Self.area(0.25, 0, 0.5, 0.5), in: bindings) == nil)
    }

    @Test("the binding being edited does not count as another one")
    func editingIsNotADuplicate() {
        let grid = KeyBinding(action: Self.grid(4, 2, 2))
        let other = KeyBinding(action: Self.grid(6, 2, 3))

        #expect(problem(Self.grid(4, 2, 2), editing: grid.id, in: [grid, other]) == nil)
        #expect(problem(Self.grid(6, 2, 3), editing: grid.id, in: [grid, other])?.message == "There is already a grid like this.")
    }

    @Test("the config's rules come before the rule about duplicates")
    func rulesBeforeDuplicates() {
        let invalid = Self.grid(5, 2, 2)
        let twin = KeyBinding(action: invalid)
        #expect(problem(invalid, in: [twin])?.fields == [.windows])
    }

    @Test("the two new messages are translated into every language")
    func duplicateMessagesAreTranslated() throws {
        for language in AppLanguage.languages where language != .en {
            let bundle = try #require(language.textBundle)
            let grid = SettingsMessages.duplicateGrid(bundle: bundle)
            let area = SettingsMessages.duplicateCustomArea(bundle: bundle)
            #expect(!grid.isEmpty && grid != "There is already a grid like this.", "\(language.rawValue): \(grid)")
            #expect(
                !area.isEmpty && area != "There is already a custom area like this.", "\(language.rawValue): \(area)")
        }
    }

    @Test("the model answers the problem of a layout")
    func modelLayoutProblem() {
        let (model, _) = make()
        #expect(model.layoutProblem(Self.grid(3, 2, 2), editing: nil) == nil)
        #expect(model.layoutProblem(Self.grid(4, 2, 2), editing: nil)?.message == SettingsMessages.duplicateGrid())
        #expect(model.layoutProblem(Self.grid(4, 2, 2), editing: grid.id) == nil)
        #expect(model.layoutProblem(Self.area(), editing: nil)?.message == SettingsMessages.duplicateCustomArea())
        #expect(model.layoutProblem(Self.area(), editing: area.id) == nil)
        #expect(model.layoutProblem(Self.area(2), editing: nil)?.fields == [.left, .width])
    }

    // MARK: Adding a layout

    @Test("adding a grid appends a binding without a shortcut, saves it and records it", arguments: [true, false])
    func addLayout(isGrid: Bool) throws {
        let (model, backend) = make()
        let action = isGrid ? Self.grid(3, 2, 2) : Self.area(0, 0, 0.5, 0.5)

        let id = try #require(model.addLayout(action))

        #expect(model.bindings.count == 4)
        #expect(model.bindings.last == KeyBinding(id: id, action: action, shortcut: nil))
        #expect(backend.saved.count == 1)
        #expect(backend.saved.last == model.config)
        #expect(model.recordingRow == .layout(id))
        #expect(model.isRecording)
        #expect(backend.isSuspended)
        #expect(model.error == nil)
        #expect(model.errorTarget == nil)
    }

    @Test("a new layout can be recorded at once")
    func addedLayoutRecords() throws {
        let (model, backend) = make()
        let id = try #require(model.addLayout(Self.grid(3, 2, 2)))

        model.record(Shortcut(keyCode: FunctionKey.f16, modifiers: UIFixture.hyper))

        #expect(model.binding(id)?.shortcut?.keyCode == FunctionKey.f16)
        #expect(backend.saved.count == 2)
        #expect(!model.isRecording)
    }

    @Test("adding something that is not a grid or a custom area is refused")
    func addLayoutWrongKind() {
        let (model, backend) = make()
        for action in [Action.placeWindow(.preset(.leftHalf)), .restoreWindow, .moveToDisplay(.next), .moveDivider(.left)] {
            #expect(model.addLayout(action) == nil)
            #expect(model.errorTarget == .window)
            #expect(model.error != nil)
        }
        #expect(backend.saved.isEmpty)
        #expect(model.bindings.count == 3)
        #expect(!model.isRecording)
    }

    @Test("a grid that exists is refused with the message, and nothing is saved")
    func addDuplicateGrid() {
        let (model, backend) = make()

        #expect(model.addLayout(Self.grid(4, 2, 2)) == nil)

        #expect(model.error == SettingsMessages.duplicateGrid())
        #expect(model.errorTarget == .window)
        #expect(backend.saved.isEmpty)
        #expect(model.bindings.count == 3)
        #expect(!model.isRecording)
    }

    @Test("a custom area that exists is refused with the message, and nothing is saved")
    func addDuplicateArea() {
        let (model, backend) = make()

        #expect(model.addLayout(Self.area()) == nil)

        #expect(model.error == SettingsMessages.duplicateCustomArea())
        #expect(model.errorTarget == .window)
        #expect(backend.saved.isEmpty)
    }

    @Test("an invalid layout is refused with the sentence of the window, and nothing is saved")
    func addInvalidLayout() {
        let (model, backend) = make()

        #expect(model.addLayout(Self.grid(5, 2, 2)) == nil)
        #expect(model.error == SettingsMessages.describe(.outOfRange(field: "count", rule: "must be <= rows * columns")))
        #expect(model.errorTarget == .window)

        #expect(model.addLayout(Self.area(0.75, 0, 0.5)) == nil)
        #expect(model.error == SettingsMessages.describe(.outOfRange(field: "x + width", rule: "must be <= 1")))
        #expect(backend.saved.isEmpty)
    }

    @Test("a layout the backend cannot save is not added and does not record")
    func addLayoutNotSaved() {
        let (model, backend) = make()
        backend.failure = "the disk is full"

        #expect(model.addLayout(Self.grid(3, 2, 2)) == nil)

        #expect(model.error?.contains("the disk is full") == true)
        #expect(model.errorTarget == .window)
        #expect(model.bindings.count == 3)
        #expect(!model.isRecording)
    }

    @Test("adding a layout drops a pending conflict")
    func addLayoutDropsConflict() throws {
        let (model, _) = make()
        model.beginRecording(.builtIn(.placeWindow(.preset(.rightHalf))))
        model.record(UIFixture.f13)
        #expect(model.pendingConflict != nil)

        _ = try #require(model.addLayout(Self.grid(3, 2, 2)))

        #expect(model.pendingConflict == nil)
    }

    // MARK: Updating a layout

    @Test("updating a grid replaces its action and keeps its binding, place and shortcut")
    func updateGrid() {
        let (model, backend) = make()

        #expect(model.updateLayout(grid.id, to: Self.grid(6, 2, 3)))

        #expect(model.bindings.map(\.id) == [left.id, grid.id, area.id])
        #expect(model.binding(grid.id) == KeyBinding(id: grid.id, action: Self.grid(6, 2, 3), shortcut: UIFixture.f14))
        #expect(backend.saved.count == 1)
        #expect(model.error == nil)
    }

    @Test("updating a custom area replaces its action")
    func updateArea() {
        let (model, _) = make()
        let changed = Self.area(0, 0, 0.5, 0.5)

        #expect(model.updateLayout(area.id, to: changed))

        #expect(model.binding(area.id)?.action == changed)
        #expect(model.binding(area.id)?.shortcut == UIFixture.f15)
    }

    @Test("updating a layout to what it is changes nothing")
    func updateToTheSame() {
        let (model, backend) = make()
        #expect(model.updateLayout(grid.id, to: Self.grid(4, 2, 2)))
        #expect(backend.saved.isEmpty)
    }

    @Test("a layout cannot become the layout of another binding")
    func updateToADuplicate() {
        let other = KeyBinding(action: Self.grid(6, 2, 3))
        let (model, backend) = make([left, grid, other])

        #expect(!model.updateLayout(grid.id, to: Self.grid(6, 2, 3)))

        #expect(model.error == SettingsMessages.duplicateGrid())
        #expect(model.errorTarget == .window)
        #expect(backend.saved.isEmpty)
        #expect(model.binding(grid.id)?.action == Self.grid(4, 2, 2))
    }

    @Test("an invalid layout is refused when updating")
    func updateInvalid() {
        let (model, backend) = make()

        #expect(!model.updateLayout(area.id, to: Self.area(0.25, 0, 0)))

        #expect(model.error == SettingsMessages.describe(.outOfRange(field: "width", rule: "must be > 0")))
        #expect(model.errorTarget == .window)
        #expect(backend.saved.isEmpty)
    }

    @Test("a layout stays in its section: a grid cannot become a custom area, nor the other way round")
    func updateAcrossSections() {
        let (model, backend) = make()

        #expect(!model.updateLayout(grid.id, to: Self.area(0, 0, 0.5, 0.5)))
        #expect(model.errorTarget == .window)
        #expect(!model.updateLayout(area.id, to: Self.grid(3, 2, 2)))
        #expect(!model.updateLayout(grid.id, to: .restoreWindow))
        #expect(backend.saved.isEmpty)
        #expect(model.error != nil)
    }

    @Test("only a layout binding can be updated")
    func updateNotALayout() {
        let (model, backend) = make()

        #expect(!model.updateLayout(left.id, to: Self.grid(3, 2, 2)))
        #expect(model.errorTarget == .window)
        #expect(!model.updateLayout(UUID(), to: Self.grid(3, 2, 2)))
        #expect(model.error == SettingsMessages.bindingGone())
        #expect(backend.saved.isEmpty)
    }

    @Test("a layout the backend cannot save is not updated")
    func updateNotSaved() {
        let (model, backend) = make()
        backend.failure = "the disk is full"

        #expect(!model.updateLayout(grid.id, to: Self.grid(6, 2, 3)))

        #expect(model.error?.contains("the disk is full") == true)
        #expect(model.binding(grid.id)?.action == Self.grid(4, 2, 2))
    }

    @Test("removing a layout is removeBinding")
    func removeLayout() {
        let (model, backend) = make()
        #expect(model.removeBinding(grid.id))
        #expect(model.bindings.map(\.id) == [left.id, area.id])
        #expect(backend.saved.count == 1)
    }

    // MARK: The request to open the sheet

    @Test("a request for a new grid or custom area is held until it is dismissed")
    func newLayoutEditor() {
        let (model, _) = make()
        #expect(model.layoutEditor == nil)

        #expect(model.editLayout(.new(.grids)))
        #expect(model.layoutEditor == .new(.grids))

        #expect(model.editLayout(.new(.customAreas)))
        #expect(model.layoutEditor == .new(.customAreas))

        model.dismissLayoutEditor()
        #expect(model.layoutEditor == nil)
        model.dismissLayoutEditor()
        #expect(model.layoutEditor == nil)
    }

    @Test("a request to edit a layout names its binding")
    func editLayoutEditor() {
        let (model, _) = make()
        #expect(model.editLayout(.edit(grid.id)))
        #expect(model.layoutEditor == .edit(grid.id))
        #expect(model.editLayout(.edit(area.id)))
        #expect(model.layoutEditor == .edit(area.id))
    }

    @Test("a reload drops a request to edit a layout whose binding is gone, and keeps one whose binding is still there")
    func reloadDropsTheRequestForAGoneBinding() {
        let (model, backend) = make()
        model.editLayout(.edit(grid.id))

        backend.replaceFromOutside(Config(bindings: [left, grid]))
        #expect(model.layoutEditor == .edit(grid.id), "the binding is still in the config")

        backend.replaceFromOutside(Config(bindings: [left, area]))
        #expect(model.layoutEditor == nil, "the binding is gone")
    }

    @Test("a reload keeps a request for a new layout")
    func reloadKeepsTheRequestForANewLayout() {
        let (model, backend) = make()
        model.editLayout(.new(.customAreas))

        backend.replaceFromOutside(Config(bindings: [left]))

        #expect(model.layoutEditor == .new(.customAreas))
    }

    @Test("restoring the default shortcuts drops a request to edit a layout, since every binding gets a new ID")
    func restoreDropsTheRequest() {
        let (model, _) = make()
        model.editLayout(.edit(grid.id))

        #expect(model.restoreDefaultShortcuts())

        #expect(model.layoutEditor == nil)
    }

    @Test("a request for something that has no sheet is refused, and the open request stays")
    func refusedLayoutEditor() {
        let (model, backend) = make()
        model.editLayout(.edit(grid.id))

        for section in KeymapSection.allCases where section != .grids && section != .customAreas {
            #expect(!model.editLayout(.new(section)), "\(section)")
            #expect(model.errorTarget == .window)
        }
        #expect(!model.editLayout(.edit(left.id)))
        #expect(!model.editLayout(.edit(UUID())))
        #expect(model.error != nil)

        #expect(model.layoutEditor == .edit(grid.id))
        #expect(backend.saved.isEmpty)
    }

    @Test("opening the sheet ends a recording of a row and drops a pending conflict")
    func openingTheEditorEndsRecording() {
        let (model, backend) = make()
        model.beginRecording(.layout(grid.id))
        #expect(backend.isSuspended)

        model.editLayout(.edit(grid.id))
        #expect(!model.isRecording)
        #expect(model.recordingRow == nil)
        #expect(!backend.isSuspended)

        model.beginRecording(.builtIn(.placeWindow(.preset(.leftHalf))))
        model.editLayout(.new(.grids))
        #expect(!model.isRecording)
        #expect(!backend.isSuspended)

        model.beginRecording(.builtIn(.placeWindow(.preset(.rightHalf))))
        model.record(UIFixture.f13)
        #expect(model.pendingConflict != nil)
        model.editLayout(.new(.customAreas))
        #expect(model.pendingConflict == nil)
    }
}
