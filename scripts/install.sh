#!/usr/bin/env bash
# Builds the app, replaces /Applications/Piccolo.app and launches it.
#
# Usage: scripts/install.sh [debug|release]   (default: release)
#
# Only a Debug build hosts the control server that piccoloctl talks to.
#
# The Accessibility grant is tied to the bundle ID and the signing identity, so
# only a build signed with the configured identity may be installed. Without one
# this script refuses before it builds or touches /Applications.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: scripts/install.sh [debug|release]" >&2
}

if [[ $# -gt 1 ]]; then
    usage
    exit 2
fi

case "${1:-release}" in
    debug | release) configuration="${1:-release}" ;;
    *)
        usage
        exit 2
        ;;
esac

load_signing_env

if [[ -z "$SIGN_IDENTITY" ]]; then
    die "no signing identity configured, refusing to install an ad-hoc build over $INSTALLED_APP.
Set PICCOLO_CODESIGN_IDENTITY and PICCOLO_TEAM_ID in $SIGN_ENV_FILE
(or point PICCOLO_SIGNING_ENV at a file that sets them)."
fi

"$SCRIPT_DIR/build.sh" "$configuration"

built_app="$BUILD_DIR/$APP_NAME.app"
if codesign -dv "$built_app" 2>&1 | grep -q '^Signature=adhoc'; then
    die "$built_app is ad-hoc signed, refusing to install it"
fi

# Stage next to the destination so that the final step is a single rename.
staging="$(mktemp -d "/Applications/.$APP_NAME-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$built_app" "$staging/$APP_NAME.app"
codesign --verify --strict --deep "$staging/$APP_NAME.app"

if pgrep -x "$APP_NAME" >/dev/null; then
    log "Quitting running $APP_NAME"
    pkill -TERM -x "$APP_NAME" || true
    for _ in $(seq 1 50); do
        pgrep -x "$APP_NAME" >/dev/null || break
        sleep 0.1
    done
    if pgrep -x "$APP_NAME" >/dev/null; then
        die "$APP_NAME is still running after SIGTERM, not replacing it"
    fi
fi

log "Installing $INSTALLED_APP"
rm -rf "$INSTALLED_APP"
mv "$staging/$APP_NAME.app" "$INSTALLED_APP"
codesign --verify --strict --deep "$INSTALLED_APP"

log "Launching $INSTALLED_APP"
open "$INSTALLED_APP"
