# Piccolo

Piccolo is a macOS menu bar app that moves, resizes and arranges windows with global keyboard shortcuts. MIT licensed.

The repository is private during development and will be made public by the owner. Write every commit, issue and PR as if it were already public: English, no secrets, no personal paths.

## Product scope

1. Menu bar app, no Dock icon, launches at login.
2. Every action can be bound to any regular global shortcut (modifiers + key), recorded in Settings.
3. Place the focused window at a target frame: built-in presets (halves, thirds, quarters, center, maximize, ...) and user-defined rectangles expressed as fractions of the screen's visible frame.
4. Move the focused window to the next or previous display, keeping its relative frame.
5. Arrange the N most recently focused windows in a grid. Each shortcut is bound to one fixed combination (e.g. "last 4 in 2×2"). Candidates are windows on the current display and current Space; minimized and full-screen windows are excluded.
6. Linked resize: after Piccolo arranged windows side by side, stacked or in a grid, a shortcut moves a divider by a fixed step and the neighbouring windows follow, leaving no gaps or overlaps. Only groups created by Piccolo are linked. Groups are validated lazily: when a linked-resize shortcut fires and any member is no longer at its expected frame, the group is dissolved.

Non-goals: drag-to-snap with the mouse, automatic tiling of new windows, moving windows across Spaces, overriding system-reserved shortcuts, modifier-only shortcuts, Mac App Store distribution.

## Architecture

- Swift 6, SwiftUI + AppKit. Minimum macOS 14; raise it only when a dependency requires it. Not sandboxed (the Accessibility API rules it out), hardened runtime on.
- Bundle ID `io.damao.piccolo`.
- The root `Package.swift` holds everything testable:
  - `PiccoloCore`: pure logic (geometry, presets, grid and divider model, config schema). No AppKit side effects, no globals, fully unit tested.
  - `PiccoloSystem`: adapters for Accessibility, window enumeration, screens and hotkeys, behind protocols so that logic is testable with fakes.
  - `PiccoloControl`: request/response protocol, server and client of the debug control channel. Imports nothing from the other targets, so test support apps can host a server too.
  - `piccoloctl` (executable): command line client of the control channel plus read-only desktop queries (see "Debug control channel").
  - `PiccoloAcceptanceTests`: desktop acceptance tests, skipped unless `PICCOLO_ACCEPTANCE=1` (see "Desktop acceptance").
- `Piccolo.xcodeproj` holds thin targets only: the `Piccolo` app (UI and wiring, sources in `App/`) and the test support app `PiccoloFixture` (sources in `Fixture/`, see "Desktop acceptance"). It uses file-system-synchronized groups, so adding files does not touch the project file; a new target does, and the file is edited by hand. No project generators.
- Config and shortcuts: the config is `~/Library/Application Support/Piccolo/config.json` (hand-edited for now; a missing file means no bindings and the app never creates one). At launch, and on "Reload Config" in the menu, `ShortcutManager` (`PiccoloSystem`) loads it, resolves it with `ShortcutPlan` and registers the shortcuts as Carbon hotkeys through `HotkeyRegistrar` (the Carbon calls sit behind `HotkeyBackend`, so the replace and failure logic is unit tested with a fake). A hotkey runs its action through `ActionExecutor` on a serial queue, never on the main thread; failures are logged. Load issues, plan issues and shortcuts the system refused are logged and listed in `config.status`.
- One canonical coordinate space inside `PiccoloCore`: global display coordinates with a top-left origin and y pointing down, as used by the Accessibility and CGWindow APIs. Convert from AppKit's bottom-left space only at the `PiccoloSystem` boundary.

## Build, sign, run

- `swift test` runs the package's unit tests.
- `scripts/build.sh [debug|release]` builds `build/Piccolo.app` with xcodebuild. A Debug build also builds `build/PiccoloFixture.app`; a Release build (and so `release.sh`) never builds or ships the fixture.
- `scripts/install.sh [debug|release]` (default `release`) builds, replaces `/Applications/Piccolo.app` and relaunches it. Only a Debug build hosts the control server.
- `scripts/accept.sh [filter]` runs the desktop acceptance tests (see "Desktop acceptance").
- `scripts/release.sh [--skip-notarize]` builds a Developer ID signed release (hardened runtime, secure timestamp, no `get-task-allow`), notarizes it, staples the ticket and writes `build/release/Piccolo-<version>.zip`. It refuses without the signing identity, and without the notary settings unless `--skip-notarize`.
- Signing and notarization settings are never committed. Scripts source `${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env` when it exists (`PICCOLO_CODESIGN_IDENTITY`, `PICCOLO_TEAM_ID`, `PICCOLO_NOTARY_*`) and fall back to ad-hoc signing otherwise. `PICCOLO_SIGNING_ENV` overrides the file's path.
- The Accessibility grant is tied to the bundle ID and the signing identity. Only builds signed with the configured identity may be installed to `/Applications/Piccolo.app`; `scripts/install.sh` refuses ad-hoc builds. Never reset or edit TCC (`tccutil`, the TCC database).

## Debug control channel

Debug builds of Piccolo host a control server (`io.damao.piccolo.control`, a same-user `CFMessagePort`; no network socket) so that scripts and tests can query the app and trigger actions without keyboard input. This is the basis of automated desktop acceptance.

- Requests are `{"command": String, "params": Object}`, responses `{"ok": Bool, "result": Any?, "error": String?}`. Commands: `status`, `window.focusedFrame`, `window.setFocusedFrame`, `action.run`, `displays`, `config.status`, `config.load`, `config.reload`, `hotkey.simulate`.
- `action.run` runs an `Action` on the focused window. The params are the action exactly as the config file writes it, for example `{"type": "placeWindow", "frame": {"preset": "leftHalf"}}` or `{"type": "moveToDisplay", "direction": "next"}`. The result is `{"target": {x, y, width, height}, "achieved": {…}}` (what was asked for, and the frame read back, which differs when the window refused the size or was shifted back inside its display) or `{"nothingToDo": true}`. Malformed params, an invalid action (a custom frame off the screen), an action that is not implemented yet (`arrangeGrid`, `moveDivider`) and window errors answer `ok: false` with a message. The logic is `ActionExecutor` in `PiccoloSystem` (planning in `PiccoloCore/Actions`); the app only registers the command.
- `displays` answers `[{frame, visibleFrame}]`, the displays as the app sees them in canonical coordinates, the primary first. `config.status` answers `{path, bindingCount, registered: [{id, keyCode, modifiers}], issues: [String]}`. `config.load {path}` loads and applies another file instead of the default one, for this run only, and answers the same; nothing is written to the default location. `config.reload` loads the default location again. `hotkey.simulate {id}` presses the shortcut of a registered binding with real keyboard events (posted at the HID tap) and answers `{posted, fired}` once the hotkey has fired, not when its action has finished; an unregistered binding, or `CGPreflightPostEventAccess()` being false, answers `ok: false` (the command never asks for the permission). The key events must come from a `CGEventSource(stateID: .privateState)`: events from the HID system state reach the system but never fire a registered hotkey.
- `window.setFocusedFrame` and every action apply a frame with `FrameSetter.apply`: size, position, size, read back. A window whose size is not settable (fixed-size) still moves to the target's origin. Actions pass the target display's visible frame, and a window that ends up sticking out of it (it refused the size) is shifted left and up until it lies inside, never past the top-left corner. `window.setFocusedFrame` knows no display and does not shift.
- `swift run piccoloctl app <command> [--params '<json>']` sends a command (`--service <name>` picks another server, `--timeout <seconds>` raises the 5 s default). `piccoloctl fixture <command>` is the same aimed at the fixture app's server (`io.damao.piccolo.fixture.control`). `piccoloctl windows`, `screens` and `frontmost` read the desktop directly. All output is one line of JSON on stdout; exit code 0 only on success. Frames are in canonical coordinates.
- Release builds contain no control code: the server is under `#if DEBUG`, and `Piccolo.xcodeproj` links `PiccoloControl` into the `Piccolo` app in Debug only (a build-only target dependency plus `OTHER_LDFLAGS` for Debug). Do not add `PiccoloControl` to the app's linked frameworks, and check that `strings` on a Release binary finds no `PiccoloControl`. The `PiccoloFixture` target links it the normal way; it is never part of a release.
- Handlers run on the server's own queue, not on the main thread. Accessibility calls have a 2 s messaging timeout.
- App names are localized: match on `bundleID` (`com.apple.finder`), not on `name`.

## Desktop acceptance

Every feature that moves or resizes real windows ships with acceptance tests that the implementer runs before opening the PR. The tests drive the installed Debug Piccolo and the fixture app, and assert on frames measured in the window server.

- Run it: `scripts/accept.sh [filter]`. It takes the machine-wide lock (waits up to `PICCOLO_ACCEPT_LOCK_TIMEOUT` seconds, default 600, then exits 75 with "locked"), runs `scripts/install.sh debug` (so a signing identity is required and the Accessibility grant is kept), launches the fixture, runs `PICCOLO_ACCEPTANCE=1 swift test --filter PiccoloAcceptanceTests` and prints a one-line `accept: PASS|FAIL` summary. The exit code is the test result; the full test log is `build/accept-test.log`. `filter` is a regular expression matched against the Swift test function names (`scripts/accept.sh setFocusedFrame`). Teardown (close fixture windows, quit the fixture, release the lock) always runs, also on failure, Ctrl-C and SIGTERM. The Debug Piccolo stays installed afterwards. Plain `swift test` skips these tests.
- The fixture is `PiccoloFixture` (`io.damao.piccolo.fixture`, regular app, Debug only, sources in `Fixture/`), built to `build/PiccoloFixture.app`. Its control server `io.damao.piccolo.fixture.control` answers `open {id, frame, minSize?, maxSize?, resizeIncrements?, resizable?}`, `focus {id}`, `list`, `close {id}`, `closeAll` and `quit`; try them with `piccoloctl fixture <command> --params '<json>'`. Frames are canonical and include the title bar. A command answers only after its window operation has taken effect. Windows have no open or close animation, which would make frames read slightly off for a moment. `NSWindow.resizeIncrements` alone makes AppKit snap Accessibility resizes to the nearest multiple; `minSize` clamps them; `resizable: false` makes `AXSize` refuse.
- Add a test: write another `@Test` in the `Desktop acceptance` suite (`Tests/PiccoloAcceptanceTests/`). A group of tests in its own file is a suite nested in it (`extension DesktopAcceptanceTests { @Suite struct ... }`), which inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch; acceptance tests must never run at the same time. A test whose numbers depend on the displays derives them from `Layout.screens()` (the displays as the app reports them with `displays`) and skips with `try Test.cancel("reason")` when this machine cannot hold them. Wrap the body in `withFixture`, open windows with `fixture.open`, bring one forward with `Focus.bring`, act through `PiccoloClient`, then assert on `Measure.waitForFrame` (CGWindowList by window number, 1 pt tolerance) and not on the response alone. Never sleep for a fixed time: use `eventually` and make the failure message say what was expected and what was measured. Take test frames from `Layout.screens()` rather than hard-coding coordinates. Identify apps by bundle ID or pid, never by name.
- Tests that register hotkeys (`ConfigHotkeyTests.swift`) write a config into a temporary directory and apply it with `config.load` inside `withConfigDirectory`, which always ends with `config.reload`, checks that Piccolo is back on the default config and that the default config folder is unchanged. They use only control + option + shift + command with F13 to F19 (`TestShortcut`): the hotkeys are live system-wide while a test runs.
- Focus must be verified, never assumed. Since macOS 14 an app cannot always activate itself: a plain `focus` request fails while another app is frontmost. `Focus.bring` therefore hands the fixture to LaunchServices (`open`) first, repeats until it observes the fixture as frontmost (via `lsappinfo`; `NSWorkspace.frontmostApplication` goes stale in a process without an app run loop), the window as key, and Piccolo's own `window.focusedFrame` agreeing, and fails with all three observations otherwise. If it reports `frontmost app is com.apple.loginwindow`, the screen is locked (it locks after the idle time set in the screen saver settings, and an unattended machine stays locked): no focus-dependent test can pass until the owner unlocks it, and nothing in the repository can fix that.
- A frame measured right after a command can still show the previous state, so always poll. Do not post input events from a test or a shell (the one place that posts them is Piccolo itself, in `hotkey.simulate`), take screenshots or script other apps: any of these can raise a permission prompt nobody is there to click.
- `NSScreen.visibleFrame` is only accurate to 1 pt. The Dock and the menu bar can be half a point thick at 2x, the window server enforces the real size, and a command line process can see a different value than the app does. A window that spans the full width or touches the top can therefore come back 1 pt smaller than its target. Never assert exact equality with a display's visible frame: compare with the 1 pt tolerance. Feature code stores the achieved frame, not the target, whenever it needs to recognise a window later.

## Workflow

Roles: the owner files issues and decides when to open-source. The orchestrator (Claude, main session) plans, writes specs, dispatches, reviews, verifies, merges and releases; it does not write implementation code. Implementers (subagents on smaller models) write the code.

- Milestones M0–M5 are GitHub milestones. Every unit of work is an issue whose body is the spec: Goal, Context, Scope, Out of scope, Acceptance (commands wherever possible).
- One issue, one branch `<issue-number>-<slug>`, one PR containing `Closes #N`. Squash merge.
- Never rebase or force-push a PR branch. If `main` has moved, leave the branch alone; when it must be updated, merge `main` into it.
- The implementer runs every acceptance command before opening the PR. The orchestrator re-runs them on the PR branch, spot-checks the key diffs and records the verdict as a PR comment. High-risk PRs also get a read-only review by a non-Claude model.
- Rework goes back to the same implementer with written feedback.
- Each PR carries a delivery record (see the PR template), filled in by the orchestrator at merge: implementer model, rework rounds, dispatch-to-merge time, defects found in review and in acceptance.
- Desktop acceptance (anything that moves real windows or installs the app) is a machine-wide shared resource: one run at a time. `scripts/accept.sh` enforces this with a lock; run it, rather than the pieces, for anything that touches the desktop.

## Rules for implementers

- The issue is the spec. Do not expand its scope. If the spec is wrong or you are blocked, stop and report instead of improvising.
- Keep logic in `PiccoloCore` and write the tests for the specified behaviour before the implementation.
- Paste the acceptance results into the PR body, including anything that failed.
- Never commit signing identities, key locations or machine-specific paths. Never read or print notarization key files.
- Do not add third-party dependencies or install tools unless the issue says so.
- Comments and docs in English. Conventional Commits.
