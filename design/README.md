# Design files

| File | What it is |
|---|---|
| `icon.png` | Source artwork of the app icon, 1024×1024. `scripts/make-icon.sh` turns it into `App/Assets.xcassets/AppIcon.appiconset` (see "App icon" in `CLAUDE.md`). |
| `menubar-icon-latte.svg` | Menu bar glyph, latte: 17 × 16 pt on the 16 pt grid. Chosen by the owner; the app ships it as `MenuBarIcon`. |
| `menubar-icon-latte-18pt.svg` | The latte on the previous 19 × 18 pt grid. Superseded and not used by the app; kept only so the preview can compare the two sizes. |
| `menubar-icon.svg` | Menu bar glyph, candidate 1 (filled panes): 19 × 18 pt on the 18 pt grid. Not used by the app. |
| `menubar-icon-outline.svg` | Menu bar glyph, candidate 2 (outline): 19 × 18 pt on the 18 pt grid. Not used by the app. |
| `menubar-preview.png` | Candidate 1, the 16 pt latte, the 18 pt latte and candidate 2, each at 16, 18 and 22 pt, at 1x and 2x, on a light and a dark menu bar, plus a magnified view of the 1x pixels. |
| `render-menubar-preview.swift` | Script that renders `menubar-preview.png` from the SVGs in its `candidates` array. |

## The menu bar glyph

The glyph is the app icon's glass reduced to one colour: a tapered tumbler split by gutters into an empty top pane and, below it, a larger left pane and a narrower right pane. All drawings are black on transparent, one SVG unit per point, with no colour, shadow or gradient.

The shipping latte is drawn on a 16 pt grid, 17 × 16 pt. Every line and gap is 1 pt, and every horizontal and vertical edge sits on a whole point, so those lines are crisp at 1x. Only the leaning sides are anti-aliased.

- Rows (y, pt): outline 0–1, gap 1–2, empty top pane 2–7, gutter 7–8, bottom panes 8–14, gap 14–15, outline 15–16.
- Columns in the bottom panes (x, pt): the left pane ends at x = 10, the vertical gutter is 10–11, the right pane starts at x = 11. Both panes sit 1 pt inside the outline, so their outer sides lean with it.
- The sides lean in by 1 pt from y = 1 to y = 13. The top corners have a 1 pt radius and the bottom corners a 3 pt radius. The inner corners of the outline (2 pt) and the bottom corners of the panes (1 pt) are concentric with them, as on the app icon.

The other drawings stay on the 18 pt grid:

- `menubar-icon-latte-18pt.svg` (superseded): outline 0–1, gap 1–2, top pane 2–8, gutter 8–9, bottom panes 9–16, gap 16–17, outline 17–18, vertical gutter at x 11–12.
- `menubar-icon.svg` (candidate 1): the same 18 pt grid with three solid panes separated by 1 pt transparent gutters.
- `menubar-icon-outline.svg` (candidate 2): the 18 pt outline with the two gutters drawn as 1 pt lines and the panes left empty.

The latte was redrawn on its own grid rather than scaled: the 18 pt drawing scaled by 8/9 puts its 1 pt lines between pixels at 1x. The latte's top pane is empty, so the gutter row above the bottom panes is transparent like the empty pane. At 1x the panes and the vertical gutter are what separate the parts.

## How `MenuBarIcon` is made

`App/Assets.xcassets/MenuBarIcon.imageset/` holds a copy of `menubar-icon-latte.svg` (under the name `menubar-icon.svg`) and a `Contents.json` that asks for the vector data to be preserved and for the template rendering intent:

```json
"properties" : {
  "preserves-vector-representation" : true,
  "template-rendering-intent" : "template"
}
```

The system tints a template image for light, dark and highlighted menu bars, so the SVG stays black on transparent. `App/PiccoloApp.swift` uses it as `MenuBarExtra("Piccolo", image: "MenuBarIcon")`; the title is the accessibility label. The image has no size of its own, so the asset's intrinsic size, 17 × 16 pt for the latte, is what the menu bar gets.

To change the glyph, edit `design/menubar-icon-latte.svg` on the 16 pt grid, copy it over the file in the image set (keep the file name `menubar-icon.svg`, `Contents.json` refers to it) and render the preview again. To ship another drawing, copy its SVG over the image set's `menubar-icon.svg`: `menubar-icon.svg` or `menubar-icon-outline.svg` (18 pt grid) or `menubar-icon-latte-18pt.svg`. Check the result with `scripts/build.sh release` and:

```sh
xcrun --sdk macosx assetutil --info build/Piccolo.app/Contents/Resources/Assets.car | grep -B12 '"Template Mode"'
```

which lists `MenuBarIcon` at 1x and 2x with `"Template Mode" : "template"` and `"Preserved Vector Representation" : true`, and the pixel size of each rendition (17 × 16 and 34 × 32 for the latte).

## Rendering the preview

```sh
swift design/render-menubar-preview.swift [output.png]
```

It needs only AppKit. Each glyph is rasterized at the pixel size a menu bar of that scale would draw (height in points × scale), tinted black on the light bar and white on the dark bar like a template image, and copied into the sheet without resampling, so one sheet pixel is one screen pixel. The column marked "native" is the drawing's own height; the other columns scale it, so they show a size the menu bar does not draw. The candidates are listed in the script's `candidates` array, in the order they appear on the sheet, each with its native height.
