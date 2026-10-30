# Contributing

Piccolo is a personal project, but bug reports and fixes are welcome.

## Issues

- **Bugs:** use the bug report form. The most useful reports give the binding (or the config file), the apps and displays involved, what happened and what you expected; a suggested fix is a bonus.
- **Security problems:** report them privately, see [SECURITY.md](SECURITY.md).
- **Feature ideas:** open an issue to discuss it first. Piccolo stays small on purpose, and [CLAUDE.md](CLAUDE.md) lists its non-goals (drag-to-snap, automatic tiling, moving windows across Spaces, among others), so not every idea will fit.

## How the project is developed

Most of the code is written by Claude agents: the owner files issues and makes product decisions, an issue is the spec, a subagent implements it as one pull request, and Claude reviews, merges and releases. [CLAUDE.md](CLAUDE.md) holds the rules those agents follow; they apply to human contributions too. In short:

- Keep logic in `PiccoloCore`, and write the tests for the specified behaviour before the implementation.
- `swift test` passes, and so does `scripts/build.sh release`.
- Changes that move real windows or touch the app are checked with `scripts/accept.sh`, the desktop acceptance tests. They take over the desktop and need a signing identity (see [README › Signing](README.md#signing)); if you cannot run them, say so in the pull request.
- No third-party dependencies or new tools unless the issue says so.
- Never commit signing identities, key locations or machine-specific paths.
- Comments and docs in English. Commit messages follow Conventional Commits (`feat: …`, `fix: …`, `docs: …`).

## Pull requests

Link the issue, list the commands you ran and their results, and note anything that differs from the issue. The delivery record table in the template is for the orchestrator; leave it empty.
