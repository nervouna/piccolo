# Piccolo

Piccolo is a macOS menu bar app that moves, resizes and arranges windows with global keyboard shortcuts. You bind each shortcut to one action in the Settings window: place the focused window at a preset or custom frame, move it to the next or previous display, or arrange your most recently focused windows in a grid. The bindings are stored in a JSON file, which you can also edit by hand.

<img src="docs/images/settings-shortcuts.png" alt="Settings window, Shortcuts tab: five bindings, with the Arrange Grid binding selected. Its editor shows 3 windows in 2 rows and 2 columns, and a preview of the three cells." width="640">

## Status

Piccolo is pre-release (version 0.1.0). No release has been published yet.

What works:

- Placing the focused window at a preset or a custom frame.
- Moving the focused window to the next or previous display.
- Arranging the most recently focused windows in a grid.
- The Settings window, for editing bindings and recording shortcuts.
- Launching at login.

What does not exist yet: linked resize. The Move Divider action can be configured and is saved to the config file, but it does nothing. Pressing its shortcut only logs that the action is not implemented. The resize step on the General tab is saved as well, but no action uses it yet.

## Requirements

- macOS 14 or later.
- The Accessibility permission. Piccolo moves other apps' windows through the Accessibility API. Without the permission, shortcuts still fire, but no window moves. Grant it under System Settings, Privacy & Security, Accessibility. When Piccolo starts without the permission, it asks macOS to show the prompt. It checks for the grant every second until it has it, so you do not need to restart Piccolo. The menu and the General tab show whether it is granted.
- Piccolo is not sandboxed and is not distributed through the Mac App Store. The project's design rules out the sandbox because of the Accessibility API, and the App Store because of the private `_AXUIElementGetWindow` function that matches windows to their numbers (see [CLAUDE.md](CLAUDE.md)).

## Install

No release has been published yet. Until one is, build Piccolo from source (see [Building and testing](#building-and-testing)).

From a release archive, once one is published:

1. Unzip the archive and move `Piccolo.app` to `/Applications`.
2. Open Piccolo. It has no Dock icon and opens no window at launch. Its icon appears in the menu bar.
3. Grant the Accessibility permission when asked (see [Requirements](#requirements)).

From source, `scripts/install.sh` builds the release configuration, replaces `/Applications/Piccolo.app` and opens it. It needs a signing identity. Without one, run `scripts/build.sh` and open `build/Piccolo.app`, then grant it the Accessibility permission. The details are under [Building and testing](#building-and-testing).

## Using Piccolo

Piccolo shows a menu bar icon and no Dock icon. Its menu shows, from top to bottom:

- the Accessibility status, with a button to open its settings when the permission is missing;
- a summary of the shortcuts, such as "3 shortcuts active", followed by the number of config problems when there are any;
- Reload Config, which reads the config file again;
- Reveal Config in Finder;
- Settings… (⌘,);
- Quit Piccolo (⌘Q).

Settings opens from the menu. It also opens when you launch Piccolo again while it is running, for example from Finder or with `open /Applications/Piccolo.app`. It does not open at launch.

### Shortcuts tab

- **Add and remove.** The + button adds a binding. It places the window in the left half and has no shortcut yet. The − button removes the selected binding.
- **Restore Default Shortcuts…** replaces every binding with the [default shortcuts](#default-shortcuts) after you confirm. The resize step stays. A copy of the config file is kept next to it first.
- **Action.** The Action menu offers four kinds: Place Window, Move to Display, Arrange Grid and Move Divider. Choosing a kind resets the binding to that kind's default: Left Half, Next Display, 4 windows in 2 × 2, or Move Divider Left. The parameters of the kind follow. For Place Window and Arrange Grid, a preview of the frame or cells is drawn beside the editor.
- **Recording a shortcut.** Click the button on the right of a binding. It reads "Record Shortcut" when the binding has none, and shows the shortcut, such as ⌃⌥F13, when it has one. Click it, then press the keys. Press Escape to cancel. Press Delete or Forward Delete on its own to clear the shortcut.
- **Rules.** A shortcut needs ⌘, ⌥ or ⌃, or it must be a function key (F1 to F20). Shift on its own does not count, so ⇧A is refused. A shortcut that another binding already has is refused too, and the message names the other binding by its action. A refused shortcut shows a message at the bottom of the window and nothing is saved. Recording ends after any key press, so press the keys again to retry.
- **Saving.** Every accepted change is written to the config file straight away. There is no save button.
- **While recording.** Every global shortcut is switched off, so you can press a shortcut that already exists to record it again. The Settings window takes the key press itself, so keys such as ⌘Q and ⌘, can be recorded.

### General tab

<img src="docs/images/settings-general.png" alt="Settings window, General tab: the Launch at login switch, the resize step, the Accessibility status, the Reveal Config in Finder button and the app version." width="640">

- **Launch at login** starts Piccolo when you log in. When macOS is waiting for you to allow it, the tab says so and offers a button to open Login Items in System Settings.
- **Resize step** is how far a linked resize will move a divider, as a share of the screen. The default is 5%. Typed values above 0% up to 50% are accepted. The arrows change it in steps of 1%, between 1% and 50%. Linked resize is not implemented yet (see [Status](#status)).
- **Accessibility** shows the permission status and opens its settings.
- **Config** reveals the config file in Finder.
- **Version** shows the app version and build number.

## Actions

Each binding runs one action.

| Action | Parameters | What it does |
|---|---|---|
| Place Window (`placeWindow`) | `frame`: a preset, or a custom frame | Sets the frame of the focused window. |
| Move to Display (`moveToDisplay`) | `direction`: `next` or `previous` | Moves the focused window to the neighbouring display and keeps its relative frame. |
| Arrange Grid (`arrangeGrid`) | `count`, `rows`, `columns` | Arranges the `count` most recently focused windows in a grid of `rows` by `columns` cells. |
| Move Divider (`moveDivider`) | `direction`: `left`, `right`, `up` or `down` | Not implemented yet. The binding is saved and does nothing. |

### Place Window

The frame is worked out against the visible frame of the display that holds most of the window. The visible frame is the screen without the menu bar and the Dock.

A custom frame is four fractions of that visible frame. `x` and `y` give the top-left corner and `width` and `height` the size. `width` and `height` must be above 0, and `x + width` and `y + height` must not be more than 1. In Settings the four fields are percentages: Left, Top, Width and Height.

Presets:

| Preset (file name) | Name in Settings | `x`, `y`, `width`, `height` (fractions of the visible frame) |
|---|---|---|
| `leftHalf` | Left Half | 0, 0, 1/2, 1 |
| `rightHalf` | Right Half | 1/2, 0, 1/2, 1 |
| `topHalf` | Top Half | 0, 0, 1, 1/2 |
| `bottomHalf` | Bottom Half | 0, 1/2, 1, 1/2 |
| `topLeft` | Top Left | 0, 0, 1/2, 1/2 |
| `topRight` | Top Right | 1/2, 0, 1/2, 1/2 |
| `bottomLeft` | Bottom Left | 0, 1/2, 1/2, 1/2 |
| `bottomRight` | Bottom Right | 1/2, 1/2, 1/2, 1/2 |
| `leftThird` | Left Third | 0, 0, 1/3, 1 |
| `centerThird` | Center Third | 1/3, 0, 1/3, 1 |
| `rightThird` | Right Third | 2/3, 0, 1/3, 1 |
| `leftTwoThirds` | Left Two Thirds | 0, 0, 2/3, 1 |
| `rightTwoThirds` | Right Two Thirds | 1/3, 0, 2/3, 1 |
| `maximize` | Maximize | 0, 0, 1, 1 |
| `center` | Center | No fixed fraction: keeps the window's size, capped to the visible frame, and centres it |

### Move to Display

Displays are ordered from left to right by the left edge of their frame. Displays with the same left edge are ordered from top to bottom. `next` moves the window to the display after its current one in this order, and `previous` to the one before. Both wrap around, so with two displays both directions lead to the other display.

The window keeps its position and its size as fractions of the visible frame of its display. A window larger than the visible frame of the target display is capped to it, and the window is moved back inside that visible frame. With one display, nothing happens.

### Arrange Grid

Arrange Grid takes the `count` most recently focused windows and places them in `rows` by `columns` cells.

- **Which windows.** Only windows that are on screen in the current Space are used, on the display that holds the focused window. Without a focused window, the display of the frontmost window is used. Only standard windows are used, not panels, sheets or other auxiliary windows. Minimized and full-screen windows are left out, and so are the windows of an application that does not answer quickly. Piccolo's own windows are never arranged.
- **Order.** The focused window counts as the most recently focused. Piccolo knows the focus order only since it started. Windows it has not seen focused come after the others, in front-to-back order.
- **Cells.** The most recently focused window takes the top-left cell. The others fill the cells row by row, from left to right and from top to bottom. The cell edges are whole points, and neighbouring cells share their edges.
- **Fewer windows than cells.** The grid is laid out for the windows there are. The cells fill row by row, a last row that is not full stretches across the width, and the rows share the height. Three windows in a 2 × 2 grid give two cells side by side on top and one across the bottom.
- **Cells too small.** If any cell would be less than 100 pt wide or high, nothing is moved, and the reason goes to the log.
- **Failures.** A window that cannot be moved, for example because it was closed in the meantime, does not stop the others. Arranged windows are moved, not raised or focused.

## Default shortcuts

Piccolo starts with these shortcuts, so the window actions work right after installation. At launch, when there is no config file, Piccolo writes them to `~/Library/Application Support/Piccolo/config.json` and loads them. It never writes over an existing file, also not one with no bindings. Deleting the file brings the defaults back at the next launch. To restore them at any time, choose Restore Default Shortcuts… on the Shortcuts tab of Settings. Restoring replaces every binding and keeps the resize step. When there is a config file, a copy of it is kept next to it first, as `config.backup-<yyyyMMdd-HHmmss>.json`.

| Action | Shortcut |
|---|---|
| Left Half | ⌃⌥← |
| Right Half | ⌃⌥→ |
| Top Half | ⌃⌥↑ |
| Bottom Half | ⌃⌥↓ |
| Top Left | ⌃⌥U |
| Top Right | ⌃⌥I |
| Bottom Left | ⌃⌥J |
| Bottom Right | ⌃⌥K |
| Left Third | ⌃⌥D |
| Center Third | ⌃⌥F |
| Right Third | ⌃⌥G |
| Left Two Thirds | ⌃⌥E |
| Right Two Thirds | ⌃⌥T |
| Maximize | ⌃⌥↩ |
| Center | ⌃⌥C |
| Next Display | ⌃⌥⌘→ |
| Previous Display | ⌃⌥⌘← |
| Arrange 2 in 1 × 2 | ⌃⌥⇧2 |
| Arrange 3 in 1 × 3 | ⌃⌥⇧3 |
| Arrange 4 in 2 × 2 | ⌃⌥⇧4 |
| Arrange 6 in 2 × 3 | ⌃⌥⇧6 |
| Move Divider Left | ⌃⌥⇧← |
| Move Divider Right | ⌃⌥⇧→ |
| Move Divider Up | ⌃⌥⇧↑ |
| Move Divider Down | ⌃⌥⇧↓ |

(⌃ is Control, ⌥ is Option, ⇧ is Shift and ⌘ is Command.) The four Move Divider shortcuts do nothing yet, see [Status](#status).

A shortcut that another app already holds, for example another window manager with the same shortcuts, is refused by the system. Piccolo does not register it and reports the refusal in the config problems: the menu counts them, the Settings window lists them and the system log has the details.

## Config file

The config file is `~/Library/Application Support/Piccolo/config.json`. At launch, when there is no file, Piccolo writes the [default shortcuts](#default-shortcuts) to it. Otherwise a missing file means no bindings: Reload Config does not write anything, and the first save from Settings creates the file and its folder.

Piccolo reads the file at launch and when you choose Reload Config. It does not watch the file, so after you edit it by hand, choose Reload Config.

This example has one binding of each action kind:

```json
{
  "bindings": [
    {
      "action": {
        "frame": { "preset": "leftHalf" },
        "type": "placeWindow"
      },
      "id": "08574701-4FCF-498E-83ED-A7DC1F3FF806",
      "shortcut": { "keyCode": 123, "modifiers": ["control", "option"] }
    },
    {
      "action": {
        "frame": { "custom": { "height": 1, "width": 0.5, "x": 0.25, "y": 0 } },
        "type": "placeWindow"
      },
      "id": "7F2FD611-FA6A-4F94-BD73-49B3F148F061",
      "shortcut": { "keyCode": 8, "modifiers": ["control", "option"] }
    },
    {
      "action": { "direction": "next", "type": "moveToDisplay" },
      "id": "41764885-F04B-4C73-974F-F862046B2C9A",
      "shortcut": { "keyCode": 124, "modifiers": ["control", "option"] }
    },
    {
      "action": { "columns": 2, "count": 4, "rows": 2, "type": "arrangeGrid" },
      "id": "B5FDDA50-25B0-469F-9908-CA739E66751D",
      "shortcut": { "keyCode": 105, "modifiers": ["control", "option"] }
    },
    {
      "action": { "direction": "left", "type": "moveDivider" },
      "id": "2656EE97-32EE-4A72-91D9-F6D06C749808",
      "shortcut": { "keyCode": 123, "modifiers": ["command", "control", "option"] }
    }
  ],
  "resizeStep": 0.05,
  "version": 1
}
```

The five bindings do the following:

1. `⌃⌥←` places the window in the left half.
2. `⌃⌥C` places the window in a custom frame: 25% from the left, half the width, full height.
3. `⌃⌥→` moves the window to the next display.
4. `⌃⌥F13` arranges the four most recently focused windows in a 2 × 2 grid.
5. `⌃⌥⌘←` moves a divider to the left. This binding does nothing yet.

The keys can appear in any order. These are the keys of the file:

| Key | Value | Meaning |
|---|---|---|
| `version` | `1` | Required. The only version this build reads and writes. |
| `resizeStep` | number | Optional, default `0.05`. How far a linked resize moves a divider, as a fraction of the screen: above 0 and at most 0.5. |
| `bindings` | array | Required; may be empty. The bindings, in the order of the Settings list. |
| `id` | UUID string | Required in each binding. Identifies the binding; each binding needs its own. |
| `action` | object | Required in each binding. Its `type` selects the kind, and the other keys depend on the kind. |
| `type` | `"placeWindow"`, `"moveToDisplay"`, `"arrangeGrid"` or `"moveDivider"` | The kind of action. Any other value is rejected. |
| `frame` | object | For `placeWindow`. Exactly one of `preset`, a preset name from the table under Place Window, or `custom`, an object with `x`, `y`, `width` and `height` as described under Place Window. |
| `direction` | `"next"` or `"previous"` for `moveToDisplay`; `"left"`, `"right"`, `"up"` or `"down"` for `moveDivider` | Where the window or the divider goes. |
| `count`, `rows`, `columns` | integers | For `arrangeGrid`. Each is at least 1, and `count` is at most `rows` × `columns`. |
| `shortcut` | object | Optional. The key press that runs the binding. Leave the key out for a binding without a shortcut. |
| `keyCode` | integer | Required in `shortcut`. The macOS virtual key code, the `kVK_` value in Carbon's `Events.h`, at least 0. For example `123` is the left arrow, `8` is C and `105` is F13. Settings records the code for you. |
| `modifiers` | array of strings | Required in `shortcut`; may be empty. Any of `"command"`, `"option"`, `"control"` and `"shift"`. |

### When Piccolo cannot use the file fully

Piccolo keeps what it can use and reports the rest.

- **No file.** At launch, Piccolo writes the [default shortcuts](#default-shortcuts) and loads them. On Reload Config, a missing file means no bindings, and nothing is written.
- **Not JSON, or an unusable top level.** This covers a file that is not JSON, an object with no `version` or no `bindings`, and a `version` that is not a whole number of at least 1. The file is moved to `config.corrupt-<yyyyMMdd-HHmmss>.json` in the same folder, with the time it was moved in the name, and no bindings are loaded. Its content stays in that copy. The next launch finds no file and writes the default shortcuts.
- **A newer version.** A version above 1 is a format this build cannot read. The file is left untouched, no bindings are loaded, and Settings refuses to save over it.
- **A binding that cannot be read or breaks a rule.** This covers a missing or malformed key, an unknown `type`, a value out of range and a duplicate `id`. That binding is skipped as a whole, and the others load. The problem names the binding by its position in the file, counting from 0 and including skipped entries, for example `bindings[2] skipped: ...`. Of two bindings with the same `id`, the first one is kept.
- **A shortcut without ⌘, ⌥ or ⌃** that is not a function key. The binding loads and appears in Settings, but its shortcut is not registered.
- **A shortcut that an earlier binding already has.** The first binding keeps it. The later one is not registered.
- **A shortcut that the system refuses**, for example one that another app holds. It is not registered.
- **A `resizeStep` that is not a number or is out of range.** The default is used.

Problems are reported in three places. The menu shows how many there are. The Settings window lists each one at the bottom of the window, on both tabs. The system log has all of them, which you can read in Console under the subsystem `io.damao.piccolo`. Failed actions are logged there as well.

Settings writes the whole file on every save. Keys that Piccolo does not know are dropped, and a binding that was skipped when the file loaded is not written back. So when the file loaded with a skipped binding or an invalid `resizeStep`, Piccolo first copies it, as it was before the first save after the load, to `config.backup-<yyyyMMdd-HHmmss>.json` in the same folder. The copy keeps everything, including the keys Piccolo does not know and the skipped bindings. Each load makes at most one copy, at the first save after it, and an earlier copy is never overwritten. The problems that Settings lists name the copy until the file is loaded again, at launch or on Reload Config. If you edit the file by hand, still fix the problems that Settings lists before you save from Settings.

## Limitations

- **Accuracy.** Frames are accurate to about 1 pt of the display's visible area. The system reports that area to 1 pt, so a window that spans the full width or touches the top can come back 1 pt smaller than its target.
- **Sizes.** An app may refuse a size, because of a minimum or maximum size, an aspect ratio or resize increments. Terminal windows, for example, can only take sizes in whole character cells. Piccolo then keeps the window on its display, shifting it left or up if needed. It never moves a window past the top-left corner of the display's visible area.
- **Scope.** Piccolo does not drag windows to snap them, does not tile new windows automatically and does not move windows to another Space. Arrange Grid uses only the windows on screen in the current Space.
- **Focus.** The actions work on the focused window. When the Settings window has the focus, the shortcuts do nothing, because Piccolo never moves its own windows. Arrange Grid knows the focus order only since Piccolo started.
- **Shortcuts.** A shortcut that another app or the system already holds may be refused. Piccolo reports the refusal and does not register that shortcut.

## Building and testing

Requirements:

- macOS 14 or later.
- Xcode 27, the version the project was last upgraded with.
- A signing identity is needed to install a build, to run the desktop acceptance tests (see below) and to make a release (see [Releasing](#releasing)).

Commands, run from the root of the checkout:

```sh
swift test                  # unit tests
scripts/build.sh            # debug build: build/Piccolo.app and build/PiccoloFixture.app
scripts/build.sh release    # release build: build/Piccolo.app only
scripts/install.sh          # release build, installed to /Applications and opened
scripts/install.sh debug    # debug build, installed to /Applications and opened
scripts/accept.sh [filter]  # desktop acceptance tests, see below
```

- `swift test` runs the unit tests of the package. The desktop acceptance tests are skipped unless `PICCOLO_ACCEPTANCE=1` is set.
- `scripts/build.sh [debug|release]` builds with `xcodebuild`. The default is debug. The products go to `build/`, and the full build logs are written there too. The fixture app is a test support app. It is built for debug builds only, and release builds never contain it.
- `scripts/install.sh [debug|release]` builds, with release as the default. It quits a running Piccolo, replaces `/Applications/Piccolo.app` and opens it. It refuses to install an ad-hoc signed build. A debug build also runs a local control channel for the acceptance tests; a release build contains no control code.

### Signing

The scripts read their signing settings from `${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env`, or from the file named by `PICCOLO_SIGNING_ENV`. The file is never committed. It sets:

- `PICCOLO_CODESIGN_IDENTITY`, the name or hash of the code signing identity in your keychain;
- `PICCOLO_TEAM_ID`, the team ID. It must be set together with the identity.

Without a signing file, the builds are signed ad-hoc. The Accessibility grant is tied to the bundle ID and the signing identity, which is why `scripts/install.sh` refuses ad-hoc builds. Launch the app from Finder or with `open`, not by running its binary from a terminal: otherwise the Accessibility grant of the terminal is checked, not Piccolo's. The notary variables used by `scripts/release.sh` are listed under [Releasing](#releasing).

### Desktop acceptance

`scripts/accept.sh [filter]` runs the desktop acceptance tests on the real desktop. It takes a machine-wide lock, and waits up to `PICCOLO_ACCEPT_LOCK_TIMEOUT` seconds (600 by default) for another run to release it. It installs the debug build over `/Applications/Piccolo.app`, which needs a signing identity, opens the fixture app and runs the `PiccoloAcceptanceTests` target. Then it closes the fixture's windows and quits the fixture, also when a test fails or the script is interrupted. The debug build stays installed and running. The tests move windows, bring apps forward and post key presses, so do not use the machine while they run. The full test log is `build/accept-test.log`, and the exit code is the test result. [CLAUDE.md](CLAUDE.md) describes the tests and the harness in detail.

## Releasing

`scripts/release.sh` turns the checkout into a notarized, stapled archive at `build/release/Piccolo-<version>.zip`, where `<version>` is the app's marketing version (`MARKETING_VERSION` in the Xcode project; the script does not bump it). It builds a release with a Developer ID signature, the hardened runtime, a secure timestamp and no `get-task-allow` entitlement, verifies the signature, submits the app to the Apple notary service and waits for the verdict, staples the ticket, zips the stapled app, and finally checks the app extracted from that zip with `stapler validate` and `spctl`. It prints the archive path and its SHA-256. A rejected submission prints the notary log and fails.

```sh
scripts/release.sh                  # build, notarize, staple, archive
scripts/release.sh --skip-notarize  # rehearse everything except notarization
```

Notarization uploads the app to Apple and typically takes a few minutes. An archive made with `--skip-notarize` is signed but not notarized and must not be distributed.

The settings are read from `${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env` (override the path with `PICCOLO_SIGNING_ENV`). They are never committed. The file defines:

| Variable | Meaning |
|---|---|
| `PICCOLO_CODESIGN_IDENTITY` | Name or hash of the Developer ID Application signing identity in the keychain |
| `PICCOLO_TEAM_ID` | Apple developer team ID |
| `PICCOLO_NOTARY_KEY` | Path to the App Store Connect API key file used for notarization |
| `PICCOLO_NOTARY_KEY_ID` | ID of that API key |
| `PICCOLO_NOTARY_ISSUER_FILE` | Path to a file containing the App Store Connect issuer ID |

The script refuses to run without a signing identity, and without the three notary variables unless `--skip-notarize` is given. The key is passed to `notarytool` by path and is never read, copied or printed; the issuer ID is never printed.

## License

[MIT](LICENSE)
