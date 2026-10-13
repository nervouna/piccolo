# Piccolo

A macOS menu bar app that moves, resizes and arranges windows with global keyboard shortcuts.

Work in progress. Planned features:

- Place the focused window at a preset or custom frame
- Move the focused window between displays
- Arrange the most recently used windows in a grid
- Resize a window in an arranged layout and have its neighbours follow

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
