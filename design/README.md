# Design files

| File | What it is |
|---|---|
| `icon.png` | Source artwork of the app icon, 1024×1024. `scripts/make-icon.sh` turns it into `App/Assets.xcassets/AppIcon.appiconset` (see "App icon" in `CLAUDE.md`). |
| `menubar-icon.svg` | Menu bar glyph, candidate 1 (filled panes). This is the one the app ships as `MenuBarIcon`. |
| `menubar-icon-latte.svg` | Menu bar glyph, candidate 1b (latte: candidate 1 with the top pane left empty). Not used by the app. |
| `menubar-icon-outline.svg` | Menu bar glyph, candidate 2 (outline). Same silhouette and grid, not used by the app. |
| `menubar-preview.png` | All three candidates at 16, 18 and 22 pt, at 1x and 2x, on a light and a dark menu bar, plus a magnified view of the 1x pixels. |
| `render-menubar-preview.swift` | Script that renders `menubar-preview.png` from the three SVGs. |

## The menu bar glyph

The glyph is the app icon's glass reduced to one colour: a tapered tumbler split by gutters into a wide top pane and, below it, a larger left pane and a narrower right pane. All three drawings are 19 × 18 pt, black on transparent, one SVG unit per point, with no colour, shadow or gradient. Every line and gap is 1 pt, and the horizontal and vertical edges sit on whole points, so those lines are crisp at 1x on an 18 pt tall menu bar item and only the leaning sides are anti-aliased. The sides lean in by 1 pt over the height and the bottom corners are rounder than the top ones, as on the app icon.

- Candidate 1 (`menubar-icon.svg`): a 1 pt outline, a 1 pt transparent gap, then three solid panes separated by 1 pt transparent gutters.
- Candidate 1b (`menubar-icon-latte.svg`): candidate 1 with the top pane removed, so the top is empty like the outline candidate's and the two bottom panes stay solid. Its geometry is otherwise identical to candidate 1's; the top pane path is the only difference.
- Candidate 2 (`menubar-icon-outline.svg`): the same outline with the two gutters drawn as 1 pt lines and the panes left empty.

At 16 pt (the drawing scaled by 8/9) a 1 pt line is 0.89 px wide and falls between pixels at 1x, so the gutters get softer but stay visible. The shipping size is 18 pt.

## How `MenuBarIcon` is made

`App/Assets.xcassets/MenuBarIcon.imageset/` holds a copy of `menubar-icon.svg` and a `Contents.json` that asks for the vector data to be preserved and for the template rendering intent:

```json
"properties" : {
  "preserves-vector-representation" : true,
  "template-rendering-intent" : "template"
}
```

The system tints a template image for light, dark and highlighted menu bars, so the SVG stays black on transparent. `App/PiccoloApp.swift` uses it as `MenuBarExtra("Piccolo", image: "MenuBarIcon")`; the title is the accessibility label.

To change the glyph, edit `design/menubar-icon.svg`, copy it over the file in the image set (keep the file name `menubar-icon.svg`, `Contents.json` refers to it) and render the preview again. To ship the latte or the outline candidate instead, copy `menubar-icon-latte.svg` or `menubar-icon-outline.svg` over the image set's `menubar-icon.svg`. Check the result with `scripts/build.sh release` and:

```sh
xcrun --sdk macosx assetutil --info build/Piccolo.app/Contents/Resources/Assets.car | grep -B10 -A3 '"Template Mode"'
```

which lists `MenuBarIcon` at 1x and 2x with `"Template Mode" : "template"` and `"Preserved Vector Representation" : true`.

## Rendering the preview

```sh
swift design/render-menubar-preview.swift [output.png]
```

It needs only AppKit. Each glyph is rasterized at the pixel size a menu bar of that scale would draw (height in points × scale), tinted black on the light bar and white on the dark bar like a template image, and copied into the sheet without resampling, so one sheet pixel is one screen pixel. The candidates are listed in the script's `candidates` array, in the order they appear on the sheet.
