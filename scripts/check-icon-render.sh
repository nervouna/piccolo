#!/usr/bin/env bash
# Renders the icon that the system shows for a built app and checks that every pane of
# the artwork is flat in that render.
#
# Usage: scripts/check-icon-render.sh [<app>]   (default: build/Piccolo.app, see scripts/build.sh)
#
# The app is copied to a new directory under build/ first: the system caches an app's
# icon by its path, so only a copy at a fresh path shows the icon the app has now. The
# copy and the renders (icon-256.png, icon-32.png) stay in that directory for inspection.
# Exits 1 when a pane is not flat at either size (see scripts/icon-tool.swift, panes).

set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

app="${1:-$BUILD_DIR/$APP_NAME.app}"
[[ -d "$app" ]] || die "$app does not exist, run scripts/build.sh release first"

SOURCE="$PICCOLO_ROOT/design/icon.png"
build_icon_tool

mkdir -p "$BUILD_DIR"
work="$(mktemp -d "$BUILD_DIR/icon-check.XXXXXX")"
ditto "$app" "$work/$APP_NAME.app"
log "Rendering the copy at ${work#"$PICCOLO_ROOT"/}"

"$ICON_TOOL" render "$work/$APP_NAME.app" "$work" 256 32

status=0
for size in 256 32; do
    log "Panes at ${size} px"
    "$ICON_TOOL" panes "$SOURCE" "$work/icon-$size.png" || status=1
done

if ((status == 0)); then
    log "All panes are flat at 256 px and 32 px"
else
    log "A pane is not flat, look at ${work#"$PICCOLO_ROOT"/}/icon-256.png"
fi
exit "$status"
