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
- `Piccolo.xcodeproj` holds thin targets only: the `Piccolo` app (UI and wiring) and test support apps. It uses file-system-synchronized groups, so adding files does not touch the project file. No project generators.
- One canonical coordinate space inside `PiccoloCore`: global display coordinates with a top-left origin and y pointing down, as used by the Accessibility and CGWindow APIs. Convert from AppKit's bottom-left space only at the `PiccoloSystem` boundary.

## Build, sign, run

- `swift test` runs the package's unit tests.
- `scripts/build.sh [debug|release]` builds `build/Piccolo.app` with xcodebuild.
- `scripts/install.sh` builds, replaces `/Applications/Piccolo.app` and relaunches it.
- Signing and notarization settings are never committed. Scripts source `${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env` when it exists (`PICCOLO_CODESIGN_IDENTITY`, `PICCOLO_TEAM_ID`, `PICCOLO_NOTARY_*`) and fall back to ad-hoc signing otherwise. `PICCOLO_SIGNING_ENV` overrides the file's path.
- The Accessibility grant is tied to the bundle ID and the signing identity. Only builds signed with the configured identity may be installed to `/Applications/Piccolo.app`; `scripts/install.sh` refuses ad-hoc builds. Never reset or edit TCC (`tccutil`, the TCC database).

## Workflow

Roles: the owner files issues and decides when to open-source. The orchestrator (Claude, main session) plans, writes specs, dispatches, reviews, verifies, merges and releases; it does not write implementation code. Implementers (subagents on smaller models) write the code.

- Milestones M0–M5 are GitHub milestones. Every unit of work is an issue whose body is the spec: Goal, Context, Scope, Out of scope, Acceptance (commands wherever possible).
- One issue, one branch `<issue-number>-<slug>`, one PR containing `Closes #N`. Squash merge.
- The implementer runs every acceptance command before opening the PR. The orchestrator re-runs them on the PR branch, spot-checks the key diffs and records the verdict as a PR comment. High-risk PRs also get a read-only review by a non-Claude model.
- Rework goes back to the same implementer with written feedback.
- Each PR carries a delivery record (see the PR template), filled in by the orchestrator at merge: implementer model, rework rounds, dispatch-to-merge time, defects found in review and in acceptance.
- Desktop acceptance (anything that moves real windows or installs the app) is a machine-wide shared resource: one run at a time.

## Rules for implementers

- The issue is the spec. Do not expand its scope. If the spec is wrong or you are blocked, stop and report instead of improvising.
- Keep logic in `PiccoloCore` and write the tests for the specified behaviour before the implementation.
- Paste the acceptance results into the PR body, including anything that failed.
- Never commit signing identities, key locations or machine-specific paths. Never read or print notarization key files.
- Do not add third-party dependencies or install tools unless the issue says so.
- Comments and docs in English. Conventional Commits.
