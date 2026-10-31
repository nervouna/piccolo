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
| Applying frames, animation, linked resize, column-first grids, cycling and Restore Window, the failure notice, onboarding, the Settings window, the language setting and restart | [docs/features.md](docs/features.md) |
| Any interface text | [docs/localization.md](docs/localization.md) |
| The debug control channel, `piccoloctl` | [docs/control-channel.md](docs/control-channel.md) |
| Acceptance tests, the fixture, focus and restart problems | [docs/acceptance.md](docs/acceptance.md) |
| Signing, notarization, releases | [docs/releasing.md](docs/releasing.md) |
| The app icon or the menu bar glyph | [design/README.md](design/README.md) |
| What the user sees (actions, defaults, config keys) | [README.md](README.md) |

## Build, sign, run

- `swift test` runs the package's unit tests.
- `scripts/build.sh [debug|release]` builds `build/Piccolo.app` with xcodebuild. A Debug build also builds `build/PiccoloFixture.app`; a Release build (and so `release.sh`) never builds or ships the fixture.
- `scripts/install.sh [debug|release]` (default `release`) builds, replaces `/Applications/Piccolo.app` and relaunches it. Only a Debug build hosts the control server.
- `scripts/accept.sh [filter]` runs the desktop acceptance tests (see "Workflow" below and [docs/acceptance.md](docs/acceptance.md)).
- `scripts/release.sh [--skip-notarize]` builds a notarized release archive ([docs/releasing.md](docs/releasing.md)).
- `swift run piccoloctl app <command> [--params '<json>']` drives a running Debug Piccolo; `piccoloctl fixture <command>` the fixture.
- Signing and notarization settings are never committed. Scripts source `${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env` when it exists and fall back to ad-hoc signing otherwise.
- The Accessibility grant is tied to the bundle ID and the signing identity. Only builds signed with the configured identity may be installed to `/Applications/Piccolo.app`; `scripts/install.sh` refuses ad-hoc builds. Never reset or edit TCC (`tccutil`, the TCC database).
- Release builds contain no control code: the server is under `#if DEBUG`, and `PiccoloControl` is linked into the app in Debug only. Do not add `PiccoloControl` to the app's linked frameworks.

## Workflow

Developed with the global `orchestrate` skill: the owner files issues and makes product decisions; Claude writes each issue as a spec, Claude subagents implement it as a PR, Claude reviews, merges and releases. Milestones are GitHub milestones, each with a tracking issue. Piccolo's own rules:

- Desktop acceptance (anything that moves real windows or installs the app) is a machine-wide shared resource: one run at a time. Run `scripts/accept.sh`, not its pieces: it holds the lock and always tears down.
- Acceptance scope: a run covers what the change can break, not the whole suite by default. A full run takes the screen for over two minutes, so it is reserved for changes that can affect every test. `scripts/accept.sh` takes a regular expression matched against the test identifiers, so a suite's struct name selects it; the script prefixes it with `PiccoloAcceptanceTests.*`, so an alternation goes in parentheses, or its later branches also match unit tests of the same name. A change that touches several rows runs the union of their filters (`scripts/accept.sh '(SettingsWindow|SettingsInFront|WindowGap)'`).

  | Change touches | Filter |
  |---|---|
  | Frames and actions: `PiccoloCore/Geometry`, `Actions`, `Layout`, `LinkedResize`, `Arrange`, `Animation`, `History`; `ActionExecutor`, `FrameSetter`, `ArrangeExecution`, `LinkedResizeExecution`, `SwapExecution`, `WindowRecordStore`, `App/DebugArrangeCommands.swift`, `PiccoloSystem/Animation` | `(SingleWindowActions\|ArrangeGrid\|ColumnFirst\|LinkedResize\|SwapWindow\|CycleRestore\|WindowGap\|WindowAnimationAcceptance)` |
  | Edge bounce only: `PiccoloCore/Animation/EdgeBounce.swift` (narrower than the frames row's `Animation`) | `(SwapWindow\|WindowAnimationAcceptance)` |
  | Shortcuts and holding them: `PiccoloCore/Shortcuts`, `PiccoloSystem/Hotkeys`, `PiccoloSystem/Preview`, `PiccoloSystem/Destinations`, `App/ConfigController.swift` | `(ConfigHotkeys\|DestinationPreviewAcceptance\|FailureNoticeAcceptance\|OnboardingAcceptance)` |
  | Config schema and settings: `PiccoloCore/Config`, `ActionSettings` | `(ConfigHotkeys\|SettingsWindow)`, plus the frames row when an action reads the new setting |
  | Settings window: `PiccoloUI/Model`, `Views`, `Window/SettingsWindowController.swift`, `Window/SettingsContentController.swift`, `Window/SettingsWindowSizing.swift`, `Text/SettingsTabText.swift`, `App/SettingsController.swift`, `App/DebugSettingsCommands.swift`, `App/DebugSettingsWindowState.swift` | `(SettingsWindow\|SettingsInFront\|SettingsWindowChrome)` |
  | Failure notice: `Notice`, `NoticePanel`, `FailureNoticeText`, `FailureNotice+System.swift`, `App/NoticeController.swift` | `FailureNoticeAcceptance` |
  | Onboarding: `PiccoloUI/Onboarding`, `App/OnboardingController.swift` | `OnboardingAcceptance` |
  | Language and restart: `AppLanguage`, `LanguageDefaults`, `App/AppRestart.swift` | `Language` |
  | Login item: `LoginItem` | `LaunchAtLogin` |
  | Texts only (a catalog, `ActionSummary`, `ShortcutText`) | none: `swift test` (`CatalogTests`) covers them |
  | Documentation only | none |

  A full run (no filter) is for changes that every test depends on: `App/AppDelegate.swift`, `App/DebugControlServer.swift`, `PiccoloControl`, `Fixture/`, the shared acceptance helpers (`Tests/PiccoloAcceptanceTests/` files that are not a suite of their own), `FocusTracker`, `FocusedWindow`, `WindowCatalog`, `OnScreenWindows`, `Screens`, `AccessibilityWindow*`, `scripts/`, `Package.swift` and `Piccolo.xcodeproj`. A file that is in no row counts as a full run until the table names it; add it to the table in the same PR. A new suite adds its struct name to its row.
- Who runs what. The implementer iterates with the filter of the suite they are writing, and before opening the PR runs the filter of every row the change touches once (a full run only when the table says so), and puts the `accept:` line and the filter in the PR. The reviewer does not re-run a run whose result cannot differ: when the PR head is the commit the implementer ran and `main` has not moved, the reviewer reads `build/accept-test.log` in the implementer's worktree (the filter, the test list, the summary) and the commit it was built from instead. The reviewer runs acceptance on the merged result only after merging `main` into the PR or after a rework, and then only the rows that the merge or the rework touches.
- Release gate, pre-releases: [docs/releasing.md](docs/releasing.md). Reviewer UI captures and focus failures during a run: [docs/acceptance.md](docs/acceptance.md).
- Parallel PRs that add catalog keys conflict in `Localizable.xcstrings` as adjacent insertions: keep both entries in key order, then check that the file parses as JSON and the key count is the sum.

## Rules for implementers

- Keep logic in `PiccoloCore` and write the tests for the specified behaviour before the implementation.
- Never commit signing identities, key locations or machine-specific paths. Never read or print notarization key files.
- Do not add third-party dependencies or install tools unless the issue says so.
- Comments and docs in English. Conventional Commits.
