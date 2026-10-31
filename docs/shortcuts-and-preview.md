# Held shortcuts and the destination preview

With `destinationPreview` on (the default) a shortcut runs when it is released, not when it is pressed, and holding it shows where its windows will go. With it off the shortcut runs on the press. Either way the action runs through `ActionExecutor` on the serial action queue.

## Hold rules

- `HoldRules` (`PiccoloCore/Shortcuts`) is a pure state machine from events (press, release, Escape, timer fired, cancel-all) to effects (run, show preview, hide preview, start timer). `HoldController` runs it against an injected `HoldTimer`; each `ShortcutManager` owns one.
- A press starts a hold and a 0.2 s timer. Released before the timer fires (a tap), the action runs on release and nothing is shown. Still held when it fires, the preview shows, and the release hides it and then runs the action. Escape while held hides the preview, and the release then does nothing.
- A press of any shortcut while one is held cancels the held one without running it and takes over, including a press of the held shortcut itself: there is no auto-repeat (see below), so a second press can only mean that the release was lost, and ignoring it would leave the shortcut dead until something else ended the hold. A release of a shortcut that is not the held one is ignored.
- Cancel-all hides the preview and drops the held shortcut without running it. Every load, save and suspend of `ShortcutManager` does it, so a config load, switching the preview off and recording a shortcut in Settings all end a hold.

## Carbon behaviour

Measured on macOS 27 and documented on `CarbonHotkeyBackend`: a key that stays down delivers one press (no auto-repeat), and the release is delivered also when the modifiers go up before the key. The hold rules depend on both. `HotkeyBackend` has `onRelease` next to `onPress`.

## Escape

- While a shortcut is held, `ShortcutManager` registers Escape (key code 53) with the held shortcut's modifiers as a temporary hotkey (`HotkeyRegistrar.registerTemporary`), so that its press cancels the hold and is not delivered to the frontmost application.
- It stays registered until the shortcut is released or the hold is cancelled in another way, also after Escape itself: the shortcut is still down, and Escape's key-up must not leak to another app.
- It is not registered when the held shortcut is on Escape itself, nor when the system refuses it (the hold still works, only Escape cannot cancel it).

## Interruptions

The key-up may never arrive when the system goes away, so `ShortcutManager.cancelHold()` is called by a `HoldInterruptionSource` (`SystemHoldInterruptions`, `PiccoloSystem/Hotkeys`) on `NSWorkspace.willSleepNotification`, `screensDidSleepNotification`, `sessionDidResignActiveNotification` and `willPowerOffNotification`, and on the distributed notifications `com.apple.screenIsLocked` and `com.apple.sessionagent.screenIsLocked` (the names `loginwindow` contains on macOS 27; there is no workspace notification for a lock). So no temporary Escape survives a lock. The source takes its two notification centers as parameters, so the unit tests post the real names into plain centers.

## Planning the preview

- When the rules say show, `DestinationPreview` (`PiccoloSystem/Preview`) plans on the action queue with `ActionExecutor.destinations(for:onlyPid:settings:)` and shows the result through a `HighlightPresenter`.
- The planning is read-only and shares its code with the run (`planSingleWindow`, `planArrangement`, `planDividerMove`, `planSwap`): it answers the frames the action would apply, and for an arrangement, a divider move and a swap the window of each, in cell order (a swap only the two windows that trade cells). It changes no window and no group: a group that no longer holds is dissolved by the real run, on release.
- A planning error, or nothing to do, shows no highlight, and the release runs the action as it would without a preview. A plan that comes back after the release, or after another show, is dropped.

## The highlight

`HighlightPanels` (`PiccoloSystem/Preview`) shows one borderless `NSPanel` per destination frame, at exactly that frame (canonical coordinates are converted at this boundary), drawn by `HighlightView` in the system accent colour, resolved when drawn so that light and dark mode and the accent colour follow. The level is `.statusBar` (25: above ordinary windows and floating panels, below menus), so in `CGWindowList` it is not among the layer 0 windows. The collection behaviour is `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary` and `ignoresCycle`: on the current Space, also over full-screen apps, not in Mission Control or the window cycle. It follows the overlay panel rules below.

## Overlay panels

The highlight, the failure notice and the onboarding guide are panels of Piccolo's process that sit over other apps. A panel must never take the focus or activate Piccolo (an app that has been the active application stops firing `hotkey.simulate`, see [acceptance.md](acceptance.md#platform-behaviour-the-harness-depends-on)): a non-activating panel that cannot become key or main, ignores the mouse, does not hide when the app is not active (a panel does by default, and Piccolo never is), and is ordered front with `orderFrontRegardless()`, never `makeKeyAndOrderFront`. Enumerations of windows leave the panels out twice over: they list layer 0 windows only, and never a window of Piccolo's own process.
