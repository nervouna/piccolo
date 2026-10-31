# Desktop acceptance

Every feature that moves or resizes real windows ships with acceptance tests that the implementer runs before opening the PR. The tests drive the installed Debug Piccolo and the fixture app, and assert on frames measured in the window server. Plain `swift test` skips them.

## Scope

A run covers what the change can break, not the whole suite. A full run takes the screen for over two minutes, so it is reserved for changes that can affect every test.

`scripts/accept.sh [filter]` takes a regular expression matched against the test identifiers, so a suite's struct name or a test function name selects it. The script prefixes it with `PiccoloAcceptanceTests.*`, so an alternation goes in parentheses, or its later branches also match unit tests of the same name. A change that touches several rows runs the union of their filters (`scripts/accept.sh '(SettingsWindow|SettingsInFront|WindowGap)'`).

| Change touches | Filter |
|---|---|
| Frames and actions: `PiccoloCore/Geometry`, `Actions`, `Layout`, `LinkedResize`, `Arrange`, `Animation`, `History`; `ActionExecutor`, `FrameSetter`, `ArrangeExecution`, `LinkedResizeExecution`, `SwapExecution`, `WindowRecordStore`, `App/DebugArrangeCommands.swift`, `PiccoloSystem/Animation` | `(SingleWindowActions\|ArrangeGrid\|ColumnFirst\|LinkedResize\|SwapWindow\|CycleRestore\|WindowGap\|WindowAnimationAcceptance)` |
| Edge bounce only: `PiccoloCore/Animation/EdgeBounce.swift` (narrower than the frames row's `Animation`) | `(SwapWindow\|WindowAnimationAcceptance)` |
| Shortcuts and holding them: `PiccoloCore/Shortcuts`, `PiccoloSystem/Hotkeys`, `PiccoloSystem/Preview`, `PiccoloSystem/Destinations`, `App/ConfigController.swift` | `(ConfigHotkeys\|DestinationPreviewAcceptance\|FailureNoticeAcceptance\|OnboardingAcceptance)` |
| Config schema and settings: `PiccoloCore/Config`, `ActionSettings` | `(ConfigHotkeys\|SettingsWindow)`, plus the frames row when an action reads the new setting |
| Settings window: `PiccoloCore/Keymap`, `PiccoloUI/Model`, `Views`, `Text/ActionPreview.swift`, `Text/KeymapSectionTitle.swift`, `Window/SettingsWindowController.swift`, `Window/SettingsContentController.swift`, `Window/SettingsWindowSizing.swift`, `Window/SettingsUndoKey.swift`, `Text/SettingsTabText.swift`, `App/SettingsController.swift`, `App/DebugSettingsCommands.swift`, `App/DebugSettingsWindowState.swift`, `Text/LayoutEditorText.swift` | `(SettingsWindow\|SettingsWindowChrome\|SettingsInFront\|KeymapSettings\|SettingsUndo)` |
| Failure notice: `Notice`, `NoticePanel`, `FailureNoticeText`, `FailureNotice+System.swift`, `App/NoticeController.swift` | `FailureNoticeAcceptance` |
| Onboarding: `PiccoloUI/Onboarding`, `App/OnboardingController.swift` | `OnboardingAcceptance` |
| Language and restart: `AppLanguage`, `LanguageDefaults`, `App/AppRestart.swift` | `Language` |
| Login item: `LoginItem` | `LaunchAtLogin` |
| Texts only (a catalog, `ActionSummary`, `ShortcutText`) | none: `swift test` (`CatalogTests`) covers them |
| Documentation only | none |

A full run (no filter) is for changes that every test depends on: `App/AppDelegate.swift`, `App/DebugControlServer.swift`, `PiccoloControl`, `Fixture/`, the shared acceptance helpers (`Tests/PiccoloAcceptanceTests/` files that are not a suite of their own), `FocusTracker`, `FocusedWindow`, `WindowCatalog`, `OnScreenWindows`, `Screens`, `AccessibilityWindow*`, `scripts/`, `Package.swift` and `Piccolo.xcodeproj`. A file that is in no row counts as a full run until the table names it; add it to the table in the same PR. A new suite adds its struct name to its row.

Who runs what:

- The implementer iterates with the filter of the suite they are writing, and before opening the PR runs the filter of every row the change touches once (a full run only when the table says so), and puts the `accept:` line and the filter in the PR.
- The reviewer does not re-run a run whose result cannot differ: when the PR head is the commit the implementer ran and `main` has not moved, the reviewer reads `build/accept-test.log` in the implementer's worktree (the filter, the test list, the summary) and the commit it was built from instead. The reviewer runs acceptance on the merged result only after merging `main` into the PR or after a rework, and then only the rows that the merge or the rework touches.
- The release gate is in [releasing.md](releasing.md#release-gate-and-pre-releases).
- Desktop runs leave a Debug build in `/Applications`. When the owner uses Piccolo day to day, end the session with `scripts/install.sh release` under the acceptance lock, and check that `~/Library/Application Support/Piccolo/config.json` and the stored language are untouched.

## Running

- `scripts/accept.sh [filter]` takes the machine-wide lock (waits up to `PICCOLO_ACCEPT_LOCK_TIMEOUT` seconds, default 600, then exits 75 with "locked"), runs `scripts/install.sh debug` (so a signing identity is required and the Accessibility grant is kept), launches the fixture, runs the tests with `PICCOLO_ACCEPTANCE=1` and prints a one-line `accept: PASS|FAIL` summary. The exit code is the test result; the full log is `build/accept-test.log`.
- Teardown always runs, also on failure, Ctrl-C and SIGTERM: it hands Piccolo back to the config at the default location (`config.reload`), closes the fixture's windows, quits the fixture and releases the lock. The Debug Piccolo stays installed.
- Tests that are off in a normal run:
  - `PICCOLO_LOGIN_ITEM=1 scripts/accept.sh loginItem` registers and unregisters the login item. It shows a system notification and changes the machine's Login Items, so run it only as often as needed, and never enable the login item by other means.
  - `PICCOLO_STRESS=1 scripts/accept.sh restartStress` (30 restarts, every second one after bringing Settings forward), `restartStressAtOnce` (SIGTERM and launch in the same breath, so LaunchServices lists the old instance every time) and `restartNowStress` (through Restart Now). `PICCOLO_STRESS_COUNT` sets the number of rounds. They print how many launches had to wait for LaunchServices and how many failed.
- A focus assertion that finds another app's window focused (not the fixture's) usually means someone used the Mac during the run: re-run that suite before treating it as a regression.

## The fixture

`PiccoloFixture` (`io.damao.piccolo.fixture`, a regular app, Debug only, sources in `Fixture/`) is built to `build/PiccoloFixture.app`. Its control server `io.damao.piccolo.fixture.control` answers `open {id, frame, minSize?, maxSize?, resizeIncrements?, resizable?}`, `focus`, `miniaturize`, `deminiaturize`, `list` (with `isKey` and `isMiniaturized`), `keyEvents {id}` (the key codes the window received, oldest first; a key a global hotkey took never gets there), `close`, `closeAll` and `quit`. Try them with `piccoloctl fixture <command> --params '<json>'`.

- Frames are canonical and include the title bar. A command answers only after its window operation has taken effect. Windows have no open or close animation, which would make frames read slightly off for a moment.
- `resizeIncrements` alone makes AppKit snap Accessibility resizes to the nearest multiple; `minSize` clamps them; `resizable: false` makes `AXSize` refuse.

## Writing a test

- Write another `@Test` in the `Desktop acceptance` suite (`Tests/PiccoloAcceptanceTests/`). A group of tests in its own file is a suite nested in it (`extension DesktopAcceptanceTests { @Suite struct ... }`), which inherits `.serialized` and the `PICCOLO_ACCEPTANCE` switch: acceptance tests must never run at the same time.
- Wrap the body in `withFixture`, open windows with `fixture.open`, bring one forward with `Focus.bring`, act through `PiccoloClient`, then assert on `Measure.waitForFrame` (CGWindowList by window number, 1 pt tolerance), not on the response alone.
- Take frames from `Layout.screens()` (the displays as the app reports them), never hard-coded coordinates, and skip with `try Test.cancel("reason")` when this machine cannot hold them. Identify apps by bundle ID or pid, never by name.
- Never sleep for a fixed time: a frame measured right after a command can still show the previous state, so poll with `eventually`, and make the failure message say what was expected and what was measured.
- `NSScreen.visibleFrame` is only accurate to 1 pt (the Dock and the menu bar can be half a point thick at 2x, and a command line process can see a different value than the app). A window that spans the full width or touches the top can come back 1 pt smaller than its target, so never assert exact equality with a visible frame. Feature code stores the achieved frame, not the target, whenever it needs to recognise a window later.
- Do not post input events from a test or a shell (the one place that posts them is Piccolo itself, in `hotkey.simulate`), take screenshots or script other apps: any of these can raise a permission prompt nobody is there to click.

### Configs

- Every test starts from the fresh-install config: the bindings of `Config.defaultShortcuts` with the settings the frame tests are written for, which are not the defaults of a new install. A new install has a 16 pt gap, column-first grids and the Medium animation; the expected frames are computed from the visible frame with no gap and row-first grids, so the config has gap 0, row-first grids and the Fast animation (`FrameTestSettings` in `FreshInstallConfig.swift`; the resize step and the destination preview are the defaults). The config at the default location is the owner's own (a gap, column-first grids), and actions read the settings of the config in effect, so a test that ran on it would measure frames off. The root suite's trait `.piccoloRunning` (`PiccoloRunningTrait.swift`) therefore writes that config to a temporary directory (`FreshInstallConfig.swift`) and loads it with `config.load` before every test, then loads the default location again and removes the directory. The default location is never written, and a Settings edit made meanwhile changes the temporary file.
- A test that needs other settings or bindings loads its own config with `withConfigDirectory` (`withLinkedResize`, `withSettingsSession` and `withFixtureOnDefaultSettings` wrap it). The configs it writes state the same settings: `Config.frameTest(...)` is `Config(...)` with them, `ConfigDirectory.write(_:)` uses it, and `withLinkedResize` defaults `gap` to 0 and `animation` to Fast. A test that takes a default shortcut reads it from `Config.defaultShortcuts` (`Config.defaultShortcut(of:)`) instead of writing the keys down. It ends by loading the fresh-install config again, not by `config.reload`, which would go to the owner's config.
- A Piccolo restarted inside a test comes up on the config at the default location, so a test that restarts it loads the config it needs before it acts or edits.
- After a run, `piccoloctl app settings.state` answers the owner's own `gap` and `gridFillOrder`, and `shasum -a 256` of the file is what it was before.

### By area

- Hotkeys (`ConfigHotkeyTests.swift`): only ⌃⌥⇧⌘ with F13 to F19 (`TestShortcut`), because the hotkeys are live system-wide while a test runs.
- Destination preview (`DestinationPreviewTests.swift`): hold shortcuts with `hotkey.press`, `hotkey.release` and `hotkey.escape`. The held shortcut is always one whose action finds a fixture window focused, because the release runs it; no test releases an arrangement before `preview.state.windows` lists the fixture's windows only (otherwise it sends `hotkey.escape` and fails). Whatever a test leaves held is cancelled by the config load that ends `withConfigDirectory`. The checks include that the fixture stays frontmost and focused while the highlight is up.
- Settings (`SettingsWindowTests.swift` and the other Settings suites): run inside `withSettingsSession`, which loads a temporary config before anything is edited (Settings writes the file Piccolo has loaded) and afterwards cancels a recording, closes Settings and checks that no Piccolo window is left on screen. Piccolo's windows are found in `CGWindowList` by pid (`PiccoloWindows`). A window that animates to a tab's size is read until its frame stops changing.
- Login item (`LoginItemTests.swift`): the test that always runs only reads; the opt-in one restores the status in `withLoginItemRestored`, also when it fails.
- Texts: tests must pass whatever language Piccolo runs in (Simplified Chinese on the owner's Mac). A test never runs Piccolo in English and never compares with an English literal: it asks `InterfaceTexts` for the same text in `settings.state.effectiveLanguage`, from the same catalog and code. Control channel texts are not translated and may be compared as literals.
- Language (`LanguageTests.swift`): the only tests that change the choice, each inside `withLanguageRestored`, which stores the choice found at the start and restarts Piccolo if it no longer runs in its old language. They switch to `zh-Hans`, or to `en` when Piccolo already runs in Chinese, so that a restart is needed on any machine. After a run, `defaults read io.damao.piccolo AppleLanguages` says what it said before.
- A failure to put something back (language, login item, a restart after a failed test) is recorded as a second issue of the test, never swallowed with `try?`.

## Platform behaviour the harness depends on

- **A Piccolo that has been the active application stops firing `hotkey.simulate`.** The events are delivered, but the system no longer matches them against the process's hotkeys, whatever is in front afterwards and however the hotkeys are registered again (macOS 27; no variation of the posting changes it). Real key presses are not affected. Only a new process fires again, so a test that brings Piccolo forward ends by restarting it (`PiccoloProcess.restart`; `withSettingsSession` does so for every session that activated it), and a test that wants a hotkey to fire after typing into Settings restarts Piccolo first and loads its config again (`SettingsSession.restartPiccolo`). This is also why Piccolo's overlay panels never activate it.
- **Restarting has to cope with LaunchServices.** For a moment after a process died, `lsappinfo find bundleid=io.damao.piccolo` still lists its instance, and an `open` then goes to the dead instance: it fails with -600 (sometimes -609) and usually leaves the window server waiting for that instance (17 of 21 such failures). `lsappinfo front` then reports `com.apple.loginwindow` although the screen is not locked, and no app can be brought forward until some live app is activated (the unified log shows `Setting processToBringForwardAtNextCheckin` for the dead instance). `PiccoloProcess.restart` therefore waits until LaunchServices lists no instance (`LaunchServicesRegistry.instances`, polled every 100 ms), retries a launch that still fails until the new process answers or the timeout runs out, and throws with what it saw. The root suite's `.piccoloRunning` launches the installed Piccolo before a test when none answers, so one failed restart fails only its own test. Restart Now (`AppRestart`) follows the same rule.
- **Focus must be verified, never assumed.** Since macOS 14 an app cannot always activate itself. `Focus.bring` hands the fixture to LaunchServices (`open`), and repeats until it observes the fixture frontmost (via `lsappinfo`; `NSWorkspace.frontmostApplication` goes stale without an app run loop), its window key, and Piccolo's `window.focusedFrame` agreeing. `loginwindow` frontmost means either a locked screen (`Frontmost.state()` reads `CGSSessionScreenIsLocked`; nothing in the repository can fix that, the owner has to unlock) or no frontmost application after a failed `open`, which a second `Focus.bring` clears by handing the front to Finder (never to Piccolo). Its failure message says which case it saw.

## Reviewer UI captures

- Hold the acceptance lock: `lockf -k -t 3600 "$HOME/.local/state/piccolo/accept.lock" <script>`. The `-k` matters: without it macOS `lockf(1)` unlinks the lock file when the command ends, and a running and a new `accept.sh` then lock different inodes and no longer exclude each other.
- Run `scripts/install.sh debug` from the PR's worktree first, wait for `piccoloctl app status` to answer, drive the window with `piccoloctl app settings.*` / `onboarding.*`, find it in `piccoloctl windows` by Piccolo's pid (Settings is its largest window) and capture it with `screencapture -x -o -l <n>`. Menu bar items are not windows of the app: the whole bar is one `MenuBarAgent` window at the top of the display; capture it and crop.
- Before any `settings.*` edit or `settings.restoreDefaults`, `config.load` a temporary file and stop if that fails: otherwise the edit writes the owner's config. End with `scripts/install.sh debug` again if Settings came to the front (it restarts Piccolo).
- README screenshots are in English: relaunch with `open -a /Applications/Piccolo.app --args -AppleLanguages '(en)'`, store `en` with `settings.setLanguage` for the shot (otherwise the restart row shows) and put back the language read from `settings.state` afterwards. Take the default shortcuts from `config.load` of a missing temporary file followed by `settings.restoreDefaults`.
