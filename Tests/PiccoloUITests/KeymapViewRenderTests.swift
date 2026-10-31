import AppKit
import SwiftUI
import Testing

import PiccoloCore

@testable import PiccoloUI

/// Draws the Shortcuts tab and its pieces into bitmaps, off screen, as a smoke test that every state of the
/// keymap can be built and laid out, and that each state looks different from the one it departs from. Nothing
/// is shown and no permission is involved.
///
/// Set `PICCOLO_RENDER_DIR` to a folder to keep the images, for example to look at the layout in light and dark
/// appearance.
@MainActor
@Suite("Keymap views render")
struct KeymapViewRenderTests {
    /// Tall enough for the whole keymap, so that the last card is in the picture.
    private static let tabSize = NSSize(width: 640, height: 1900)

    private let host = SettingsHost(
        isAccessibilityTrusted: { true },
        openAccessibilitySettings: {},
        revealConfigInFinder: {},
        appVersion: "0.1.0 (1)")

    private static let leftHalf = Action.placeWindow(.preset(.leftHalf))
    private static let topLeft = Action.placeWindow(.preset(.topLeft))
    private static let leftRow = KeymapRowID.builtIn(leftHalf)
    private static let topLeftRow = KeymapRowID.builtIn(topLeft)
    private static let area = KeyBinding(
        action: .placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1))), shortcut: UIFixture.f14)
    private static let shiftA = Shortcut(keyCode: 0, modifiers: [.shift])
    private static let controlOptionLeft = Shortcut(keyCode: 123, modifiers: [.control, .option])

    /// A model on the default shortcuts, which have four grids and no custom area, or on `bindings`.
    private func model(
        _ bindings: [KeyBinding] = Config.defaultShortcuts.bindings, issues: [String] = []
    ) -> SettingsModel {
        let backend = InMemorySettingsBackend(config: Config(bindings: bindings), issues: issues)
        return SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage()) { code in
            ["0": "a", "11": "b"][String(code)]
        }
    }

    private func tab(_ model: SettingsModel) -> ShortcutsTab {
        ShortcutsTab(model: model, host: host)
    }

    /// Renders `view` at `size` with the given appearance and returns the bitmap.
    private func render<Content: View>(
        _ view: Content, size: NSSize = KeymapViewRenderTests.tabSize, dark: Bool
    ) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    /// Whether the bitmap shows more than one colour, which a view that failed to draw does not. Every `step`th
    /// pixel is looked at.
    private func hasContent(_ bitmap: NSBitmapImageRep, step: Int = 7) -> Bool {
        guard let first = bitmap.colorAt(x: 0, y: 0) else { return false }
        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
                if let color = bitmap.colorAt(x: x, y: y), color != first { return true }
            }
        }
        return false
    }

    private func png(_ bitmap: NSBitmapImageRep) -> Data? {
        bitmap.representation(using: .png, properties: [:])
    }

    private func keep(_ bitmap: NSBitmapImageRep, as name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PICCOLO_RENDER_DIR"],
            let data = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: directory).appending(path: "\(name).png"))
    }

    /// The tab in the state `prepare` brings `model()` to, drawn in light and dark, each of which must differ
    /// from `baseline` (the default tab in the same appearance), and must not be blank.
    private func expectDiffers(
        from baseline: [Bool: Data], named name: String, _ prepare: (SettingsModel) -> Void,
        bindings: [KeyBinding] = Config.defaultShortcuts.bindings, issues: [String] = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        for dark in [false, true] {
            let appearance = dark ? "dark" : "light"
            let model = model(bindings, issues: issues)
            prepare(model)
            let bitmap = try render(tab(model), dark: dark)
            #expect(hasContent(bitmap), "\(name) is blank in \(appearance) appearance", sourceLocation: sourceLocation)
            #expect(
                png(bitmap) != baseline[dark],
                "\(name) looks like the default tab in \(appearance) appearance", sourceLocation: sourceLocation)
            keep(bitmap, as: "keymap-\(name)-\(appearance)")
        }
    }

    /// The default tab in light and dark appearance.
    private func baseline() throws -> [Bool: Data] {
        var images: [Bool: Data] = [:]
        for dark in [false, true] {
            let bitmap = try render(tab(model()), dark: dark)
            #expect(hasContent(bitmap), "the keymap is blank in \(dark ? "dark" : "light") appearance")
            keep(bitmap, as: "keymap-default-\(dark ? "dark" : "light")")
            images[dark] = png(bitmap)
        }
        return images
    }

    // MARK: Glyphs

    /// One action of every kind of glyph, and the variants that look different.
    private static let glyphActions: [(String, Action, GridFillOrder)] =
        [
            ("leftHalf", leftHalf, .rows),
            ("rightHalf", .placeWindow(.preset(.rightHalf)), .rows),
            ("topLeft", topLeft, .rows),
            ("leftThird", .placeWindow(.preset(.leftThird)), .rows),
            ("rightTwoThirds", .placeWindow(.preset(.rightTwoThirds)), .rows),
            ("maximize", .placeWindow(.preset(.maximize)), .rows),
            ("center", .placeWindow(.preset(.center)), .rows),
            ("custom", area.action, .rows),
            ("grid 4 in 2 × 2", .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)), .rows),
            ("grid 3 in 2 × 2, rows first", .arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2)), .rows),
            ("grid 3 in 2 × 2, columns first", .arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2)), .columns),
            ("restore", .restoreWindow, .rows),
        ]
        + DisplayDirection.allCases.map { ("display \($0.rawValue)", Action.moveToDisplay($0), GridFillOrder.rows) }
        + Direction.allCases.map { ("divider \($0.rawValue)", Action.moveDivider($0), GridFillOrder.rows) }
        + Direction.allCases.map { ("swap \($0.rawValue)", Action.swapWindow($0), GridFillOrder.rows) }

    @Test("every kind of glyph draws something, and no two of them draw the same", arguments: [false, true])
    func glyphs(dark: Bool) throws {
        var seen: [Data: String] = [:]
        for (name, action, fillOrder) in Self.glyphActions {
            let view = ActionGlyph(action: action, fillOrder: fillOrder)
                .frame(width: ActionGlyph.size.width, height: ActionGlyph.size.height)
            let bitmap = try render(
                view, size: NSSize(width: ActionGlyph.size.width, height: ActionGlyph.size.height), dark: dark)
            #expect(hasContent(bitmap, step: 1), "the glyph of \(name) is blank")
            let data = try #require(png(bitmap))
            if let other = seen[data] {
                Issue.record("the glyphs of \(name) and \(other) look the same")
            }
            seen[data] = name
        }
    }

    @Test("the glyph of a grid follows the fill order, and a frame does not")
    func glyphFollowsFillOrder() throws {
        let grid = Action.arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2))
        let size = NSSize(width: ActionGlyph.size.width, height: ActionGlyph.size.height)
        func glyph(_ action: Action, _ order: GridFillOrder) throws -> Data? {
            png(try render(ActionGlyph(action: action, fillOrder: order), size: size, dark: false))
        }
        #expect(try glyph(grid, .rows) != glyph(grid, .columns))
        #expect(try glyph(Self.leftHalf, .rows) == glyph(Self.leftHalf, .columns))
    }

    /// The bitmap of a glyph, at its size.
    private func glyph(_ kind: ActionGlyphKind, dark: Bool) throws -> NSBitmapImageRep {
        try render(
            ActionGlyph(kind: kind),
            size: NSSize(width: ActionGlyph.size.width, height: ActionGlyph.size.height), dark: dark)
    }

    /// The sRGB components of the pixel that holds `point`, in points from the top-left corner of a glyph-sized bitmap.
    private func pixel(_ bitmap: NSBitmapImageRep, at point: CGPoint, in size: CGSize = ActionGlyph.size)
        -> [CGFloat]?
    {
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / size.width)
        let y = Int(point.y * CGFloat(bitmap.pixelsHigh) / size.height)
        return components(of: bitmap.colorAt(x: x, y: y))
    }

    private func components(of color: NSColor?) -> [CGFloat]? {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
    }

    /// Whether two colours look the same: every channel within `tolerance`. False when either is missing.
    private func same(_ first: [CGFloat]?, _ second: [CGFloat]?, tolerance: CGFloat = 0.02) -> Bool {
        guard let first, let second else { return false }
        return zip(first, second).allSatisfy { abs($0 - $1) <= tolerance }
    }

    @Test(
        "the arrow of a divider or a swap sits on a pill of the screen's colour, which hides the split behind it",
        arguments: [false, true])
    func arrowPill(dark: Bool) throws {
        let size = ActionGlyph.size
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        // The pill is the colour of the screen: that of the bare screen's inside, beside its frame.
        let pill = try #require(pixel(try glyph(.frames([]), dark: dark), at: CGPoint(x: 4, y: centre.y)))
        for direction in Direction.allCases {
            // The split runs through the centre: vertically for a left or right direction, horizontally for up or down.
            let horizontalSplit = direction == .up || direction == .down
            // Points along the split, 0.5 pt apart, from 2.5 pt short of one end to 2.5 pt short of the other: the
            // windows reach 2 pt from the glyph's edges, so these lie on the split.
            let length = horizontalSplit ? size.width : size.height
            let along = stride(from: CGFloat(2.5), through: length - 2.5, by: 0.5).map { offset in
                horizontalSplit ? CGPoint(x: offset, y: centre.y) : CGPoint(x: centre.x, y: offset)
            }
            for kind in [ActionGlyphKind.divider(direction), .swap(direction)] {
                let bitmap = try glyph(kind, dark: dark)
                let onPill = along.map { same(pixel(bitmap, at: $0), pill) }
                // The ends of the split are outside the arrow's pill, where the split is drawn.
                #expect(
                    onPill.first == false && onPill.last == false,
                    "the split is not drawn at its ends for \(kind), appearance dark: \(dark)")
                // The arrow sits in the middle of the split, on a pill that covers the split where the arrow is not.
                #expect(
                    onPill.filter { $0 }.count >= 4,
                    "the pill does not cover the split for \(kind), appearance dark: \(dark)")
            }
        }
    }

    @Test(
        "the arrow of a display sits inside the small screen, which is drawn with its frame and no windows",
        arguments: [false, true])
    func displayInsideScreen(dark: Bool) throws {
        let size = ActionGlyph.size
        let screen = try glyph(.frames([]), dark: dark)
        // The arrow is in the middle, from 5 pt to 5 pt short of the right edge: the rest is the bare screen.
        let middle = 5.0...(size.width - 5)
        for direction in DisplayDirection.allCases {
            let bitmap = try glyph(.display(direction), dark: dark)
            var outside = 0
            var arrowDrawn = false
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    let point = CGPoint(
                        x: (CGFloat(x) + 0.5) * size.width / CGFloat(bitmap.pixelsWide),
                        y: (CGFloat(y) + 0.5) * size.height / CGFloat(bitmap.pixelsHigh))
                    let matches = same(pixel(bitmap, at: point), pixel(screen, at: point), tolerance: 0.001)
                    if middle.contains(point.x) {
                        arrowDrawn = arrowDrawn || !matches
                    } else if !matches {
                        outside += 1
                    }
                }
            }
            #expect(
                outside == 0,
                "the glyph of \(direction) differs from the bare screen at \(outside) pixels outside the arrow")
            #expect(arrowDrawn, "the arrow of \(direction) is not drawn")
            // The frame's stroke lies along the left edge, the screen's fill 3 pt inside it.
            let edge = pixel(bitmap, at: CGPoint(x: 0.5, y: size.height / 2))
            let fill = pixel(bitmap, at: CGPoint(x: 4, y: size.height / 2))
            #expect(!same(edge, fill, tolerance: 0.001), "the frame of \(direction) is not drawn, appearance dark: \(dark)")
        }
    }

    /// The sRGB components of the accent colour as the render draws it in the given appearance, which is not
    /// those of `NSColor.controlAccentColor` itself: the bitmap's colour space shifts a saturated colour.
    private func drawnAccent(dark: Bool) throws -> [CGFloat]? {
        let size = ActionGlyph.size
        let swatch = try render(
            Color(nsColor: .controlAccentColor), size: NSSize(width: size.width, height: size.height), dark: dark)
        return pixel(swatch, at: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    /// Whether the ink drawn on `background` within `region` (in points from the top-left corner of a glyph-sized
    /// bitmap) is the accent colour. The most strongly inked pixel of the region is looked at: a pixel the arrow
    /// covers only in part is a mix of the background and the arrow's colour, so it must lie on the line from one
    /// to the other, and be at least halfway to the accent colour.
    private func inkIsAccent(
        _ bitmap: NSBitmapImageRep, on background: [CGFloat], accent: [CGFloat], in region: CGRect
    ) -> Bool {
        let size = ActionGlyph.size
        func distance(_ first: [CGFloat], _ second: [CGFloat]) -> CGFloat {
            sqrt(zip(first.prefix(3), second.prefix(3)).map { ($0 - $1) * ($0 - $1) }.reduce(0, +))
        }
        let reach = distance(accent, background)
        guard reach > 0 else { return false }
        var strongest: (pixel: [CGFloat], distance: CGFloat)?
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                let point = CGPoint(
                    x: (CGFloat(x) + 0.5) * size.width / CGFloat(bitmap.pixelsWide),
                    y: (CGFloat(y) + 0.5) * size.height / CGFloat(bitmap.pixelsHigh))
                guard region.contains(point), let pixel = components(of: bitmap.colorAt(x: x, y: y)) else { continue }
                let away = distance(pixel, background)
                if away > (strongest?.distance ?? 0) { strongest = (pixel, away) }
            }
        }
        guard let strongest else { return false }
        let coverage = strongest.distance / reach
        let expected = zip(background, accent).map { $0 + coverage * ($1 - $0) }
        return coverage >= 0.5 && same(strongest.pixel, expected, tolerance: 0.04)
    }

    @Test(
        "every arrow of the glyphs, on a split or in a display's screen, is drawn in the accent colour",
        arguments: [false, true])
    func arrowsAreAccent(dark: Bool) throws {
        let size = ActionGlyph.size
        let accent = try #require(try drawnAccent(dark: dark))
        // The screen's colour: that of the bare screen's inside, beside its frame.
        let screen = try #require(pixel(try glyph(.frames([]), dark: dark), at: CGPoint(x: 4, y: size.height / 2)))
        // Where an arrow is: on the pill in the middle of a split, which lies well inside the pill, and in the
        // middle of the screen of a display, clear of its frame.
        let split = CGRect(x: size.width / 2 - 4, y: size.height / 2 - 3, width: 8, height: 6)
        let display = CGRect(x: 5, y: 3, width: size.width - 10, height: size.height - 6)
        var kinds: [(String, ActionGlyphKind, CGRect)] = []
        for direction in Direction.allCases {
            kinds.append(("divider \(direction.rawValue)", .divider(direction), split))
            kinds.append(("swap \(direction.rawValue)", .swap(direction), split))
        }
        for direction in DisplayDirection.allCases {
            kinds.append(("display \(direction.rawValue)", .display(direction), display))
        }
        for (name, kind, region) in kinds {
            let bitmap = try glyph(kind, dark: dark)
            #expect(
                inkIsAccent(bitmap, on: screen, accent: accent, in: region),
                "the arrow of \(name) is not drawn in the accent colour, appearance dark: \(dark)")
        }
    }

    // MARK: The tab

    @Test("the default tab renders in light and dark appearance")
    func defaultTab() throws {
        _ = try baseline()
    }

    @Test("a row that records looks different from the tab without a recording")
    func recordingRow() throws {
        let images = try baseline()
        try expectDiffers(from: images, named: "recording") { model in
            #expect(model.beginRecording(Self.leftRow))
            #expect(model.recordingRow == Self.leftRow)
        }
    }

    @Test("a row with a recording of a row that has no shortcut looks different from one that has one")
    func recordingUnboundRow() throws {
        let images = try baseline()
        try expectDiffers(from: images, named: "recording-unbound") { model in
            #expect(model.beginRecording(.builtIn(.moveToDisplay(.next))))
        }
    }

    @Test("a shortcut that cannot be global shows its reason under the row")
    func rowError() throws {
        let images = try baseline()
        try expectDiffers(from: images, named: "row-error") { model in
            model.beginRecording(Self.leftRow)
            model.record(Self.shiftA)
            #expect(model.errorTarget == .row(Self.leftRow))
            #expect(model.error != nil)
        }
        // The reason is more than the recording: the same recording without it looks different.
        let recording = model()
        recording.beginRecording(Self.leftRow)
        let failing = model()
        failing.beginRecording(Self.leftRow)
        failing.record(Self.shiftA)
        #expect(
            png(try render(tab(recording), dark: false)) != png(try render(tab(failing), dark: false)),
            "the reason does not change the tab")
    }

    @Test("a shortcut another row has shows the box with Cancel and Replace")
    func conflictBox() throws {
        let images = try baseline()
        try expectDiffers(from: images, named: "conflict") { model in
            model.beginRecording(Self.topLeftRow)
            model.record(Self.controlOptionLeft)
            #expect(model.pendingConflict?.row == Self.topLeftRow)
        }
        // Cancel takes the box away again.
        let model = model()
        model.beginRecording(Self.topLeftRow)
        model.record(Self.controlOptionLeft)
        let withBox = png(try render(tab(model), dark: false))
        model.resolveConflict(replace: false)
        #expect(png(try render(tab(model), dark: false)) == images[false], "cancelling left something behind")
        #expect(withBox != images[false])
    }

    @Test("a built-in row with an extra binding shows it as a tag")
    func extraTag() throws {
        let images = try baseline()
        let extra = KeyBinding(action: Self.leftHalf, shortcut: UIFixture.f15)
        try expectDiffers(
            from: images, named: "extra-tag", { model in
                #expect(model.keymap.flatMap(\.rows).first { $0.id == Self.leftRow }?.bindings.count == 2)
            }, bindings: Config.defaultShortcuts.bindings + [extra])
    }

    @Test("the Custom Areas card without a row still draws, and a row in it makes it look different")
    func customAreasCard() throws {
        let images = try baseline()
        let empty = model()
        let group = try #require(empty.keymap.first { $0.section == .customAreas })
        #expect(group.rows.isEmpty, "the default shortcuts have a custom area")
        try expectDiffers(
            from: images, named: "custom-area-row", { model in
                #expect(model.keymap.first { $0.section == .customAreas }?.rows.count == 1)
            }, bindings: Config.defaultShortcuts.bindings + [Self.area])
    }

    @Test("a search that matches nothing draws the empty state")
    func searchWithoutMatches() throws {
        let images = try baseline()
        try expectDiffers(from: images, named: "no-match") { model in
            model.setSearch("zzz")
            #expect(model.keymap.isEmpty)
        }
    }

    @Test("a search draws the rows it keeps, with the clear button")
    func searchWithMatches() throws {
        let images = try baseline()
        try expectDiffers(from: images, named: "search") { model in
            model.setSearch("left")
            #expect(!model.keymap.isEmpty)
        }
    }

    @Test("the problems with the config show in a banner")
    func issuesBanner() throws {
        let images = try baseline()
        try expectDiffers(
            from: images, named: "issues", { _ in },
            issues: [
                "bindings[4] shortcut was refused: taken by the system",
                "bindings[7] skipped: the action is unknown",
            ])
    }

    @Test("an error that belongs to no row shows in the banner too, and one that belongs to a field does not")
    func windowError() throws {
        let images = try baseline()
        try expectDiffers(from: images, named: "window-error") { model in
            #expect(!model.removeBinding(UUID()))
            #expect(model.errorTarget == .window)
        }

        let field = model()
        #expect(!field.setGap(100))
        #expect(field.errorTarget == .field(.gap))
        #expect(
            png(try render(tab(field), dark: false)) == images[false],
            "an error of the General tab's field shows on the Shortcuts tab")
    }

    @Test("a shortcut that is not active is marked")
    func inactiveMark() throws {
        let images = try baseline()
        let config = Config.defaultShortcuts
        let backend = InMemorySettingsBackend(config: config)
        backend.inactive = [try #require(config.bindings.first).id]
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage())
        let bitmap = try render(tab(model), dark: false)
        #expect(hasContent(bitmap))
        #expect(png(bitmap) != images[false], "the inactive shortcut is not marked")
    }

    @Test("the ⋯ button is as tall as the search field, and the row of the two is no taller than the field")
    func menuButtonHeight() {
        let view = tab(model())
        let search = fittingHeight(view.searchField)
        #expect(search > 0)
        #expect(
            fittingHeight(view.menu) == search,
            "the ⋯ button is \(fittingHeight(view.menu)) pt tall, the search field \(search) pt")
        #expect(
            fittingHeight(view.controls) == search,
            "the search field and the ⋯ button make \(fittingHeight(view.controls)) pt, search field \(search) pt")
    }

    @Test(
        "the ⋯ button draws a bezel over its whole 30 pt × search field height, with rounded corners",
        arguments: [false, true])
    func menuButtonBezel(dark: Bool) throws {
        let size = CGSize(width: ShortcutsTab.menuWidth, height: ShortcutsTab.controlHeight)
        let pixels = NSSize(width: size.width, height: size.height)
        let window = Color(nsColor: .windowBackgroundColor)
        let button = try render(tab(model()).menu.background(window), size: pixels, dark: dark)
        let bare = try render(window, size: pixels, dark: dark)
        func at(_ bitmap: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> [CGFloat]? {
            pixel(bitmap, at: CGPoint(x: x, y: y), in: size)
        }
        let background = at(bare, 0.5, 0.5)
        // The bezel reaches 2 pt short of each edge, so that it is as tall and as wide as the button: a system
        // menu draws a capsule about half as tall.
        let inside: [(CGFloat, CGFloat)] = [
            (size.width / 2, 2), (size.width / 2, size.height - 2), (2, size.height / 2),
            (size.width - 2, size.height / 2),
        ]
        for (x, y) in inside {
            #expect(
                !same(at(button, x, y), background, tolerance: 0.01),
                "the ⋯ button draws no bezel at (\(x), \(y)), appearance dark: \(dark)")
        }
        // The very corner lies outside the 6 pt radius.
        #expect(same(at(button, 0.5, 0.5), background, tolerance: 0.01), "the corner of the ⋯ button is not rounded")
    }

    /// The height a view asks for, laid out off screen.
    private func fittingHeight<Content: View>(_ view: Content) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.height
    }
}
