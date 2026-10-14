import PiccoloCore
import SwiftUI

/// Edits the action of one binding: its kind first, then the parameters of that kind. Every
/// control sends a complete new action to the model; a rejected one leaves the control at the
/// value the model holds.
struct BindingEditor: View {
    let model: SettingsModel
    let binding: KeyBinding

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section {
                    Picker(selection: kind) {
                        ForEach(ActionKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    } label: {
                        Text(localized: "Action")
                    }
                    parameters
                }
            }
            .formStyle(.grouped)

            // The picture sits beside the form, not under it: under it, it would be pushed out
            // of the window by the custom frame's four fields.
            if let rects = ActionPreview.rects(for: binding.action) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized: "Preview")
                        .font(.headline)
                    FramePreview(rects: rects)
                }
                .frame(width: 190)
                .padding(.top, 20)
                .padding(.trailing, 16)
            }
        }
    }

    // MARK: Kind

    private var kind: Binding<ActionKind> {
        Binding(
            get: { ActionKind(binding.action) },
            set: { newKind in
                guard newKind != ActionKind(binding.action) else { return }
                model.updateAction(binding.id, to: newKind.defaultAction)
            })
    }

    // MARK: Parameters

    @ViewBuilder
    private var parameters: some View {
        switch binding.action {
        case .placeWindow(let frame):
            placeWindowParameters(frame)
        case .moveToDisplay(let direction):
            Picker(selection: displayDirection(direction)) {
                ForEach(DisplayDirection.allCases, id: \.self) { direction in
                    Text(ActionSummary.name(of: direction)).tag(direction)
                }
            } label: {
                Text(localized: "Direction")
            }
        case .arrangeGrid(let grid):
            gridParameters(grid)
        case .moveDivider(let direction):
            Picker(selection: dividerDirection(direction)) {
                ForEach(Direction.allCases, id: \.self) { direction in
                    Text(ActionSummary.name(of: direction)).tag(direction)
                }
            } label: {
                Text(localized: "Direction")
            }
        }
    }

    private func displayDirection(_ current: DisplayDirection) -> Binding<DisplayDirection> {
        Binding(
            get: { current },
            set: { model.updateAction(binding.id, to: .moveToDisplay($0)) })
    }

    private func dividerDirection(_ current: Direction) -> Binding<Direction> {
        Binding(
            get: { current },
            set: { model.updateAction(binding.id, to: .moveDivider($0)) })
    }

    // MARK: Place window

    private enum FrameChoice: Hashable {
        case preset(Preset)
        case custom
    }

    @ViewBuilder
    private func placeWindowParameters(_ frame: FrameSpec) -> some View {
        Picker(selection: frameChoice(frame)) {
            ForEach(Preset.allCases, id: \.self) { preset in
                Text(ActionSummary.name(of: preset)).tag(FrameChoice.preset(preset))
            }
            Divider()
            Text(localized: "Custom").tag(FrameChoice.custom)
        } label: {
            Text(localized: "Frame")
        }
        if case .custom(let rect) = frame {
            let left = String(localized: "Left", bundle: .module)
            let top = String(localized: "Top", bundle: .module)
            let width = String(localized: "Width", bundle: .module)
            let height = String(localized: "Height", bundle: .module)
            customField(left, rect.x, range: 0...1) { var r = rect; r.x = $0; return r }
            customField(top, rect.y, range: 0...1) { var r = rect; r.y = $0; return r }
            customField(width, rect.width, range: 0.01...1) { var r = rect; r.width = $0; return r }
            customField(height, rect.height, range: 0.01...1) { var r = rect; r.height = $0; return r }
        }
    }

    private func frameChoice(_ frame: FrameSpec) -> Binding<FrameChoice> {
        Binding(
            get: {
                switch frame {
                case .preset(let preset): .preset(preset)
                case .custom: .custom
                }
            },
            set: { choice in
                switch choice {
                case .preset(let preset):
                    model.updateAction(binding.id, to: .placeWindow(.preset(preset)))
                case .custom:
                    guard case .preset(let preset) = frame else { return }
                    // Start from the frame the preset had, so that nothing jumps.
                    let start =
                        preset.fractionalRect
                        ?? FractionalRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                    model.updateAction(binding.id, to: .placeWindow(.custom(start)))
                }
            })
    }

    private func customField(
        _ title: String, _ value: Double, range: ClosedRange<Double>,
        replacing change: @escaping (Double) -> FractionalRect
    ) -> some View {
        PercentField(title: title, fraction: value, step: 0.05, range: range) { newValue in
            model.updateAction(binding.id, to: .placeWindow(.custom(change(newValue))))
        }
    }

    // MARK: Arrange grid

    @ViewBuilder
    private func gridParameters(_ grid: GridSpec) -> some View {
        gridStepper(
            String(localized: "Windows", bundle: .module), grid, \.count, in: 1...max(1, grid.rows * grid.columns))
        gridStepper(String(localized: "Rows", bundle: .module), grid, \.rows, in: 1...max(8, grid.rows))
        gridStepper(String(localized: "Columns", bundle: .module), grid, \.columns, in: 1...max(8, grid.columns))
    }

    /// A whole number with the usual arrows, laid out like the percentage fields.
    private func gridStepper(
        _ title: String, _ grid: GridSpec, _ field: WritableKeyPath<GridSpec, Int>,
        in range: ClosedRange<Int>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Text(verbatim: "\(grid[keyPath: field])")
                    .monospacedDigit()
                Stepper(title, value: gridValue(grid, field), in: range)
                    .labelsHidden()
            }
        }
    }

    private func gridValue(_ grid: GridSpec, _ field: WritableKeyPath<GridSpec, Int>) -> Binding<Int> {
        Binding(
            get: { grid[keyPath: field] },
            set: { newValue in
                var changed = grid
                changed[keyPath: field] = newValue
                model.updateAction(binding.id, to: .arrangeGrid(changed))
            })
    }
}
