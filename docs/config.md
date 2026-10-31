# Config internals

The format of `~/Library/Application Support/Piccolo/config.json`, its keys and defaults, and what happens to a file Piccolo cannot use fully are in the [README](../README.md#config-file). This file is how the app loads, saves and applies it.

## Loading and saving

- `ShortcutManager` (`PiccoloSystem`) loads the file at launch and on Reload Config, resolves it with `ShortcutPlan` and registers the shortcuts as Carbon hotkeys through `HotkeyRegistrar`. The Carbon calls sit behind `HotkeyBackend`, so the replace and failure logic is unit tested with a fake.
- A missing file means no bindings, with one exception: at launch, `ShortcutManager.loadAtLaunch(from:)` writes `Config.defaultShortcuts` (`PiccoloCore/Config/DefaultShortcuts.swift`) through `ConfigStore.createIfMissing`, which never writes over an existing file, and then loads it. `config.load`, Reload Config and every other load of a missing file write nothing. The defaults are never added to an existing file, so a config written before an action existed loads unchanged.
- `ShortcutManager.save(_:)` writes to the file it has loaded (the default location, or the file given to `config.load`) and loads it again. Every save writes every setting; the first save creates the folder too.
- A missing key takes its default without an issue. A key that cannot be read (an unknown name, a wrong JSON type, a value out of range) takes its default with an issue naming it, and counts as a dropped entry like a skipped binding.
- When the last load dropped something, the first save after it copies the file to `config.backup-<yyyyMMdd-HHmmss>.json` before writing, once per load, and the issue list says where the copy is until the next load. Restore Default Shortcuts goes through `ShortcutManager.replaceKeepingCopy(with:)`: it copies the file (`ConfigStore.backUp()`) and saves the default bindings in its place, keeping the settings in use.
- `setSuspended(_:)` releases every hotkey and keeps loads and saves from registering any until it is lifted (a recording in Settings).
- Load issues, plan issues and shortcuts the system refused are logged and listed in `config.status`.
- When a shortcut runs its action, on press or on release, is in [shortcuts-and-preview.md](shortcuts-and-preview.md).

## ActionSettings

`ActionSettings` (`PiccoloCore`) is what an action reads from the config: the resize step, the animation, the fill order and the gap. The hotkey path passes `ActionSettings(config)` of the config in effect when the key is pressed; `action.run` takes it from `ConfigController`. A new setting an action reads goes through it.

## Window gap

- The rule is `WindowGap.inset(_:gap:in:)` (`PiccoloCore/Geometry/WindowGap.swift`), the only place it is written. Frames are computed without a gap first and rounded as before; then every edge on the visible frame's edge (within 1 pt) moves in by `gap` and every other edge by half of it.
- A shared divider is rounded once, before the inset. With an odd gap the left or top edge takes the larger half (`gap - gap / 2`) and the right or bottom edge the smaller, so facing edges are exactly `gap` apart on whole points.
- Every frame Piccolo computes goes through it: presets and custom frames (`FrameResolver`; `center` is capped to the inset visible frame), the cycling steps and their recognition (`PresetCycle`), grid and group cells (`TileLayout.frames(in:gap:)`), reading a divider back (`LayoutGroup.recordAchieved`) and display moves (`DisplayLayout.frame(moving:from:to:gap:)`, which measures the relative frame in each visible frame inset by `gap`). `restoreWindow` ignores the gap.
- `ActionExecutor` hands the gap to the planners, so the destination preview shows the gapped frames. A group does not store it: a divider move uses the gap in effect when the key is pressed.
