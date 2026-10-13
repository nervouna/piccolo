#!/usr/bin/env bash
# Runs /Applications/Piccolo.app in self-check mode and prints its JSON report:
# {"axTrusted": ..., "bundleID": ..., "version": ..., "build": ..., "bundlePath": ...}
#
# Usage: scripts/self-check.sh
#
# The app is launched through LaunchServices (open), never by executing the
# binary: only then is Piccolo its own "responsible process", so that
# AXIsProcessTrusted reports Piccolo's grant and not the grant of the terminal or
# agent that happens to run this script.

set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ -d "$INSTALLED_APP" ]] || die "$INSTALLED_APP does not exist, run scripts/install.sh first"

report="$(mktemp "${TMPDIR:-/tmp}/piccolo-self-check.XXXXXX")"
open_err="$(mktemp "${TMPDIR:-/tmp}/piccolo-self-check-open.XXXXXX")"
open_pid=""
cleanup() {
    if [[ -n "$open_pid" ]] && kill -0 "$open_pid" 2>/dev/null; then
        disown "$open_pid" 2>/dev/null || true # no job-control noise for the kill
        kill "$open_pid" 2>/dev/null || true
    fi
    rm -f "$report" "$open_err"
}
trap cleanup EXIT

open -n -W -a "$INSTALLED_APP" --args --self-check "$report" 2>"$open_err" &
open_pid=$!

# The report is the source of truth, not the exit of `open -W`: when the app exits
# before open has looked up its pid, open prints "Unable to block on application"
# and returns early. Give the app 30 seconds; it normally answers in well under one.
open_done=false
for _ in $(seq 1 300); do
    [[ -s "$report" ]] && break
    if ! $open_done && ! kill -0 "$open_pid" 2>/dev/null; then
        open_done=true
        wait "$open_pid" || die "could not launch $INSTALLED_APP: $(cat "$open_err")"
    fi
    sleep 0.1
done

if [[ ! -s "$report" ]]; then
    pkill -f -- "--self-check $report" || true
    die "self-check timed out without a report"
fi

# The app exits right after writing the report; let `open` notice before cleanup.
for _ in $(seq 1 50); do
    kill -0 "$open_pid" 2>/dev/null || break
    sleep 0.1
done

plutil -convert json -o /dev/null "$report" 2>/dev/null \
    || die "self-check output is not valid JSON: $(cat "$report")"
cat "$report"
echo
