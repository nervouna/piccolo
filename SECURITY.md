# Security

Piccolo holds the Accessibility permission, which lets it read and move the windows of every app, and it registers global keyboard shortcuts. It is not sandboxed. Release builds are signed with a Developer ID and notarized; debug builds also host a local control channel for the acceptance tests, which release builds do not contain.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately through GitHub: **Security → Report a vulnerability** on this repository ([direct link](https://github.com/nervouna/piccolo/security/advisories/new)). Include what you did, what happened, and the release or commit you tested.

You will get an answer within a week. Fixes land on `main`; there are no maintained release branches.

## In scope

- A way for another process to make Piccolo act through its Accessibility permission
- A config file that makes Piccolo do more than move and resize windows
- A release build that contains debug control code, or a release archive that is not what `scripts/release.sh` produced
- Piccolo sending any data off the machine

## Out of scope

- Anything that needs an already compromised user account or administrator access
- Debug builds, which are for development only
- What other apps can do once you grant them the Accessibility permission
