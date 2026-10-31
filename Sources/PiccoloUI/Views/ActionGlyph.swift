import PiccoloCore
import SwiftUI

/// What a row's glyph draws, decided from the row's action. Pure, so that a unit test covers every action
/// without a view.
enum ActionGlyphKind: Equatable {
    /// Windows on a small screen: a preset or custom frame, or the cells of a grid in the fill order. Rectangles
    /// in the unit square (see ``ActionPreview``).
    case frames([CGRect])
    /// A move to another display: an arrow in a small screen, with a bar for the next and previous display.
    case display(DisplayDirection)
    /// Two light halves split along the divider, with the arrow of the direction the divider moves.
    case divider(Direction)
    /// Two filled halves, with the arrow of the side the windows trade with.
    case swap(Direction)
    /// A dashed frame in the middle of the screen with a turning arrow.
    case restore

    init(_ action: Action, fillOrder: GridFillOrder) {
        switch action {
        case .placeWindow, .arrangeGrid:
            self = .frames(ActionPreview.rects(for: action, fillOrder: fillOrder) ?? [])
        case .moveToDisplay(let direction):
            self = .display(direction)
        case .moveDivider(let direction):
            self = .divider(direction)
        case .swapWindow(let direction):
            self = .swap(direction)
        case .restoreWindow:
            self = .restore
        }
    }

    /// Two halves of the screen, split by a vertical line for a left or right direction and by a horizontal one
    /// for up or down.
    static func halves(split direction: Direction) -> [CGRect] {
        switch direction {
        case .left, .right:
            [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .up, .down:
            [CGRect(x: 0, y: 0, width: 1, height: 0.5), CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]
        }
    }

    static func arrowSymbol(_ direction: Direction) -> String {
        switch direction {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }

    /// The arrow for a display: the bar-ended arrows stand for ⇥ (next) and ⇤ (previous).
    static func displaySymbol(_ direction: DisplayDirection) -> String {
        switch direction {
        case .next: "arrow.right.to.line"
        case .previous: "arrow.left.to.line"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }
}

/// The 30 × 19 pt picture before a row's name: the frame or the grid cells on a small screen, and a mark for the
/// actions that place nothing on their own. Colours come from the system, so it follows light and dark mode and the
/// accent colour.
struct ActionGlyph: View {
    static let size = CGSize(width: 30, height: 19)
    /// The room around the windows on the small screen.
    private static let inset: CGFloat = 2

    let kind: ActionGlyphKind

    init(action: Action, fillOrder: GridFillOrder) {
        kind = ActionGlyphKind(action, fillOrder: fillOrder)
    }

    init(kind: ActionGlyphKind) {
        self.kind = kind
    }

    private var accent: Color { Color(nsColor: .controlAccentColor) }

    var body: some View {
        content
            .frame(width: Self.size.width, height: Self.size.height)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .frames(let rects):
            screen {
                windows(rects, filled: true)
            }
        case .display(let direction):
            screen {
                Image(systemName: ActionGlyphKind.displaySymbol(direction))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.size.width, height: Self.size.height)
            }
        case .divider(let direction):
            screen {
                windows(ActionGlyphKind.halves(split: direction), filled: false)
                arrow(direction, color: accent)
            }
        case .swap(let direction):
            screen {
                windows(ActionGlyphKind.halves(split: direction), filled: true)
                arrow(direction, color: .primary)
            }
        case .restore:
            screen {
                // The screen's content is laid out from the top-left corner: this one is centred.
                ZStack {
                    RoundedRectangle(cornerRadius: 1.5)
                        .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2.5, 1.5]))
                        .frame(width: Self.size.width * 0.62, height: Self.size.height * 0.62)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: Self.size.width, height: Self.size.height)
            }
        }
    }

    // MARK: Pieces

    /// The small screen the windows are drawn on.
    private func screen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: .controlBackgroundColor))
            content()
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// The windows of `rects`, a filled one with the accent colour or a light one.
    private func windows(_ rects: [CGRect], filled: Bool) -> some View {
        let width = Self.size.width - 2 * Self.inset
        let height = Self.size.height - 2 * Self.inset
        return ZStack(alignment: .topLeading) {
            ForEach(rects.indices, id: \.self) { index in
                let rect = rects[index]
                Rectangle()
                    .fill(accent.opacity(filled ? 0.35 : 0.12))
                    .overlay(Rectangle().strokeBorder(accent.opacity(filled ? 1 : 0.55), lineWidth: 0.75))
                    .frame(width: max(1, rect.width * width), height: max(1, rect.height * height))
                    .offset(x: Self.inset + rect.minX * width, y: Self.inset + rect.minY * height)
            }
        }
    }

    /// The arrow across the split, centred on a pill of the screen's colour, so that the split line stops behind it.
    private func arrow(_ direction: Direction, color: Color) -> some View {
        Image(systemName: ActionGlyphKind.arrowSymbol(direction))
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 2)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
            .frame(width: Self.size.width, height: Self.size.height)
    }
}
