# Feature internals

How the features work inside, and the rules that are easy to break. What the user sees is in the [README](../README.md); the types named here hold the details.

## Applying frames and animation

### Applying a frame

- Every action and `window.setFocusedFrame` apply a frame with `FrameSetter.apply`: size, position, size, read back. A window whose size is not settable still moves to the target's origin.
- Actions pass the target display's visible frame: a window that ends up sticking out of it (it refused the size) is shifted left and up until it lies inside, never past the top-left corner. `window.setFocusedFrame` knows no display and does not shift.

### Window animation

- Every action glides its windows to their new frames over `ActionSettings.animation`, then places them with `FrameSetter.apply` exactly as without animation, so the achieved frames, the shift into the visible frame and the errors do not depend on the animation.
- The pure part is in `PiccoloCore/Animation`: `FrameInterpolation` (the frame at progress t, whole points, exactly the start and the target at the ends) and `AnimationEligibility` (no animation when start and target are within 1 pt on every edge or lie mostly on different displays).
- `WindowAnimator` (`PiccoloSystem/Animation`) drives all windows of an action on one injected `AnimationClock`, with the progress taken from the clock: slow Accessibility calls drop frames and never stretch the animation. A tick sends a window only what changed, the position first when its top or left edge moves towards the corner and the size first otherwise, so that the window stays within its old and new frame.
- A window whose size is not settable animates its position only. A window whose change throws, or whose tick takes longer than the whole duration, drops out of the animation and only gets the final apply.
- A divider move and a swap animate their first round with the shrinking windows first, and a dropped window also stops the windows behind it, so that none grows into space that was not freed. The second round for refused sizes is not animated.
- Only an `ActionExecutor` that was given an animator animates: `ActionExecutor.live` has one, the default (used by the executor's unit tests) has none. A shortcut pressed during an animation runs after it, because the action queue is serial.

### Edge bounce

- A Swap Window press that finds no neighbour bounces the focused window towards that side and back instead of failing, when the animation is not Off and the executor has an animator. `EdgeBounce` (`PiccoloCore/Animation`) is the damped spring the owner picked (#97); its constants are private to it, and its duration is the same at every animation speed.
- `left`, `right` and `down` move the frame and keep its size. `up` squashes instead (the top edge stays, the bottom edge moves up), because macOS keeps windows below the menu bar.
- `WindowAnimator.bounce` uses the tick schedule of every animation. The offset is exactly 0 at the end, so the window ends on the frame read when the group was checked: no `FrameSetter`, no shift into the visible frame, and the window may leave its display for a moment. The group, the window records and the window order are not touched.
- There is no bounce, and `SwapOutcome.Reason.noNeighbour(bounced: false)` says so, when the animation is Off, when the executor has no animator, when `up` finds the size not settable, or when an Accessibility call throws during the bounce (the window is then put back at its start frame, errors ignored). A slow call drops frames but never the window.
- Planning never bounces: `planSwap` answers `SwapPlan.noNeighbour`, the preview shows nothing, and with a held shortcut the bounce happens when the action runs, on release.

## Linked resize, Swap Window and column-first grids

### Groups

- A successful `arrangeGrid` records a group of its windows for its display (`LayoutGroupStore`, rules in `PiccoloCore/LinkedResize`): the layout, the windows in cell order, the visible frame and the achieved frames. An arrangement in which a window failed records none. One group per display, a window in at most one group, in memory only. A group does not store the gap: a move uses the gap in effect when the key is pressed.
- A group is validated when the key is pressed: the windows on screen are read, and a member that is missing or has an edge more than 2 pt from its recorded frame dissolves the group.
- `moveDivider` and `swapWindow` share the lookup and the sending in `LinkedResizeExecution.swift`: `lookUpFocusedGroup` (the group of the focused window, validated) and `carryOut` (the glide, `FrameSetter.apply`, `recordAchieved` with the second round for refused sizes, dissolving the group on a failing window, `records.recordChange`).
- Actions read the resize step, the gap and the fill order of the config in effect when the key is pressed (`ActionExecutor.run(_:onlyPid:settings:)`; `action.run` takes them from `ConfigController`), so a test that depends on them loads a temporary config first. `onlyPid` restricts a move or a swap as it does an arrangement: a group with a window of another process is dissolved instead.

### Move Divider

- `DividerMove.plan` gives the new layout, the windows whose cell changed are sent to it (those that shrink first), and `LayoutGroup.recordAchieved` records where they ended up. A window that refused its size moves the divider to where it ended up, and the windows whose cell changed with it are sent there once more. A window that cannot be changed ends the move and dissolves the group.
- Nothing to do: `noFocusedWindow`, `noGroup`, `dissolved` (cause `missing` or `moved`) and `cannotMove` (the window that would shrink is at 10%, or there is no divider that way). The answers are in [control-channel.md](control-channel.md).

### Swap Window

- Exchanges the focused window with its neighbour on the side of the key (`SwapExecution.swift`; the planning, `planSwap`, is read-only and shared with `destinations`).
- The neighbour (`SwapNeighbor.neighbor(of:direction:in:)`) is geometric, so a column layout needs no transpose: the layout is laid out in a large frame without a gap, where neighbouring cells share their edges exactly; a candidate's facing edge coincides with the focused cell's edge on the side of the key and overlaps it on the other axis by a positive length. The longest overlap wins, then the lowest cell index.
- The two windows trade cells (`LayoutGroup.swappingCells`), glide together (they pass each other, so they overlap during the glide) and are placed, the one that shrinks first; no other window is touched. The group is recorded with the same layout through `recordAchieved`, so a window that refused the size of its new cell moves the divider exactly as in a divider move. The group stays linked.
- No window is raised or focused: the focused window keeps the focus and moves with its cell, so repeated presses carry it across the group.
- With no neighbour the window bounces (see "Edge bounce" above), and the hotkey path shows the `noNeighbour` notice only when it did not bounce.

### Column-first grids

- `ActionSettings.gridFillOrder` decides how `arrangeGrid` numbers the cells: `rows` row by row; `columns` makes a column layout, numbered top to bottom within a column and columns left to right (3 windows in 2 × 2 are two stacked on the left and one at full height on the right). Window `i` sits in cell `i` either way.
- A column layout is stored as the transposed row layout (`TileLayout.transposed`). `frames(in:)`, `validate()`, `DividerMove.plan` and `recordAchieved` all go through the transpose, with the divider directions transposed (`left`↔`up`, `right`↔`down`).

## Cycling, Restore Window and the window records

- `PresetCycle` (`PiccoloCore/Actions`) holds the three steps of the halves (1/2, 2/3, 1/3 anchored to the preset's edge). A window is at step k when its frame is within 2 pt (`FrameTolerance`) of step k, or of the achieved frame recorded for step k of the same preset, so that a window that refused the exact size still cycles; otherwise it is at step 0.
- Restore Window: with a record whose `lastAchieved` the window is still at (2 pt), the target is the record's `origin` on the display that holds most of it, shifted inside the visible frame like any target; an origin on no display keeps its size, centred on the window's current display; otherwise there is nothing to do (the notice `nothingToRestore`). It ignores the gap.
- `ActionPlanner.plan` is shared by `run` and `destinations`, so the preview shows the next step and the restore target. Planning never writes the records.
- The records (`WindowRecord`; update rules in `WindowRecords`; kept by `WindowRecordStore`, shared by the copies of an `ActionExecutor`) are keyed by window number. A window without one is neither recorded nor restorable and cycles by its frame alone.
- A run records every window it changed that did not fail (a single-window action, the placed windows of an arrangement, the windows of a divider move or a swap whose cell changed). When the window has no record or is no longer at its `lastAchieved` (the user moved it since), the frame before the action becomes the new `origin`; `lastAchieved` and the step are then set to what the action achieved. A restore that ran clears the record, and one that found nothing to do drops the stale record. A cycling press is never a notice.

## Failure notice

- When a shortcut fires and nothing can happen, a short notice in the middle of the display says why. `FailureNotice` (`PiccoloCore/Notice`) lists the reasons; its raw values are the stable names used on the control channel.
- The mapping is in `PiccoloSystem/FailureNotice+System.swift`, from a thrown error (`FailureNotice(error:)`) or an outcome (`FailureNotice(outcome:for:)`). There is no notice for config errors (`ActionExecutionError`, `ActionPlanningError`, which Settings reports), for `placeWindow` with nothing to do, for a success, or for a swap that bounced.
- `ConfigController.run` (the hotkey path) maps the result on the action queue and shows the notice through `NoticeController` on the main thread, on the display that holds the focused window, or the one with the mouse when there is none. `action.run` and the planning of the preview never show a notice.
- The panel is `NoticePanel`; a new notice replaces the one showing and restarts its timer. It follows the [overlay panel rules](shortcuts-and-preview.md#overlay-panels).

## Onboarding guide

- A floating panel that walks a new user through granting Accessibility, moving a window and arranging two windows. `OnboardingFlow` (`PiccoloUI/Onboarding`) is the pure, unit-tested state machine; `OnboardingModel` holds whether it is open, the stored flag and the auto-advance after a done step.
- Step 2 asks for the first `leftHalf` binding with a shortcut, else the first `placeWindow` binding with one; step 3 for the 2-window 1 × 2 grid, else the first `arrangeGrid` binding with one. Without a binding the step says so and offers Open Settings.
- A step is completed only while it is showing and Accessibility is granted, by a successful hotkey run of its binding: `ConfigController.run` reports each non-failing run to `OnboardingController.hotkeyRan`. `action.run` does not count.
- It opens at launch when `ConfigController.start()` wrote the default shortcuts (a first launch) and `OnboardingSeen` is not set, and from "Getting Started…" at step 1 whatever is stored. Finish, Skip Guide and the close button store `OnboardingSeen` in the `io.damao.piccolo` defaults domain.
- The panel (`OnboardingPanel`) is non-activating, floating and on every Space, placed in the top-right corner of the display with the mouse when it is first shown. It follows the [overlay panel rules](shortcuts-and-preview.md#overlay-panels), except that it takes clicks on its buttons, still without activating Piccolo: the shortcuts it asks for must act on the app the user works in.

## Settings window

### Opening

- The window is an `NSWindow` with toolbar tabs (`SettingsWindowController` in `PiccoloUI`, owned by `SettingsController` in `App/`), not a SwiftUI `Settings` scene: a scene cannot be opened reliably from code in a menu bar app.
- Every way of opening it (the menu, a second launch through `applicationShouldHandleReopen`, the control channel) ends in `SettingsWindowController.show()`. When Piccolo is not active, it asks for activation with the option `activateIgnoringOtherApps`, passed as its raw value `1 << 1` because it is deprecated since macOS 14; it is what makes the request work (the measurements and the fallback are on `show()`, and the acceptance test "Settings in front" catches a macOS that stops honouring it). `show()` never asks LaunchServices to open Piccolo, so a second launch cannot start a loop of reopen events.

### Tabs, sizes and focus (#99 item 1)

- The tabs are the items of an `NSToolbar` in the `.preference` style, and the window title is the selected tab's name. Not an `NSTabViewController`: it resizes the window from its children by itself, and Piccolo has to own the animation, the anchoring and the limit to the screen.
- `SettingsModel.tab` is the source of truth both ways, so `settings.showTab` changes the tab of an open window and a window created later opens on it. A tab change forgets the error of the old tab, and the General tab reads the login item and the language again when it comes up.
- Both tabs are hosting controllers with `sizingOptions = []`: a SwiftUI view that sizes its window by itself neither keeps the top edge nor animates. The sizes are `SettingsWindowSizing`. The Shortcuts tab is resizable, and only the person's own resizes and moves are saved (the controller counts its own frame changes in `ownFrameChanges`). The General tab is exactly as tall as its content: `GeneralPane` lays it out in a `ScrollView` and reports the height (`GeneralHeight`), because in a `VStack` the problems strip would take more than it needs and the form would scroll.
- A tab change animates the window to the new size and keeps its top-left corner, moving it up or left only as far as needed to stay inside the visible frame; a tab that still does not fit scrolls. A new size during an animation replaces it, so the window always ends at the last size asked for; `NSWindow.setFrame` does not stop an animation under way, so even a size set without animation goes through one that takes no time. The size is fitted again when the window opens, once more after it is on screen (the toolbar takes its height from the frame then), and when it moves to another screen.
- Opening the window and changing the tab leave no text field with the focus. The system or SwiftUI focuses the first field when the window becomes key (up to 0.1 s after `show()`) and when a tab's view is put in the window, so the controller takes it back with `makeFirstResponder(nil)`. A `show()` on a window that is key already takes nothing from a field the person is typing in.

### General tab

- Launch at login and Language; Moving windows (the animation, the destination preview); Arranging windows (the gap, the fill order, the linked resize step); a card with Accessibility and the config file; the version. A refused gap or resize step shows under its field; a save that failed shows above the version; problems with the config file belong to the Shortcuts tab.
- The login item switch goes through a `LoginItemBackend`: the model reads the status when the tab appears, when the window opens or the app is activated, and after every change, and shows a refused change under the switch.

### Shortcuts tab and the keymap

- The tab is a keymap of nine sections (`KeymapSection` in `PiccoloCore/Keymap`; the raw values name them on the control channel). `BuiltInActions.all` is the built-in actions in tab order; only grids (`arrangeGrid`) and custom areas (`placeWindow(.custom)`) are not built in.
- `Keymap.make` (`PiccoloUI/Model`, pure) builds the rows. Every built-in action is a row whether a binding has it or not, holding every binding with that action in file order (a hand-edited config may bind an action twice; the first binding is the row's `primaryBinding`). A grid or custom area is one row per binding. A binding without a shortcut counts as no shortcut.
- The search matches the trimmed query, ignoring case and diacritics, against a row's name and its shortcut text. With an empty query the grid and custom area sections are always there, possibly without rows.
- `ShortcutsTab` shows a search field and a "⋯" menu (Restore Default Shortcuts…, Reveal Config in Finder), the problems banner (the config's issues and errors whose target is `.window`), then one card per section. The "⋯" is a bordered `Button` that pops an `NSMenu` up, because a SwiftUI `Menu` draws the system's short capsule whatever its style. A row's glyph is decided by `ActionGlyphKind`, which is unit tested. Extra bindings of a built-in row show as tags that can be removed; the interface offers no way to add one.

### Recording and conflicts

- `beginRecording(_ row:)` suspends the hotkeys, clears the error and drops a pending conflict; a recording under way moves to the new row. The key press is caught by `SettingsWindowController`'s local key monitor. A click in the cards on anything that is not a control ends a recording.
- `record(_:)`: Escape alone cancels. Delete alone clears the row (a built-in row loses its first binding, a layout row keeps its binding without a shortcut). A shortcut that cannot be global (`Shortcut.isRegistrable`) is rejected on the row and **recording goes on**. A shortcut another binding has changes nothing, ends the recording and becomes `pendingConflict`. The row's own shortcut ends the recording with no change. Anything else is given to the row (a built-in row without a binding gets a new one).
- `resolveConflict(replace: true)` takes the shortcut from the other binding (removed when its action is built in, its shortcut cleared when it is a layout) and gives it to the row in one commit; `false` drops the conflict. Beginning a recording, any accepted change (also a no-op), opening the layout sheet and a reload drop a pending conflict; a rejected change does not.
- A recording of a layout row ends when its binding goes (removal, reload, restoring the defaults); restoring the defaults ends any recording.
- `SettingsModel.errorTarget` says where `error` shows: `.row` for a rejected shortcut, `.field(.gap)` or `.field(.resizeStep)`, and `.window` for everything else.

### Grids and custom areas (#99 item 6)

- `addLayout(_:)` accepts grids and custom areas only, appends a binding without a shortcut and starts recording on its row; `updateLayout(_:to:)` replaces the action within its section, keeping the binding, its place and its shortcut. Both are refused, with nothing saved, when `layoutProblem(_:editing:)` answers a problem: first the config's own validation of the action (its `fields` name the sheet's fields the failing rule is about), then an equal action in the same section. A request no window can make is refused with an English-only sentence.
- `editLayout(_:)` sets `layoutEditor`, the request for the sheet; `dismissLayoutEditor()` withdraws it, and so does closing the window. A reload drops an `.edit(id)` request whose binding is gone.
- `LayoutEditorSheet` is presented by `ShortcutsTab` with `.sheet(item:)`, not by the window controller, so a request made on the General tab waits until the Shortcuts tab is selected. The draft lives in the sheet's `@State` and reaches the model only with Done. Done and Delete dismiss the sheet even when the model refuses, so that the error shows on the tab. Escape is Cancel and Return is Done (no field has an `onSubmit`). Done is disabled while `layoutProblem` answers a problem, asked again on every change of the draft.
- The message line under the columns has a fixed height and is there when empty: a message that wraps makes the sheet open as tall as the text at its narrowest width, and a line that comes and goes would move the picture under the pointer while an area is dragged.
- The rules of the draft are `LayoutDraft` (`PiccoloCore/Keymap`), pure and tested with exact values: snapping, drawing a new area or moving one, the cell picker. Snapped values are computed as `(value * n).rounded() / n`, so a snapped value equals the same number typed and a snapped third equals the presets' third.
- The area picture pushes and pops its cursor itself (`PushedCursor`) and reads the option key from `NSEvent.modifierFlags` at every change of a drag. A percent field rewrites its text only when the area changes from outside or the field loses the focus.

### Undo and redo (#99 item 8)

- `SettingsModel.commit(_:)` is the one place a change is accepted, and it records the config it replaced: a step is a commit that changed the config. `undo()` and `redo()` go through the same validate-and-save path, so a backend that refuses leaves the config, the history, a recording and a pending conflict as they were. At most `historyLimit` steps are kept; a new change after an undo drops the steps that could be redone.
- Restoring the default shortcuts is one step (undoing it saves the old config, without a second backup), and so is a replaced conflict. A reload (a config replaced from outside) clears both histories; closing the window keeps them. Launch at login and the language are not part of the config and not in the history.
- A successful undo or redo ends a recording, drops a pending conflict and withdraws the sheet request of a layout the step removed.
- Piccolo has no Edit menu, so ⌘Z would reach nothing: the window's key monitor takes it, and `SettingsUndoKey` is the pure decision (including keyboard layouts without Latin letters). While a row records, ⌘Z is recorded like any other shortcut. Otherwise the press is taken, also with nothing to undo, unless a text field has the focus (it keeps its own undo) or a sheet is open. There is no undo inside the sheet; its Cancel discards what it edited.

## Language setting and restart

- The choice is stored as `AppleLanguages` in Piccolo's own defaults domain (`LanguageDefaults`): one code, or no key for System default. That is the key macOS reads for an app's language at launch and the one System Settings → Language & Region → Applications writes, so the two agree. The config file does not hold the language.
- A change applies at the next launch. `SettingsModel.effectiveLanguage` is the language the running app started in (read once at launch), and `restartRequired` compares the choice with it, System default counting as the system's first language (`LanguageBackend.systemLanguage`), so that System default on a Mac already set to that language needs no restart.
- Restart Now (`AppRestart`) starts `/bin/sh` with a short script and terminates Piccolo. The script waits for the old process to be gone and for LaunchServices to list no instance of the app (see [acceptance.md](acceptance.md#platform-behaviour-the-harness-depends-on)), then `open`s the bundle, again when that fails or no instance shows up. Failures go to the unified log under the tag `PiccoloRestart`. A helper that cannot be started leaves Piccolo running and shows the reason under the button (`restartError`).
