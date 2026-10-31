# Piccolo

Piccolo is a macOS menu bar app that moves, resizes and arranges windows with global keyboard shortcuts. MIT licensed.

The repository is public. Write every commit, issue and PR in English, with no secrets and no personal paths.

## Product scope

1. Menu bar app, no Dock icon, launches at login.
2. Every action can be bound to a global shortcut recorded in Settings: a key together with at least one of command, option or control, or a function key on its own. Shift alone does not make a shortcut, so a hand-edited config can never take over a plain key.
3. Place the focused window at a target frame: built-in presets (halves, thirds, quarters, center, maximize, ...) and user-defined rectangles expressed as fractions of the screen's visible frame. Pressing Left, Right, Top or Bottom Half again cycles the window through 1/2, 2/3 and 1/3 of the display. A Restore Window action puts a window back where it was before Piccolo moved it (one level, in memory, for windows Piccolo moved only).
4. Move the focused window to the next or previous display, or to the display to its left, right, above or below, keeping its relative frame.
5. Arrange the N most recently focused windows in a grid. Each shortcut is bound to one fixed combination (e.g. "last 4 in 2×2"). Candidates are windows on the current display and current Space; minimized and full-screen windows are excluded.
6. Linked resize: after Piccolo arranged windows side by side, stacked or in a grid, a shortcut moves a divider by a fixed step and the neighbouring windows follow, leaving no gaps or overlaps. Only groups created by Piccolo are linked. Groups are validated lazily: when a linked-resize shortcut fires and any member is no longer at its expected frame, the group is dissolved. Swap Window works on the same groups: it exchanges the focused window with its neighbour on the side of the key, the two windows trade cells, and the layout and the group stay.

Non-goals: drag-to-snap with the mouse, automatic tiling of new windows, moving windows across Spaces, overriding system-reserved shortcuts, modifier-only shortcuts, Mac App Store distribution.

## Architecture

- Swift 6, SwiftUI + AppKit. Minimum macOS 14; raise it only when a dependency requires it. Not sandboxed (the Accessibility API rules it out), hardened runtime on. Bundle ID `io.damao.piccolo`.
- The root `Package.swift` holds everything testable:
  - `PiccoloCore`: pure logic (geometry, presets, grid and divider model, config schema, hold rules, cycling and window records). No AppKit side effects, no globals, fully unit tested.
  - `PiccoloSystem`: adapters for Accessibility, window enumeration, screens, hotkeys, the login item (`LoginItem`, over `SMAppService.mainApp`), the preview highlight and animation, behind protocols so that logic is testable with fakes. `ActionExecutor` runs actions. The window catalog joins CGWindowList (order, window numbers) with Accessibility through `_AXUIElementGetWindow`, a private but long-stable API declared in one place (`WindowNumber.swift`). The focus tracker keeps a `FocusHistory`; `AppDelegate` starts it at launch so that the first arrangement already has a history.
  - `PiccoloControl`: request/response protocol, server and client of the debug control channel. Imports nothing from the other targets, so test support apps can host a server too.
  - `PiccoloUI`: the Settings window, the onboarding guide, the failure notice panel and every localized text. `SettingsModel` (`@MainActor`, `@Observable`) validates every edit, then persists it through a `SettingsBackend` before it shows. Depends on `PiccoloCore` only; the app plugs in the backends, so the model is unit tested against ones in memory.
  - `piccoloctl` (executable): command line client of the control channel plus read-only desktop queries.
  - `PiccoloAcceptanceTests`: desktop acceptance tests, skipped unless `PICCOLO_ACCEPTANCE=1`.
- `Piccolo.xcodeproj` holds thin targets only: the `Piccolo` app (UI and wiring, sources in `App/`) and the test support app `PiccoloFixture` (sources in `Fixture/`). It uses file-system-synchronized groups, so adding files does not touch the project file; a new target does, and the file is edited by hand. No project generators. A new package product the app uses (`PiccoloCore`, `PiccoloSystem`, `PiccoloUI`) is linked the same way each time: a `PBXBuildFile` in the app's Frameworks phase, an entry in its `packageProductDependencies` and an `XCSwiftPackageProductDependency`.
- One canonical coordinate space inside `PiccoloCore`: global display coordinates with a top-left origin and y pointing down, as used by the Accessibility and CGWindow APIs. Convert from AppKit's bottom-left space only at the `PiccoloSystem` boundary.
- Hotkey actions run through `ActionExecutor` on a serial queue, never on the main thread. Piccolo never acts on its own windows (`WindowError.ownWindow`), and enumerations of windows leave them out.
- Piccolo's panels over other apps (highlight, notice, onboarding guide) must never activate Piccolo or take the focus: a Piccolo that has been the active application stops firing simulated hotkeys.
- Interface texts live in two hand-written String Catalogs and ship in eight languages; `CatalogTests` enforces the lookup rules. Read [docs/localization.md](docs/localization.md) before adding or changing a text.

## Read before you change

| When the change touches | Read |
|---|---|
| The config file, `ActionSettings`, the window gap, default shortcuts | [docs/config.md](docs/config.md) |
| Hotkeys, holding a shortcut, the destination preview, overlay panels | [docs/shortcuts-and-preview.md](docs/shortcuts-and-preview.md) |
| Applying frames, animation, the edge bounce | [docs/features.md › Applying frames and animation](docs/features.md#applying-frames-and-animation) |
| Linked resize, Swap Window, column-first grids | [docs/features.md › Linked resize](docs/features.md#linked-resize-swap-window-and-column-first-grids) |
| Cycling halves, Restore Window, the window records | [docs/features.md › Cycling](docs/features.md#cycling-restore-window-and-the-window-records) |
| The failure notice | [docs/features.md › Failure notice](docs/features.md#failure-notice) |
| Onboarding | [docs/features.md › Onboarding guide](docs/features.md#onboarding-guide) |
| The Settings window | [docs/features.md › Settings window](docs/features.md#settings-window) |
| The language setting and restart | [docs/features.md › Language](docs/features.md#language-setting-and-restart) |
| Any interface text, a merge conflict in a String Catalog | [docs/localization.md](docs/localization.md) |
| The debug control channel, `piccoloctl` | [docs/control-channel.md](docs/control-channel.md) |
| Choosing an acceptance filter, opening or reviewing a PR, acceptance tests, the fixture, focus and restart problems, UI captures | [docs/acceptance.md](docs/acceptance.md) |
| Signing, notarization, releases | [docs/releasing.md](docs/releasing.md) |
| The app icon or the menu bar glyph | [design/README.md](design/README.md) |
| What the user sees (actions, defaults, config keys) | [README.md](README.md) |

## Build, sign, run

- `swift test` runs the package's unit tests.
- `swift test --filter <regex>` matches type and function names (`followsTheModel`), not the `@Test("…")` display string.
- `scripts/build.sh [debug|release]` builds `build/Piccolo.app` with xcodebuild. A Debug build also builds `build/PiccoloFixture.app`; a Release build (and so `release.sh`) never builds or ships the fixture.
- `scripts/install.sh [debug|release]` (default `release`) builds, replaces `/Applications/Piccolo.app` and relaunches it. Only a Debug build hosts the control server.
- `scripts/accept.sh [filter]` runs the desktop acceptance tests ([docs/acceptance.md](docs/acceptance.md)).
- `scripts/release.sh [--skip-notarize]` builds a notarized release archive ([docs/releasing.md](docs/releasing.md)).
- `swift run piccoloctl app <command> [--params '<json>']` drives a running Debug Piccolo; `piccoloctl fixture <command>` the fixture.
- Signing and notarization settings are never committed. Scripts source `${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env` when it exists and fall back to ad-hoc signing otherwise.
- The Accessibility grant is tied to the bundle ID and the signing identity. Only builds signed with the configured identity may be installed to `/Applications/Piccolo.app`; `scripts/install.sh` refuses ad-hoc builds. Never reset or edit TCC (`tccutil`, the TCC database).
- Release builds contain no control code: the server is under `#if DEBUG`, and `PiccoloControl` is linked into the app in Debug only. Do not add `PiccoloControl` to the app's linked frameworks.

## Workflow

Developed with the global `orchestrate` skill. Piccolo's own rules:

- Desktop acceptance (anything that moves real windows or installs the app) is a machine-wide shared resource: one run at a time, always through `scripts/accept.sh`, which holds the lock and always tears down. A run covers what the change can break, not the whole suite: the filter for each kind of change, who runs what, and the reinstall at the end of a session are in [docs/acceptance.md › Scope](docs/acceptance.md#scope). Read it before opening or reviewing a PR.

## Rules for implementers

- Keep logic in `PiccoloCore` and write the tests for the specified behaviour before the implementation.
- Never commit signing identities, key locations or machine-specific paths. Never read or print notarization key files.
- Do not add third-party dependencies or install tools unless the issue says so.
- Unit tests that wait for AppKit or SwiftUI (a window's frame, a render, a reported height) wait for the condition in polls that actually ran, with a wall-clock limit only against hangs: a full `swift test` blocks the main actor for 10 s and more at a time, so a deadline in seconds runs out before the window had its turn (#113, #114). A bitmap comparison renders a window ordered front invisibly (`alphaValue = 0`, `ignoresMouseEvents`).
- Off-screen render tests miss some of what a real window draws (a custom fill under a borderless menu, a SwiftUI `Grid` squeezing flexible text to nothing): use the system's control styles over painted backgrounds, and leave every visual change to the reviewer's capture of the real window.
- Comments and docs in English. Conventional Commits.
