import SwiftUI

/// A screen-shaped rectangle with the windows an action produces drawn on it. Colours come from
/// the system, so it follows light and dark mode and the accent colour.
struct FramePreview: View {
    /// Rectangles in the unit square, origin at the top-left. See ``ActionPreview``.
    let rects: [CGRect]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                ForEach(rects.indices, id: \.self) { index in
                    let rect = rects[index]
                    Rectangle()
                        .fill(Color(nsColor: .controlAccentColor).opacity(0.3))
                        .overlay(Rectangle().strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 1))
                        .frame(width: rect.width * proxy.size.width, height: rect.height * proxy.size.height)
                        .offset(x: rect.minX * proxy.size.width, y: rect.minY * proxy.size.height)
                }
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .frame(maxWidth: 176)
        .accessibilityElement()
        .accessibilityLabel("Preview of the window layout")
    }
}
