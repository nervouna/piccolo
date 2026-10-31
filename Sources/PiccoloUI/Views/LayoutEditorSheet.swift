import AppKit
import PiccoloCore
import SwiftUI

/// A cell of the grid picker, counted from the top-left corner, from 0.
struct GridCell: Equatable {
    var row: Int
    var column: Int
}

/// The sheet that creates and edits a grid or a custom area (agreed in #99, item 6): a title, two columns, the
/// reason Done is disabled, and the buttons.
///
/// - A custom area: on the left a picture of the screen on which a drag draws the area and a drag inside it moves it
///   (``LayoutDraft``); on the right Left, Top, Width and Height as percentages.
/// - A grid: on the left a picker of up to 8 × 8 cells, on the right a preview of the layout with the windows
///   numbered in the current fill order, and the number of windows.
///
/// The sheet keeps its own draft and gives it to the model only with Done (`addLayout(_:)`, which starts recording
/// the new row's shortcut, or `updateLayout(_:to:)`). Done is disabled while `layoutProblem(_:editing:)` answers a
/// problem; its message shows under the columns and the fields it names are outlined in red. Delete (when editing)
/// removes the binding. Return is Done and Escape is Cancel.
struct LayoutEditorSheet: View {
    let model: SettingsModel
    let request: LayoutEditorRequest

    private let isGrid: Bool
    @State private var area: FractionalRect
    @State private var grid: GridSpec
    @State private var hoveredCell: GridCell?

    /// - Parameters:
    ///   - start: The layout to start from instead of the one the request names, for the tests.
    ///   - hover: The cell the pointer is over in the picker, for the tests.
    init(model: SettingsModel, request: LayoutEditorRequest, start: Action? = nil, hover: GridCell? = nil) {
        self.model = model
        self.request = request
        let action = start ?? Self.startingAction(of: request, in: model)
        if case .arrangeGrid(let spec) = action {
            isGrid = true
            _grid = State(initialValue: spec)
            _area = State(initialValue: LayoutDraft.newArea)
        } else {
            isGrid = false
            if case .placeWindow(.custom(let rect)) = action {
                _area = State(initialValue: rect)
            } else {
                _area = State(initialValue: LayoutDraft.newArea)
            }
            _grid = State(initialValue: LayoutDraft.newGrid)
        }
        _hoveredCell = State(initialValue: hover)
    }

    /// The layout the sheet starts from: a new grid or custom area, or the one of the binding being edited.
    static func startingAction(of request: LayoutEditorRequest, in model: SettingsModel) -> Action {
        switch request {
        case .new(.grids):
            return .arrangeGrid(LayoutDraft.newGrid)
        case .new:
            return .placeWindow(.custom(LayoutDraft.newArea))
        case .edit(let id):
            return model.binding(id)?.action ?? .placeWindow(.custom(LayoutDraft.newArea))
        }
    }

    private var isNew: Bool {
        if case .new = request { return true }
        return false
    }

    private var editedBinding: UUID? {
        if case .edit(let id) = request { return id }
        return nil
    }

    /// The layout the draft stands for.
    private var action: Action {
        isGrid ? .arrangeGrid(grid) : .placeWindow(.custom(area))
    }

    private var problem: LayoutProblem? {
        model.layoutProblem(action, editing: editedBinding)
    }

    var body: some View {
        let problem = problem
        VStack(alignment: .leading, spacing: 16) {
            Text(LayoutEditorText.title(isNew: isNew, isGrid: isGrid))
                .font(.headline)
            if isGrid {
                GridEditor(
                    grid: $grid, hoveredCell: $hoveredCell, fillOrder: model.gridFillOrder,
                    problemFields: problem?.fields ?? [])
            } else {
                AreaEditor(area: $area, problemFields: problem?.fields ?? [])
            }
            LayoutEditorMessage(problem: problem)
            buttons(disabled: problem != nil)
        }
        .padding(20)
    }

    // MARK: Buttons

    private func buttons(disabled: Bool) -> some View {
        HStack(spacing: 12) {
            if let id = editedBinding {
                Button(role: .destructive) {
                    Self.delete(id, in: model)
                } label: {
                    Text(localized: "Delete")
                }
            }
            Spacer()
            Button {
                model.dismissLayoutEditor()
            } label: {
                Text(localized: "Cancel")
            }
            .keyboardShortcut(.cancelAction)
            Button {
                Self.finish(request, with: action, in: model)
            } label: {
                Text(localized: "Done")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(disabled)
            .accessibilityIdentifier("layoutEditor.done")
        }
    }

    /// Done: hands `action` to the model, which starts recording a shortcut for a new row, and closes the sheet. A
    /// draft the model refuses (it only does for a problem Done was disabled for, or a config that cannot be saved)
    /// leaves its reason where the model shows errors.
    static func finish(_ request: LayoutEditorRequest, with action: Action, in model: SettingsModel) {
        switch request {
        case .new:
            model.addLayout(action)
        case .edit(let id):
            model.updateLayout(id, to: action)
        }
        model.dismissLayoutEditor()
    }

    /// Delete: removes the binding being edited and closes the sheet.
    static func delete(_ id: UUID, in model: SettingsModel) {
        model.removeBinding(id)
        model.dismissLayoutEditor()
    }
}

// MARK: The reason Done is disabled

/// The reason Done is disabled, in red under the columns, on one line. The line is there, empty, when there is no
/// reason, so that a reason can come and go while an area is dragged without moving the picture under the pointer.
///
/// Its height is fixed on purpose: a text that is allowed to wrap makes the window's smallest height the height of
/// the text at the narrowest width, and the sheet would open that tall. A message too long for the line is cut and
/// shown whole in the tooltip.
struct LayoutEditorMessage: View {
    static let height: CGFloat = 18

    let problem: LayoutProblem?

    var body: some View {
        Text(problem?.message ?? "")
            .font(.callout)
            .foregroundStyle(.red)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
            .help(problem?.message ?? "")
    }
}

// MARK: Presenting

extension LayoutEditorSheet {
    /// The request for the sheet in the form `.sheet(item:)` wants: it is the same sheet as long as the request is.
    struct Presentation: Identifiable {
        let request: LayoutEditorRequest

        var id: String {
            switch request {
            case .new(let section): "new.\(section.rawValue)"
            case .edit(let id): "edit.\(id.uuidString)"
            }
        }
    }

    /// A binding to the sheet `model.layoutEditor` asks for. Closing the sheet (Escape, a button) withdraws the
    /// request.
    static func presentation(of model: SettingsModel) -> Binding<Presentation?> {
        Binding(
            get: { model.layoutEditor.map(Presentation.init) },
            set: { presentation in
                if presentation == nil { model.dismissLayoutEditor() }
            })
    }
}

// MARK: - Custom area

/// The two columns of a custom area: the picture of the screen and the fields.
private struct AreaEditor: View {
    @Binding var area: FractionalRect
    let problemFields: Set<LayoutField>

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            AreaPicture(area: $area)
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 10) {
                field(String(localized: "Left", bundle: .module), $area.x, .left)
                field(String(localized: "Top", bundle: .module), $area.y, .top)
                field(String(localized: "Width", bundle: .module), $area.width, .width)
                field(String(localized: "Height", bundle: .module), $area.height, .height)
            }
        }
    }

    private func field(_ title: String, _ fraction: Binding<Double>, _ field: LayoutField) -> some View {
        GridRow {
            // Fixed size: the grid squeezes its flexible cells to the width it is given, and a label squeezed that far
            // is gone. The unit after the field is fixed for the same reason.
            Text(verbatim: title)
                .fixedSize()
            AreaPercentField(title: title, fraction: fraction, isOutlined: problemFields.contains(field))
        }
    }
}

/// The picture of the screen, 352 × 220 pt, on which the area is drawn and moved, with faint guides at the quarters,
/// the thirds and the half. A drag that starts outside the area draws a new one; one that starts inside moves it
/// (⌥ held: in steps of 1%). The rules are ``LayoutDraft``'s.
private struct AreaPicture: View {
    static let size = CGSize(width: 352, height: 220)

    @Binding var area: FractionalRect
    /// The area when the drag in progress began, which decides whether it draws or moves.
    @State private var areaAtDragStart: FractionalRect?
    @State private var cursor = PushedCursor()

    private static let guides: [(fraction: Double, isStrong: Bool)] = [
        (0.25, false), (1.0 / 3.0, false), (0.5, true), (2.0 / 3.0, false), (0.75, false),
    ]

    private var accent: Color { Color(nsColor: .controlAccentColor) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor))
            ForEach(Self.guides, id: \.fraction) { guide in
                guideLines(guide.fraction)
                    .stroke(Color.primary.opacity(guide.isStrong ? 0.2 : 0.09), lineWidth: 1)
            }
            areaShape
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(drag)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                cursor.set(contains(location) ? .openHand : .crosshair)
            case .ended:
                cursor.set(nil)
            }
        }
        .onDisappear { cursor.set(nil) }
        .accessibilityElement()
        .accessibilityLabel(Text(localized: "Preview of the window layout"))
    }

    /// The vertical and the horizontal line at `fraction` of the picture.
    private func guideLines(_ fraction: Double) -> Path {
        var path = Path()
        let x = fraction * Self.size.width
        let y = fraction * Self.size.height
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: Self.size.height))
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: Self.size.width, y: y))
        return path
    }

    /// The area in the accent colour. A value the fields were given that puts it off the screen shows as far as it
    /// is on it; one with no size shows nothing.
    @ViewBuilder
    private var areaShape: some View {
        let frame = CGRect(
            x: area.x * Self.size.width, y: area.y * Self.size.height,
            width: area.width * Self.size.width, height: area.height * Self.size.height
        ).intersection(CGRect(origin: .zero, size: Self.size))
        if area.width > 0, area.height > 0, !frame.isNull, frame.width > 0, frame.height > 0 {
            Rectangle()
                .fill(accent.opacity(0.3))
                .overlay(Rectangle().strokeBorder(accent, lineWidth: 1.5))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
    }

    private func fraction(of point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / Self.size.width, y: point.y / Self.size.height)
    }

    private func contains(_ location: CGPoint) -> Bool {
        let point = fraction(of: location)
        return area.width > 0 && area.height > 0
            && point.x >= area.x && point.x <= area.x + area.width
            && point.y >= area.y && point.y <= area.y + area.height
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let start = areaAtDragStart ?? area
                areaAtDragStart = start
                let free = NSEvent.modifierFlags.contains(.option)
                if let next = LayoutDraft.areaAfterDrag(
                    from: fraction(of: value.startLocation), to: fraction(of: value.location),
                    startingWith: start, free: free)
                {
                    area = next
                }
            }
            .onEnded { _ in
                areaAtDragStart = nil
            }
    }
}

/// A field for a fraction of the screen shown as a percentage. Typing changes the fraction as soon as the text is a
/// number; a text that is not one leaves it as it was, and the field shows the fraction again when it loses the
/// focus. The fraction changed from outside (a drag on the picture) is shown at once.
struct AreaPercentField: View {
    let title: String
    @Binding var fraction: Double
    let isOutlined: Bool

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(title: String, fraction: Binding<Double>, isOutlined: Bool) {
        self.title = title
        _fraction = fraction
        self.isOutlined = isOutlined
        _text = State(initialValue: ActionSummary.percentNumber(fraction.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(
                title,
                text: Binding(
                    get: { text },
                    set: { typed in
                        text = typed
                        if let value = Self.fraction(fromPercentText: typed) {
                            fraction = value
                        }
                    })
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
            .focused($isFocused)
            .overlay {
                if isOutlined {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.red, lineWidth: 1.5).padding(-2)
                }
            }
            Text(verbatim: "%")
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .onChange(of: fraction) { _, new in
            // Typing set the fraction from the text, so the text already says it; a drag did not.
            if Self.fraction(fromPercentText: text).map({ abs($0 - new) > 1e-9 }) ?? true {
                text = ActionSummary.percentNumber(new)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { text = ActionSummary.percentNumber(fraction) }
        }
    }

    /// The fraction a text stands for: a number in percent, written with a point or a comma and an optional percent
    /// sign, to two decimals of a percent as the other fields do. `nil` when the text is not a number.
    static func fraction(fromPercentText text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        // Past a million percent nothing is meant, and the picture could not draw it.
        guard let percent = Double(cleaned), percent.isFinite, abs(percent) <= 1_000_000 else { return nil }
        return (percent * 100).rounded() / 10_000
    }
}

/// Keeps one cursor on the cursor stack while the pointer is over a view.
@MainActor
private final class PushedCursor {
    private var current: NSCursor?

    /// Shows `cursor` (`nil`: the one the view under the pointer asks for).
    func set(_ cursor: NSCursor?) {
        guard cursor !== current else { return }
        if current != nil { NSCursor.pop() }
        current = cursor
        cursor?.push()
    }
}

// MARK: - Grid

/// The two columns of a grid: the cell picker with the size, and the preview with the number of windows.
private struct GridEditor: View {
    @Binding var grid: GridSpec
    @Binding var hoveredCell: GridCell?
    let fillOrder: GridFillOrder
    let problemFields: Set<LayoutField>

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 10) {
                CellPicker(grid: $grid, hoveredCell: $hoveredCell)
                Text(verbatim: sizeText)
                    .monospacedDigit()
                    .overlay {
                        if problemFields.contains(.rows) || problemFields.contains(.columns) {
                            Rectangle().strokeBorder(Color.red, lineWidth: 1.5).padding(-3)
                        }
                    }
            }
            VStack(spacing: 14) {
                GridPreview(grid: grid, fillOrder: fillOrder)
                WindowsStepper(grid: $grid, isOutlined: problemFields.contains(.windows))
            }
        }
    }

    /// The size the pointer is over, or the one picked.
    private var sizeText: String {
        if let cell = hoveredCell {
            LayoutEditorText.size(rows: cell.row + 1, columns: cell.column + 1)
        } else {
            LayoutEditorText.size(rows: grid.rows, columns: grid.columns)
        }
    }
}

/// An 8 × 8 picker of 18 pt cells with 3 pt gaps. Hovering lights the cells from the top-left corner to the one under
/// the pointer; a click picks them, which sets rows and columns and puts a window in every cell.
struct CellPicker: View {
    static let count = 8
    static let cell: CGFloat = 18
    static let gap: CGFloat = 3
    static let side = CGFloat(count) * cell + CGFloat(count - 1) * gap

    @Binding var grid: GridSpec
    @Binding var hoveredCell: GridCell?

    private var accent: Color { Color(nsColor: .controlAccentColor) }

    /// The corner cell of the cells that are lit: the hovered one, or the one the grid has picked.
    private var lit: GridCell {
        hoveredCell ?? GridCell(row: grid.rows - 1, column: grid.columns - 1)
    }

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(0..<Self.count, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(0..<Self.count, id: \.self) { column in
                        cellShape(isLit: row <= lit.row && column <= lit.column)
                    }
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoveredCell = Self.cell(at: location)
            case .ended:
                hoveredCell = nil
            }
        }
        .gesture(
            SpatialTapGesture().onEnded { tap in
                if let cell = Self.cell(at: tap.location) {
                    grid = LayoutDraft.grid(pickingRow: cell.row, column: cell.column)
                }
            }
        )
        .accessibilityHidden(true)
    }

    private func cellShape(isLit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isLit ? accent.opacity(0.75) : Color(nsColor: .quaternaryLabelColor).opacity(0.5))
            .frame(width: Self.cell, height: Self.cell)
    }

    /// The cell under a point of the picker; a gap belongs to the cell before it. `nil` outside the picker.
    static func cell(at point: CGPoint) -> GridCell? {
        guard point.x >= 0, point.y >= 0, point.x < Self.side, point.y < Self.side else { return nil }
        let pitch = Self.cell + Self.gap
        return GridCell(row: Int(point.y / pitch), column: Int(point.x / pitch))
    }
}

/// The layout of the grid on a 320 × 200 pt screen, each window numbered in the order the fill order gives.
private struct GridPreview: View {
    static let size = CGSize(width: 320, height: 200)

    let grid: GridSpec
    let fillOrder: GridFillOrder

    var body: some View {
        let frames = windowFrames
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor))
            ForEach(frames.indices, id: \.self) { index in
                let frame = frames[index].insetBy(dx: 3, dy: 3)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .controlAccentColor).opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 1))
                    .overlay {
                        Text(verbatim: "\(index + 1)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: max(0, frame.width), height: max(0, frame.height))
                    .offset(x: frame.minX, y: frame.minY)
            }
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement()
        .accessibilityLabel(Text(localized: "Preview of the window layout"))
    }

    /// The windows' frames on the screen; none for a grid that cannot be laid out.
    private var windowFrames: [CGRect] {
        guard grid.count >= 1, grid.rows >= 1, grid.columns >= 1 else { return [] }
        return TileLayout.grid(
            windowCount: grid.count, rows: grid.rows, columns: grid.columns, fillOrder: fillOrder
        ).frames(in: CGRect(origin: .zero, size: Self.size))
    }
}

/// "Windows", the number of them, and the buttons that take one away and add one, within 1 to rows × columns.
private struct WindowsStepper: View {
    @Binding var grid: GridSpec
    let isOutlined: Bool

    private var range: ClosedRange<Int> {
        LayoutDraft.windowRange(rows: grid.rows, columns: grid.columns)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(localized: "Windows")
            Spacer()
            button("minus", delta: -1, isEnabled: grid.count > range.lowerBound)
            Text(verbatim: "\(grid.count)")
                .monospacedDigit()
                .frame(minWidth: 28)
                .overlay {
                    if isOutlined {
                        Rectangle().strokeBorder(Color.red, lineWidth: 1.5).padding(-3)
                    }
                }
            button("plus", delta: 1, isEnabled: grid.count < range.upperBound)
        }
    }

    private func button(_ symbol: String, delta: Int, isEnabled: Bool) -> some View {
        Button {
            grid = LayoutDraft.grid(grid, windowsBy: delta)
        } label: {
            Image(systemName: symbol)
                .frame(width: 12, height: 14)
        }
        .disabled(!isEnabled)
    }
}
