# Signing and releasing

## Signing

The scripts read their signing settings from `${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env`, or from the file named by `PICCOLO_SIGNING_ENV`. The file is never committed. It sets:

- `PICCOLO_CODESIGN_IDENTITY`, the name or hash of the code signing identity in your keychain;
- `PICCOLO_TEAM_ID`, the team ID. It must be set together with the identity.

Without a signing file, the builds are signed ad-hoc. The Accessibility grant is tied to the bundle ID and the signing identity, which is why `scripts/install.sh` refuses ad-hoc builds. Launch the app from Finder or with `open`, not by running its binary from a terminal: otherwise the Accessibility grant of the terminal is checked, not Piccolo's. The notary variables used by `scripts/release.sh` are listed under [Releasing](#releasing).

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

## Release gate and pre-releases

- Release gate: `swift test` and `scripts/build.sh release` on the exact commit to be tagged. Run `scripts/accept.sh` there only for code that changed since it last passed acceptance in the scope the table gives it (on `main` or on the merged PR result), with that scope; a full run only when such a change is in the full-run list. The published asset, downloaded again, has the SHA-256 of the local archive, is stapled, is assessed as `Notarized Developer ID`, and has no control code and no `get-task-allow`.
- Pre-release: `release.sh` writes `Piccolo-<version>.zip`; upload it as `Piccolo-<version>-alpha.<n>.zip` with `gh release create <tag> --prerelease --verify-tag`. A 504 from `gh release create` can leave the tag pushed and no release: check `gh release list`, then run it again.
