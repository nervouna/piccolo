# Shared helpers for the Piccolo scripts. Sourced by them, not executed.
#
# shellcheck shell=bash disable=SC2034

# Absolute path of the checkout (or git worktree) that contains this script, so
# the scripts behave the same from any working directory.
PICCOLO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_DIR="$PICCOLO_ROOT/build"
APP_NAME="Piccolo"
INSTALLED_APP="/Applications/$APP_NAME.app"

die() {
    echo "error: $*" >&2
    exit 1
}

log() {
    echo "==> $*" >&2
}

# Reads the signing settings. They are never part of the repository: the file
# named by PICCOLO_SIGNING_ENV, or ${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env,
# is the only source. A missing file means ad-hoc signing.
#
# Sets SIGN_ENV_FILE, SIGN_IDENTITY and SIGN_TEAM (the last two are empty for ad-hoc).
load_signing_env() {
    SIGN_ENV_FILE="${PICCOLO_SIGNING_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/piccolo/signing.env}"

    # Do not let values inherited from the caller's environment override the file.
    unset PICCOLO_CODESIGN_IDENTITY PICCOLO_TEAM_ID

    if [[ -r "$SIGN_ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$SIGN_ENV_FILE"
    elif [[ -n "${PICCOLO_SIGNING_ENV:-}" ]]; then
        log "signing env file '$SIGN_ENV_FILE' is not readable"
    fi

    SIGN_IDENTITY="${PICCOLO_CODESIGN_IDENTITY:-}"
    SIGN_TEAM="${PICCOLO_TEAM_ID:-}"

    if [[ -n "$SIGN_IDENTITY" && -z "$SIGN_TEAM" ]]; then
        die "PICCOLO_CODESIGN_IDENTITY is set but PICCOLO_TEAM_ID is not (see $SIGN_ENV_FILE)"
    fi
}
