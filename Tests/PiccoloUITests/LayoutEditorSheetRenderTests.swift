import AppKit
import SwiftUI
import Testing

import PiccoloCore

@testable import PiccoloUI

/// Draws the sheet that creates and edits a grid or a custom area into bitmaps, off screen, as a smoke test that its
/// states can be built and laid out and that each looks different from the one it departs from, and looks at what
/// the pictures can tell: the labels and the units of the fields, the red outline around a field, the state of the
/// Done button, the numbers of the windows.
/// Nothing is shown and no permission is involved.
///
/// Set `PICCOLO_RENDER_DIR` to a folder to keep the images, for example to look at the sheet in light and dark
/// appearance.
@MainActor
@Suite("Layout editor sheet")
struct LayoutEditorSheetRenderTests {
    private static let area = FractionalRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    private static let otherArea = FractionalRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
    /// Left plus width is 130%.
    private static let invalidArea = FractionalRect(x: 0.8, y: 0.25, width: 0.5, height: 0.5)

    // MARK: Support

    /// A model on `bindings`, with the grids filling in `fillOrder`.
    private func model(_ bindings: [KeyBinding] = [], fillOrder: GridFillOrder = .rows) -> SettingsModel {
        let backend = InMemorySettingsBackend(config: Config(bindings: bindings))
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage()) { _ in nil }
        if fillOrder != .rows {
            #expect(model.setGridFillOrder(fillOrder))
        }
        return model
    }

    /// A sheet drawn into a bitmap, with where its text fields are.
    private struct Picture {
        let bitmap: NSBitmapImageRep
        /// The frames of the text fields in points from the top-left corner of the sheet, in the order they are
        /// laid out.
        let fields: [CGRect]
        /// Bitmap pixels to a point.
        let scale: CGFloat
        /// The size the sheet asked for before it was in a window, and the size it has once the layout has settled.
        /// A window follows what its content asks for, so a sheet whose content grows when a message comes up opens
        /// that much bigger.
        let askedSize: CGSize
        let size: CGSize

        var data: Data? { bitmap.representation(using: .png, properties: [:]) }

        /// The picture of the part of the sheet in `rect` (points from the top-left corner), as PNG data.
        func data(of rect: CGRect) -> Data? {
            let pixels = CGRect(
                x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
            ).integral
            guard let image = bitmap.cgImage?.cropping(to: pixels) else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }

        /// How many pixels in the band of `rect` (points from the top-left corner of the sheet) are drawn, that is,
        /// are darker than white once taken over white, and the darkest of them (0 black, 1 white). The sheet's own
        /// background is transparent in the picture, as a viewer shows it on white.
        func ink(in rect: CGRect) -> (count: Int, darkest: CGFloat) {
            let minX = max(0, Int((rect.minX * scale).rounded(.down)))
            let maxX = min(bitmap.pixelsWide, Int((rect.maxX * scale).rounded(.up)))
            let minY = max(0, Int((rect.minY * scale).rounded(.down)))
            let maxY = min(bitmap.pixelsHigh, Int((rect.maxY * scale).rounded(.up)))
            var count = 0
            var darkest: CGFloat = 1
            for x in minX..<max(minX, maxX) {
                for y in minY..<max(minY, maxY) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let luminance = Self.luminanceOverWhite(color)
                    if luminance < 0.9 { count += 1 }
                    darkest = min(darkest, luminance)
                }
            }
            return (count, darkest)
        }

        private static func luminanceOverWhite(_ color: NSColor) -> CGFloat {
            let alpha = color.alphaComponent
            let value = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
            return value * alpha + (1 - alpha)
        }

        /// The number of red pixels in the band of 4 points around `field`'s frame, which is where the outline of a
        /// field is drawn and where a text field has nothing of its own.
        func redPixels(around field: CGRect) -> Int {
            let band = field.insetBy(dx: -4, dy: -4)
            var count = 0
            let width = bitmap.pixelsWide
            let height = bitmap.pixelsHigh
            for x in Int(band.minX * scale)..<min(width, Int((band.maxX * scale).rounded(.up))) {
                for y in Int(band.minY * scale)..<min(height, Int((band.maxY * scale).rounded(.up))) {
                    let point = CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale)
                    guard !field.contains(point),
                        let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                    else { continue }
                    if color.redComponent > 0.6, color.greenComponent < 0.4, color.blueComponent < 0.4 {
                        count += 1
                    }
                }
            }
            return count
        }
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let field = view as? NSTextField, field.isEditable { found.append(field) }
        for sub in view.subviews { found += textFields(in: sub) }
        return found
    }

    /// `view` in a window of its own size, drawn once the layout has settled: again and again, 20 ms apart, until
    /// two in a row are the same, at most 5 s.
    private func render(_ view: some View, dark: Bool = false) async throws -> Picture {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        func draw() throws -> NSBitmapImageRep {
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            return bitmap
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var previous = try draw()
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            let next = try draw()
            if next.representation(using: .png, properties: [:]) == previous.representation(using: .png, properties: [:]) {
                previous = next
                break
            }
            previous = next
        }
        let settled = hosting.bounds.size
        let fields = textFields(in: hosting).map { field -> CGRect in
            let frame = hosting.convert(field.bounds, from: field)
            return hosting.isFlipped
                ? frame : CGRect(x: frame.minX, y: settled.height - frame.maxY, width: frame.width, height: frame.height)
        }
        return Picture(
            bitmap: previous, fields: fields, scale: CGFloat(previous.pixelsWide) / settled.width, askedSize: size,
            size: settled)
    }

    private func hasContent(_ bitmap: NSBitmapImageRep, step: Int = 5) -> Bool {
        guard let first = bitmap.colorAt(x: 0, y: 0) else { return false }
        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
                if let color = bitmap.colorAt(x: x, y: y), color != first { return true }
            }
        }
        return false
    }

    private func keep(_ bitmap: NSBitmapImageRep, as name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PICCOLO_RENDER_DIR"],
            let data = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: directory).appending(path: "\(name).png"))
    }

    /// Draws the sheet in light and dark appearance, checks that neither is blank, keeps the images, and answers the
    /// light picture.
    private func draw(
        _ sheet: @autoclosure () -> LayoutEditorSheet, named name: String, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Picture {
        var light: Picture?
        for dark in [false, true] {
            let appearance = dark ? "dark" : "light"
            let picture = try await render(sheet(), dark: dark)
            #expect(hasContent(picture.bitmap), "\(name) is blank in \(appearance) appearance", sourceLocation: sourceLocation)
            #expect(
                picture.size == picture.askedSize,
                "\(name) asked for \(picture.askedSize) and is \(picture.size) in \(appearance) appearance",
                sourceLocation: sourceLocation)
            keep(picture.bitmap, as: "layout-sheet-\(name)-\(appearance)")
            if !dark { light = picture }
        }
        return try #require(light)
    }

    /// The strip at the bottom of the sheet with its buttons and the room below them.
    private func buttonStrip(_ picture: Picture) -> Data? {
        picture.data(of: CGRect(x: 0, y: picture.size.height - 44, width: picture.size.width, height: 44))
    }

    // MARK: A custom area

    @Test("the sheet of a new custom area starts at 25%, 25%, 50% by 50% and has nothing to complain about")
    func newCustomArea() async throws {
        let model = model()
        let sheet = { LayoutEditorSheet(model: model, request: .new(.customAreas)) }
        let picture = try await draw(sheet(), named: "area-new")
        #expect(picture.fields.count == 4, "Left, Top, Width and Height")
        for field in picture.fields {
            #expect(picture.redPixels(around: field) == 0, "a field of a valid area is outlined")
        }
        #expect(
            model.layoutProblem(.placeWindow(.custom(LayoutDraft.newArea)), editing: nil) == nil,
            "the new area is not valid")
    }

    @Test("the fields show the area in percent")
    func fieldsShowTheArea() async throws {
        let model = model()
        let hosting = NSHostingView(
            rootView: LayoutEditorSheet(
                model: model, request: .new(.customAreas), start: .placeWindow(.custom(FractionalRect(x: 0.1, y: 0.125, width: 1.0 / 3.0, height: 0.5)))))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        #expect(textFields(in: hosting).map(\.stringValue) == ["10", "12.5", "33.33", "50"])
    }

    @Test("each field of the area has its label on its left, in the primary colour, and a % after it")
    func fieldsHaveLabelsAndUnit() async throws {
        let model = model()
        let picture = try await draw(
            LayoutEditorSheet(model: model, request: .new(.customAreas)), named: "area-labels-and-unit")
        #expect(picture.fields.count == 4)
        for field in picture.fields {
            // The label band ends 2 points short of the field and starts 60 points before it, clear of the picture.
            let label = picture.ink(in: CGRect(x: field.minX - 60, y: field.minY, width: 58, height: field.height))
            #expect(label.count > 20, "a field has no label on its left")
            #expect(label.darkest < 0.4, "a label is not in the primary colour")
            let unit = picture.ink(in: CGRect(x: field.maxX + 2, y: field.minY, width: 14, height: field.height))
            #expect(unit.count > 10, "a field has no % after it")
        }
    }

    @Test("an invalid value outlines its fields, shows the message, and disables Done")
    func invalidValue() async throws {
        let model = model()
        let valid = try await draw(LayoutEditorSheet(model: model, request: .new(.customAreas)), named: "area-valid")
        let otherValid = try await render(
            LayoutEditorSheet(model: model, request: .new(.customAreas), start: .placeWindow(.custom(Self.otherArea))))

        let action = Action.placeWindow(.custom(Self.invalidArea))
        let problem = try #require(model.layoutProblem(action, editing: nil))
        #expect(problem.message == "Left plus width must not be more than 100%.")
        #expect(problem.fields == [.left, .width])

        let invalid = try await draw(
            LayoutEditorSheet(model: model, request: .new(.customAreas), start: action), named: "area-invalid")
        #expect(invalid.fields.count == 4)
        // The fields the problem names are outlined in red, the others are not.
        #expect(invalid.redPixels(around: invalid.fields[0]) > 0, "Left is not outlined")
        #expect(invalid.redPixels(around: invalid.fields[1]) == 0, "Top is outlined")
        #expect(invalid.redPixels(around: invalid.fields[2]) > 0, "Width is not outlined")
        #expect(invalid.redPixels(around: invalid.fields[3]) == 0, "Height is outlined")
        // The sheet looks different, and so do the buttons: Done is dimmed, which another valid area does not do.
        #expect(invalid.data != valid.data)
        #expect(invalid.size == valid.size, "the message changes the size of the sheet")
        #expect(buttonStrip(valid) != nil)
        #expect(buttonStrip(valid) == buttonStrip(otherValid), "the buttons depend on the area")
        #expect(buttonStrip(valid) != buttonStrip(invalid), "Done looks the same with an invalid area")
    }

    @Test("each value out of range is a problem with its own sentence")
    func valuesOutOfRange() {
        let model = model()
        for (area, problem) in [
            (FractionalRect(x: -0.1, y: 0, width: 0.5, height: 0.5), "Left must be 0% or more."),
            (FractionalRect(x: 0, y: -0.1, width: 0.5, height: 0.5), "Top must be 0% or more."),
            (FractionalRect(x: 0, y: 0, width: 0, height: 0.5), "Width must be more than 0%."),
            (FractionalRect(x: 0, y: 0, width: 0.5, height: 0), "Height must be more than 0%."),
            (FractionalRect(x: 0, y: 0.6, width: 0.5, height: 0.5), "Top plus height must not be more than 100%."),
        ] {
            let found = model.layoutProblem(.placeWindow(.custom(area)), editing: nil)
            #expect(found?.message == problem)
        }
    }

    @Test("an area that another row has shows the message without outlining a field, and disables Done")
    func duplicate() async throws {
        let existing = KeyBinding(action: .placeWindow(.custom(Self.area)), shortcut: UIFixture.f14)
        let model = model([existing])
        let valid = try await render(
            LayoutEditorSheet(model: model, request: .new(.customAreas), start: .placeWindow(.custom(Self.otherArea))))

        let action = Action.placeWindow(.custom(Self.area))
        let problem = try #require(model.layoutProblem(action, editing: nil))
        #expect(problem.message == "There is already a custom area like this.")
        #expect(problem.fields.isEmpty)

        let duplicate = try await draw(
            LayoutEditorSheet(model: model, request: .new(.customAreas), start: action), named: "area-duplicate")
        for field in duplicate.fields {
            #expect(duplicate.redPixels(around: field) == 0, "a field is outlined for a duplicate")
        }
        #expect(duplicate.data != valid.data)
        #expect(duplicate.size == valid.size, "the message changes the size of the sheet")
        #expect(buttonStrip(valid) != buttonStrip(duplicate), "Done looks the same with a duplicate")
    }

    @Test("editing a row, its own area is not a duplicate; the sheet has Delete and another title")
    func editingARow() async throws {
        let existing = KeyBinding(action: .placeWindow(.custom(Self.area)), shortcut: UIFixture.f14)
        let model = model([existing])
        #expect(model.layoutProblem(existing.action, editing: existing.id) == nil)

        let editing = try await draw(
            LayoutEditorSheet(model: model, request: .edit(existing.id)), named: "area-edit")
        let new = try await render(
            LayoutEditorSheet(model: model, request: .new(.customAreas), start: existing.action))
        // The same area is a duplicate as a new row, and none when editing the row that has it.
        #expect(editing.data != new.data)
        for field in editing.fields {
            #expect(editing.redPixels(around: field) == 0)
        }
        let fresh = try await render(LayoutEditorSheet(model: self.model(), request: .new(.customAreas)))
        #expect(buttonStrip(editing) != buttonStrip(fresh), "an editing sheet has no Delete")
    }

    // MARK: A grid

    @Test("a grid of 3 windows in 2 by 2 numbers its windows in the fill order")
    func gridFillOrders() async throws {
        let three = Action.arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2))
        let rows = try await draw(
            LayoutEditorSheet(model: model(fillOrder: .rows), request: .new(.grids), start: three),
            named: "grid-3-rows-first")
        let columns = try await draw(
            LayoutEditorSheet(model: model(fillOrder: .columns), request: .new(.grids), start: three),
            named: "grid-3-columns-first")
        let four = try await render(LayoutEditorSheet(model: model(fillOrder: .rows), request: .new(.grids)))
        #expect(rows.data != columns.data, "the fill order does not show")
        #expect(rows.data != four.data)
        #expect(columns.data != four.data)
        #expect(rows.fields.isEmpty, "a grid has no text fields")
    }

    @Test("the new grid is 4 windows in 2 by 2, and a grid being edited shows its own")
    func gridStart() async throws {
        let grid = KeyBinding(action: .arrangeGrid(GridSpec(count: 6, rows: 2, columns: 3)), shortcut: UIFixture.f14)
        let model = model([grid])
        #expect(LayoutEditorSheet.startingAction(of: .new(.grids), in: model) == .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))
        #expect(
            LayoutEditorSheet.startingAction(of: .new(.customAreas), in: model)
                == .placeWindow(.custom(FractionalRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))))
        #expect(LayoutEditorSheet.startingAction(of: .edit(grid.id), in: model) == grid.action)

        let new = try await render(LayoutEditorSheet(model: model, request: .new(.grids)))
        let editing = try await draw(LayoutEditorSheet(model: model, request: .edit(grid.id)), named: "grid-edit")
        #expect(editing.data != new.data)
    }

    @Test("hovering the cell picker lights the cells up to the one under the pointer")
    func hoveringTheCellPicker() async throws {
        let model = model()
        let resting = try await render(LayoutEditorSheet(model: model, request: .new(.grids)))
        let hovering = try await draw(
            LayoutEditorSheet(model: model, request: .new(.grids), hover: GridCell(row: 2, column: 3)),
            named: "grid-hover-3x4")
        #expect(hovering.data != resting.data)
        // The same cell as the grid already has changes nothing: the lit cells are the picked ones.
        let sameAsPicked = try await render(
            LayoutEditorSheet(model: model, request: .new(.grids), hover: GridCell(row: 1, column: 1)))
        #expect(sameAsPicked.data == resting.data)
        #expect(LayoutEditorText.size(rows: 3, columns: 4, bundle: AppLanguage.en.textBundle!) == "3 × 4")
    }

    @Test("a point of the cell picker belongs to a cell, and a gap to the cell before it")
    func cellAtPoint() {
        #expect(CellPicker.cell(at: CGPoint(x: 0, y: 0)) == GridCell(row: 0, column: 0))
        #expect(CellPicker.cell(at: CGPoint(x: 17.9, y: 17.9)) == GridCell(row: 0, column: 0))
        #expect(CellPicker.cell(at: CGPoint(x: 19.5, y: 20.5)) == GridCell(row: 0, column: 0))
        #expect(CellPicker.cell(at: CGPoint(x: 21, y: 21)) == GridCell(row: 1, column: 1))
        #expect(CellPicker.cell(at: CGPoint(x: 21 * 3 + 5, y: 21 * 2 + 5)) == GridCell(row: 2, column: 3))
        #expect(CellPicker.cell(at: CGPoint(x: 164.9, y: 164.9)) == GridCell(row: 7, column: 7))
        #expect(CGFloat(8 * 18 + 7 * 3) == CellPicker.side)
        #expect(CellPicker.cell(at: CGPoint(x: 165, y: 10)) == nil)
        #expect(CellPicker.cell(at: CGPoint(x: 10, y: 165)) == nil)
        #expect(CellPicker.cell(at: CGPoint(x: -1, y: 5)) == nil)
        #expect(CellPicker.cell(at: CGPoint(x: 5, y: -0.5)) == nil)
    }

    // MARK: Done, Delete and Cancel

    @Test("Done on a new row adds it, starts recording its shortcut and closes the sheet")
    func doneAddsARow() {
        let model = model()
        model.editLayout(.new(.customAreas))
        let action = Action.placeWindow(.custom(Self.area))
        LayoutEditorSheet.finish(.new(.customAreas), with: action, in: model)
        let binding = model.bindings.first { $0.action == action }
        #expect(binding != nil)
        #expect(binding?.shortcut == nil)
        #expect(model.recordingRow == binding.map { .layout($0.id) })
        #expect(model.layoutEditor == nil)
    }

    @Test("Done on a row being edited changes its layout, keeps its shortcut and closes the sheet")
    func doneUpdatesARow() {
        let existing = KeyBinding(action: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)), shortcut: UIFixture.f14)
        let model = model([existing])
        model.editLayout(.edit(existing.id))
        let grid = Action.arrangeGrid(GridSpec(count: 6, rows: 2, columns: 3))
        LayoutEditorSheet.finish(.edit(existing.id), with: grid, in: model)
        #expect(model.bindings.count == 1)
        #expect(model.binding(existing.id)?.action == grid)
        #expect(model.binding(existing.id)?.shortcut == UIFixture.f14)
        #expect(model.recordingRow == nil)
        #expect(model.layoutEditor == nil)
    }

    @Test("Delete removes the row and closes the sheet")
    func deleteRemovesTheRow() {
        let existing = KeyBinding(action: .placeWindow(.custom(Self.area)), shortcut: UIFixture.f14)
        let model = model([existing])
        model.editLayout(.edit(existing.id))
        LayoutEditorSheet.delete(existing.id, in: model)
        #expect(model.bindings.isEmpty)
        #expect(model.layoutEditor == nil)
    }

    @Test("the sheet is shown for the request of the model, and closing it withdraws the request")
    func presentation() {
        let existing = KeyBinding(action: .placeWindow(.custom(Self.area)), shortcut: UIFixture.f14)
        let model = model([existing])
        let binding = LayoutEditorSheet.presentation(of: model)
        #expect(binding.wrappedValue == nil)

        model.editLayout(.new(.grids))
        #expect(binding.wrappedValue?.request == .new(.grids))
        let grids = binding.wrappedValue?.id
        model.editLayout(.new(.customAreas))
        #expect(binding.wrappedValue?.id != grids, "a new request is the same sheet")
        model.editLayout(.edit(existing.id))
        #expect(binding.wrappedValue?.request == .edit(existing.id))

        binding.wrappedValue = nil
        #expect(model.layoutEditor == nil)
        #expect(binding.wrappedValue == nil)
    }

    // MARK: Texts

    @Test("the title says new or edit and grid or custom area, in every language", arguments: AppLanguage.languages)
    func titles(_ language: AppLanguage) throws {
        let bundle = try #require(language.textBundle)
        let titles = [
            LayoutEditorText.title(isNew: true, isGrid: true, bundle: bundle),
            LayoutEditorText.title(isNew: false, isGrid: true, bundle: bundle),
            LayoutEditorText.title(isNew: true, isGrid: false, bundle: bundle),
            LayoutEditorText.title(isNew: false, isGrid: false, bundle: bundle),
        ]
        #expect(Set(titles).count == 4, "\(language.rawValue): \(titles)")
        if language == .en {
            #expect(titles == ["New Grid", "Edit Grid", "New Custom Area", "Edit Custom Area"])
        }
        if language == .zhHans {
            #expect(titles == ["新建网格", "编辑网格", "新建自定义区域", "编辑自定义区域"])
        }
    }

    @Test("the size under the picker is the two numbers with a ×, in every language", arguments: AppLanguage.languages)
    func sizeText(_ language: AppLanguage) throws {
        let bundle = try #require(language.textBundle)
        #expect(LayoutEditorText.size(rows: 3, columns: 4, bundle: bundle) == "3 × 4")
        #expect(LayoutEditorText.size(rows: 8, columns: 1, bundle: bundle) == "8 × 1")
    }

    @Test("a percentage is read with a point or a comma and an optional sign")
    func percentText() {
        #expect(AreaPercentField.fraction(fromPercentText: "25") == 0.25)
        #expect(AreaPercentField.fraction(fromPercentText: " 33.33 % ") == 0.3333)
        #expect(AreaPercentField.fraction(fromPercentText: "33,5") == 0.335)
        #expect(AreaPercentField.fraction(fromPercentText: "100") == 1)
        #expect(AreaPercentField.fraction(fromPercentText: "-5") == -0.05)
        #expect(AreaPercentField.fraction(fromPercentText: "150") == 1.5)
        for text in ["", " ", "-", "%", "abc", "1e9", "inf", "nan", "2 5"] {
            #expect(AreaPercentField.fraction(fromPercentText: text) == nil, "\"\(text)\"")
        }
    }

    @Test("the reason Done is disabled is drawn when there is one, and the room for it is kept when there is not")
    func message() async throws {
        let none = try await render(LayoutEditorMessage(problem: nil).frame(width: 400))
        let some = try await render(
            LayoutEditorMessage(problem: LayoutProblem(message: "Width must be more than 0%.", fields: [.width]))
                .frame(width: 400))
        #expect(!hasContent(none.bitmap), "the message is drawn with nothing to say")
        #expect(hasContent(some.bitmap), "the message is not drawn")
        #expect(none.bitmap.pixelsHigh >= Int(LayoutEditorMessage.height))
        #expect(none.bitmap.pixelsHigh == some.bitmap.pixelsHigh, "the message moves the rest of the sheet")
    }
}
