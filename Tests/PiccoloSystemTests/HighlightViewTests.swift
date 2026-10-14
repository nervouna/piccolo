import AppKit
import Testing

@testable import PiccoloSystem

/// What the highlight looks like, drawn into a bitmap of its own (nothing is put on screen): a
/// rounded rectangle filled with the accent colour at low opacity and outlined with it, the same in
/// light and dark mode.
@MainActor
@Suite("Highlight view")
struct HighlightViewTests {
    private static let size = CGSize(width: 300, height: 200)

    /// The view drawn at 1 pixel per point in `appearance`.
    private func render(_ appearanceName: NSAppearance.Name) throws -> NSBitmapImageRep {
        let view = HighlightView(frame: CGRect(origin: .zero, size: Self.size))
        view.appearance = NSAppearance(named: appearanceName)
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(Self.size.width), pixelsHigh: Int(Self.size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// The accent colour as `appearanceName` resolves it, as device RGB.
    private func accent(in appearanceName: NSAppearance.Name) throws -> NSColor {
        var resolved: NSColor?
        try #require(NSAppearance(named: appearanceName)).performAsCurrentDrawingAppearance {
            resolved = NSColor.controlAccentColor.usingColorSpace(.deviceRGB)
        }
        return try #require(resolved)
    }

    private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> NSColor {
        try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }

    private func expectColor(
        _ color: NSColor, is accent: NSColor, alpha: ClosedRange<CGFloat>, _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(alpha.contains(color.alphaComponent), "\(what) has alpha \(color.alphaComponent), expected \(alpha)", sourceLocation: sourceLocation)
        for (name, got, wanted) in [
            ("red", color.redComponent, accent.redComponent),
            ("green", color.greenComponent, accent.greenComponent),
            ("blue", color.blueComponent, accent.blueComponent),
        ] {
            #expect(
                abs(got - wanted) < 0.06, "\(what) has \(name) \(got), the accent colour has \(wanted)",
                sourceLocation: sourceLocation)
        }
    }

    @Test("the inside is the accent colour at low opacity", arguments: [NSAppearance.Name.aqua, .darkAqua])
    func fill(appearance: NSAppearance.Name) throws {
        let rep = try render(appearance)
        let accent = try accent(in: appearance)
        expectColor(try pixel(rep, 150, 100), is: accent, alpha: 0.15...0.25, "the middle")
        expectColor(try pixel(rep, 30, 30), is: accent, alpha: 0.15...0.25, "a point inside, near a corner")
    }

    @Test("the border is the accent colour, opaque, 3 points wide, on all four sides", arguments: [NSAppearance.Name.aqua, .darkAqua])
    func border(appearance: NSAppearance.Name) throws {
        let rep = try render(appearance)
        let accent = try accent(in: appearance)
        for (x, y, side) in [(1, 100, "left"), (298, 100, "right"), (150, 1, "top"), (150, 198, "bottom")] {
            expectColor(try pixel(rep, x, y), is: accent, alpha: 0.97...1, "the \(side) border")
        }
        // 3 points in, the border is over and the fill shows.
        expectColor(try pixel(rep, 4, 100), is: accent, alpha: 0.15...0.25, "just inside the left border")
        expectColor(try pixel(rep, 150, 4), is: accent, alpha: 0.15...0.25, "just inside the top border")
    }

    @Test("the corners are rounded: the very corner is empty, and the radius is about 10 points", arguments: [NSAppearance.Name.aqua, .darkAqua])
    func corners(appearance: NSAppearance.Name) throws {
        let rep = try render(appearance)
        #expect(try pixel(rep, 0, 0).alphaComponent < 0.05, "the top-left corner pixel is drawn")
        #expect(try pixel(rep, 299, 199).alphaComponent < 0.05, "the bottom-right corner pixel is drawn")
        // The edge is straight again at the end of the radius.
        #expect(try pixel(rep, 12, 1).alphaComponent > 0.97, "the top border has not started 12 points from the corner")
        #expect(try pixel(rep, 1, 12).alphaComponent > 0.97, "the left border has not started 12 points from the corner")
    }

    @Test("the panel never becomes key or main and ignores the mouse")
    func panelBehaviour() {
        let panel = HighlightPanel()
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(!panel.hidesOnDeactivate, "a panel hides when its app is not active, and Piccolo never is")
        #expect(panel.level == HighlightPanels.level)
        #expect(panel.level.rawValue > NSWindow.Level.floating.rawValue)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(!panel.isOpaque)
        #expect(!panel.hasShadow)
    }

    @Test("the panel keeps exactly the frame it is given, also where a normal window would be moved")
    func exactFrame() {
        let panel = HighlightPanel()
        let offScreen = CGRect(x: -5000, y: -5000, width: 300, height: 200)
        #expect(panel.constrainFrameRect(offScreen, to: nil) == offScreen)
    }
}
