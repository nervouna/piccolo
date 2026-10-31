# Debug control channel

Debug builds of Piccolo host a control server (`io.damao.piccolo.control`, a same-user `CFMessagePort`; no network socket) so that scripts and tests can query the app and trigger actions without keyboard input. It is the basis of the desktop acceptance tests.

## Protocol

- Requests are `{"command": String, "params": Object}`, responses `{"ok": Bool, "result": Any?, "error": String?}`. Frames are in canonical coordinates (origin at the top left of the primary display, y down).
- The commands are registered in `App/DebugControlServer.swift` and `App/Debug*Commands.swift`; the logic they call lives in the packages. The tests decode every answer in `Tests/PiccoloAcceptanceTests/PiccoloClient*.swift`, the reference for each field. The tables below give what the names do not.
- Handlers run on the server's own queue, not on the main thread. Accessibility calls have a 2 s messaging timeout.
- The server does not touch `ActionExecutor.live` until a command needs it, so that it never starts the focus tracker in the app's place (the acceptance test of the launch-time start relies on it).
- App names are localized: match on `bundleID` (`com.apple.finder`), not on `name`.
- Release builds contain no control code (see CLAUDE.md): `Piccolo.xcodeproj` links `PiccoloControl` into the app in Debug only, through a build-only target dependency and `OTHER_LDFLAGS`. `strings` on a Release binary must find no `PiccoloControl`. `PiccoloFixture` links it the normal way and is never part of a release.

## `piccoloctl`

- `swift run piccoloctl app <command> [--params '<json>']` sends a command; `--service <name>` picks another server, `--timeout <seconds>` raises the 5 s default. `piccoloctl fixture <command>` aims at the fixture's server (`io.damao.piccolo.fixture.control`).
- `piccoloctl windows` (`{windowNumber, pid, frame}`, no layer), `screens` and `frontmost` read the desktop directly.
- All output is one line of JSON on stdout; the exit code is 0 only on success.

## Windows and actions

| Command | Params | Answer and notes |
|---|---|---|
| `status` | | `{axTrusted, version, build, bundlePath, pid}` |
| `window.focusedFrame` | | `{frame, pid, appName}` of the focused window |
| `window.setFocusedFrame` | `{x, y, width, height}` | Applies the frame with `FrameSetter` and answers the achieved `frame`; knows no display, so no shift |
| `action.run` | The action as the config file writes it, plus `animation?` and `onlyPid?` | See below |
| `focus.history` | | `{windows}`: the windows the focus tracker has seen since launch, most recently focused first |
| `groups.list` | | The linked groups: `[{display, visibleFrame, layout, windows: [{window, frame}]}]`, windows in cell order with their recorded frames; `layout` is `{rows: [{height, widths}]}` or, column-first, `{columns: [{width, heights}]}` |
| `history.list` | | The window records, by window number: `[{window, origin, lastAchieved, preset?, step?}]`; `preset` and `step` when a cycling half placed it last |
| `displays` | | `[{frame, visibleFrame}]`, the primary display first |

`action.run` runs the action on the focused window and returns after the windows have glided and been placed. It never shows a notice; only the hotkey path does.

- `animation` (`off`, `fast`, `medium`, `slow`) replaces the config's animation for this call. Without it, and for the resize step, the gap and the fill order, the config in effect decides, as for a shortcut.
- `onlyPid` restricts the windows to one process: an arrangement takes only its windows, and a divider move or swap dissolves a group with a window of another process. Every test passes it, so that it never moves the owner's windows.
- Malformed params, an unknown `animation`, an invalid action (a custom frame off the screen) and window errors answer `ok: false` with a message.

| Action | Answer |
|---|---|
| `placeWindow`, `moveToDisplay`, `restoreWindow` | `{target, achieved}` (`achieved` differs when the window refused the size or was shifted inside its display), or `{nothingToDo: true}` |
| `arrangeGrid` | Arranges the most recently focused windows on the focused window's display: `{display, windows: [{window, target, achieved} or {window, target, error}]}`, the top-left cell first, or `{nothingToDo: true}`. A window that fails does not stop the others |
| `moveDivider` | `{moved: true, display, windows}`, every window of the group in cell order (`target` is the last frame it was asked for), or `{nothingToDo: true, reason, message}`; `reason` is `noFocusedWindow`, `noGroup`, `dissolved` (with `cause`, `missing` or `moved`, and the `window` that broke the group) or `cannotMove` |
| `swapWindow` | `{swapped: true, display, windows}` in cell order after the swap, or `nothingToDo` with the reasons of `moveDivider` except `cannotMove`, plus `noNeighbour` with `bounced`. The bounce is over when the command answers, so it can only be seen by sampling the window from outside |

## Config and hotkeys

| Command | Params | Answer and notes |
|---|---|---|
| `config.status` | | `{path, bindingCount, registered: [{id, keyCode, modifiers}], issues}` |
| `config.load` | `{path}` | Loads and applies another file for this run only and answers as `config.status`; nothing is written to the default location. Clears the Settings undo history |
| `config.reload` | | Loads the default location again; clears the history too |
| `hotkey.simulate` | `{id}` | Posts the key-down and key-up of a registered binding's shortcut and answers `{posted, fired}` once the hotkey fired, not when its action finished. With the preview on it is a tap: the action runs on release |
| `hotkey.press` | `{id, autorepeat?}` | Posts the key-down only and answers `{posted, fired}`; the key stays down until `hotkey.release`. `autorepeat: N` adds N key-downs flagged as repeats and the answer adds `presses` |
| `hotkey.release` | `{id, modifiersFirst?}` | Posts the key-up and answers `{posted, released}` once the app has seen the release (an error after 3 s). `modifiersFirst: true` posts a flags-changed event with no flags before it |
| `hotkey.escape` | | Posts Escape with the held binding's modifiers and answers `{posted, fired}` once the temporary Escape hotkey fired; `ok: false` when nothing is held |
| `preview.state` | | `{visible, frames, windows?, heldBindingID?, escapeRegistered, planningError?, last?: {bindingID, result, previewShown}}` |

- The key events come from a `CGEventSource(stateID: .privateState)`, posted at the HID tap: events from the HID system state reach the system but never fire a registered hotkey. An unregistered binding, or `CGPreflightPostEventAccess()` being false, answers `ok: false`; no command asks for the permission.
- `autorepeat` and `modifiersFirst` exist to measure Carbon (see [shortcuts-and-preview.md](shortcuts-and-preview.md#carbon-behaviour)).
- `preview.state.windows` is the window of each frame for an arrangement, a divider move or a swap. The action queue plans without `onlyPid`, so a test that releases an arrangement checks this list first and sends `hotkey.escape` when a window other than its own is in it. `planningError` says why the latest plan showed nothing. `last.result` is `ran` or `cancelled`; `previewShown` is true only when the highlight really reached the screen.
- The highlight is a window of Piccolo's process at each frame, on layer 25: the tests find it by pid and frame (`PiccoloOverlays`), since `PiccoloWindows.onScreen` lists layer 0 only.

## Notice and onboarding

| Command | Params | Answer and notes |
|---|---|---|
| `notice.state` | | `{visible, last?: {kind, text, frame}}`: `kind` is `FailureNotice.rawValue`, `text` is in the language Piccolo runs in. `last` is never cleared, so a test that expects no new notice compares it with its value before. The panel is on layer 25 |
| `onboarding.open` | | Opens the guide as the menu item does |
| `onboarding.close` | | Closes it as Skip Guide does, which stores `OnboardingSeen` |
| `onboarding.continue`, `onboarding.skip` | | Press those buttons (Continue is Finish on the last step); `ok: false` when the button is not enabled |
| `onboarding.setSeen` | `{seen}` | Sets the stored flag; `null` or no `seen` removes the key, so that it reads as never written |
| `onboarding.state` | | `{visible, step, done, moveBindingID?, arrangeBindingID?, seen, seenStored, frame?}`; `seenStored` says whether the key is stored at all. The panel is on layer 3 |

None of these activates Piccolo. A test reads `seen` and `seenStored` first and restores them at the end, also on failure: after a run, `defaults read io.damao.piccolo OnboardingSeen` says what it said before.

## Settings

- The `settings.*` commands drive the model the window uses. Each answers `settings.state`, or `ok: false` with the model's message when it rejects the request, and nothing is saved then.
- Edits write the file Piccolo has loaded, so run `config.load` with a temporary file first: they never touch the default location unless that is what is loaded.
- Every change made through the model is one undo step, except `settings.setLanguage` and `loginItem.set`, which are not part of the config.
- Rows are named `placeWindow.<preset>`, `restoreWindow`, `moveToDisplay.<direction>`, `moveDivider.<direction>` and `swapWindow.<direction>` for the built-in actions, and by the binding's UUID for a grid or a custom area (`KeymapRowID.name`). A name no row can have is `invalidParams`; a well-formed name with no row is `ok: false`.
- The commands that post keys (`settings.record`, `settings.pressKey`) post real keyboard events like `hotkey.simulate`, and refuse (`ok: false`, nothing posted) unless Piccolo may post events, is the frontmost application and has the Settings window as its key window, so that the key can never land in another app. Bring Piccolo forward through LaunchServices (`open` on the app) first.

| Command | Params | Notes |
|---|---|---|
| `settings.open`, `settings.close` | | `open` answers at once, before the system has activated Piccolo, so poll `settings.state` for `isActive` and `isKey`. `close` ends a recording and drops a pending conflict, and keeps the undo history |
| `settings.state` | | See the fields below |
| `settings.showTab` | `{tab}`: `shortcuts` or `general` | Also works with the window closed, which then opens on that tab; saves nothing |
| `settings.setSearch` | `{text}` | As typing it does; view state, saved nowhere |
| `settings.removeBinding` | `{id}` | |
| `settings.updateAction` | `{id, action}` | |
| `settings.setResizeStep` | `{value}`, a fraction (0.1 is 10%) | |
| `settings.setAnimation`, `settings.setGridFillOrder` | `{value}`, a name of the config file | `ok: false` for a name the format does not know |
| `settings.setDestinationPreview` | `{enabled}` | |
| `settings.setGap` | `{value}`, whole points from 0 to 64 | |
| `settings.restoreDefaults` | | Replaces the bindings with the defaults without the confirmation, keeps the settings; the answer adds `backup`, the name of the copy, or `null` when there was no file |
| `settings.beginRecording` | `{row}` | As a click on the row's shortcut button: every hotkey is suspended (`config.status.registered` is empty) until the recording ends |
| `settings.cancelRecording` | | |
| `settings.record` | `{row, keyCode, modifiers}` | Begins recording on the row and posts one key press; answers once the recorder has taken it. A rejected shortcut and a conflict come back in the state, not as `ok: false` |
| `settings.clearShortcut` | `{row}` | |
| `settings.resolveConflict` | `{replace}` | `true` replaces in one save, `false` drops; `ok: false` when none is pending |
| `settings.addLayout` | `{action}` | A grid or custom area; the answer has `recordingRow` set to the new row |
| `settings.updateLayout` | `{id, action}` | Within the binding's section |
| `settings.editLayout` | `{row}`, or `{new}`: `grids` or `customAreas` | Sets `layoutEditor`, which the Shortcuts tab shows as the sheet; ends a recording and drops a conflict |
| `settings.dismissLayoutEditor` | | Closes the sheet |
| `settings.pressKey` | `{keyCode, modifiers}` | Posts one key press to the window without recording: ⌘Z (`6`, `["command"]`) undoes, ⇧⌘Z redoes, a key in a text field goes to the field. Answers once the window's key monitor handled it (`SettingsWindowController.keyPressesSeen`); `ok: false` when it did not within 3 s. While a row records, ⌘Z is recorded instead |
| `settings.undo`, `settings.redo` | | As ⌘Z and ⇧⌘Z: through the same validate-and-save path; end a recording and drop a conflict; `ok: false` with "there is nothing to undo" or "there is nothing to redo" |
| `settings.setLanguage` | `{language}`: `system` or one of the eight codes | Changes `AppleLanguages` in Piccolo's defaults domain, which outlives a run: only the language tests use it. The running app keeps its language until it restarts |
| `settings.restartNow` | | Runs Restart Now and answers (with `restarting: true`) before Piccolo quits 0.3 s later; wait for a new pid |
| `settings.moveWindow` | `{display}`, an index in `displays` | Moves the open window to the top-left corner of that display's visible frame and fits its size; saves nothing |

`settings.state` fields whose meaning is not in their name:

- `isActive` is `NSApp.isActive`; `isKey` whether the Settings window is the key window of the active app.
- `bindings[].active` is false only for a shortcut that is not registered (the system refused it, or `ShortcutPlan` could not register it); while a recording suspends the hotkeys none is reported. `shortcutText` reads like `⌃⌥⇧⌘F14`. `animation` and `gridFillOrder` are the names of the config file.
- `rows` are the rows under the current `search`, in the order of the tab, built-in rows always present: `{row, section, name, editable, shortcuts: [{bindingID, shortcutText, active}], recording}`.
- `recordingRow` is absent when no row records. `conflict` is `{row, shortcutText, ownerBindingID, ownerName}`. `errorTarget` is `{"row": name}`, `{"field": "gap"}`, `{"field": "resizeStep"}` or `"window"`, present exactly when `error` is. `layoutEditor` is `{"new": section}` or `{"edit": id}`.
- `loginItem` is the status of `loginItem.status`. `language` is the stored choice (`system` or a code), `effectiveLanguage` the language the running app uses (never `system`); `restartError` appears after a restart that could not be arranged.
- `windowFrame` changes while the window animates to the size of a tab, so read it again until two reads agree. `windowTitle` is in the language the app runs in. `firstResponder` is `none`, `textField` (a text field or its field editor) or `other`. `contentFits` says that nothing in the tab scrolls and, on the General tab, that the window is as tall as the tab asks for.

## Login item

| Command | Params | Notes |
|---|---|---|
| `loginItem.status` | | `{status}`: `enabled`, `notRegistered`, `requiresApproval` (the user has to allow it in System Settings) or `notFound` |
| `loginItem.set` | `{enabled}` | Runs the model method behind the General tab's switch and answers `{status}`; a refusal answers `ok: false` with the system's message |

- `SMAppService.mainApp` stands for the running bundle, so only the app can ask: neither `piccoloctl` nor a test process can.
- Registering shows a system notification and changes the machine's Login Items, so only the acceptance test that restores it and a person use `loginItem.set`.
- Measured on macOS 27: an app that was never registered reports `notFound`, and `notRegistered` once it has been registered and unregistered; no API goes back to `notFound`, and neither state is a login item.
