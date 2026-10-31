#!/usr/bin/env bash
# Desktop acceptance: builds and installs the Debug Piccolo, launches the fixture app
# and runs the acceptance tests against the real desktop.
#
# Usage: scripts/accept.sh [filter]
#
#   filter   narrows the run to acceptance tests whose name matches this regular
#            expression (swift test --filter 'PiccoloAcceptanceTests.*<filter>').
#            Test names are the Swift function names, e.g. "setFocusedFrame".
#
# Environment:
#   PICCOLO_ACCEPT_LOCK_TIMEOUT   seconds to wait for the machine-wide lock when another
#                                 run holds it (default 600); then exit 75, "locked".
#
# Acceptance moves real windows and replaces /Applications/Piccolo.app, so only one run
# may use the desktop at a time. The lock is an flock on
# ${XDG_STATE_HOME:-$HOME/.local/state}/piccolo/accept.lock, shared by every checkout and
# worktree; the system drops it when this script ends, however it ends.
#
# Teardown is unconditional (normal end, test failure, error, Ctrl-C, SIGTERM): Piccolo is
# handed back to the config at the default location (every test runs on a temporary
# fresh-install config), fixture windows are closed, the fixture is quit, the lock is
# released. The Debug build of Piccolo stays installed and running.
#
# The exit code is the test result: 0 only when the tests passed. One line on stdout
# summarizes the run; progress goes to stderr.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: scripts/accept.sh [filter]" >&2
}

filter=""
case $# in
    0) ;;
    1)
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -*)
                usage
                exit 2
                ;;
        esac
        filter="$1"
        ;;
    *)
        usage
        exit 2
        ;;
esac

lock_timeout="${PICCOLO_ACCEPT_LOCK_TIMEOUT:-600}"
[[ "$lock_timeout" =~ ^[0-9]+$ ]] \
    || die "PICCOLO_ACCEPT_LOCK_TIMEOUT must be a whole number of seconds, not '$lock_timeout'"

cd "$PICCOLO_ROOT"

# --- The machine-wide lock. -------------------------------------------------------
#
# File descriptor 9 holds the lock for the lifetime of this script. Nothing this script
# starts may inherit it (see run), or a daemon outliving the script could keep the
# lock held for good.

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/piccolo"
lock_file="$state_dir/accept.lock"
lock_info="$state_dir/accept.lock.info"

mkdir -p "$state_dir"
exec 9>>"$lock_file" || die "cannot open the lock file $lock_file"

lock_exit=0
lockf -s -t 0 9 || lock_exit=$?
if ((lock_exit == 75)) && ((lock_timeout > 0)); then
    log "Another acceptance run holds the lock ($(cat "$lock_info" 2>/dev/null || echo "no details")); waiting up to $lock_timeout s"
    lock_exit=0
    lockf -s -t "$lock_timeout" 9 || lock_exit=$?
fi
if ((lock_exit == 75)); then
    echo "error: locked: another desktop acceptance run holds the lock ($lock_file) and did not release it within $lock_timeout s." >&2
    echo "Holder: $(cat "$lock_info" 2>/dev/null || echo "unknown"). Try again later, or raise PICCOLO_ACCEPT_LOCK_TIMEOUT." >&2
    exit 75
elif ((lock_exit != 0)); then
    die "could not take the lock $lock_file (lockf exit code $lock_exit)"
fi
echo "pid=$$ checkout=$PICCOLO_ROOT since=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$lock_info"

# --- Teardown, armed as soon as the lock is ours. -----------------------------------

CHILD_PID=""
CTL=""
fixture_app="$BUILD_DIR/$FIXTURE_NAME.app"

# kill_tree <pid>: terminates the process and everything below it.
kill_tree() {
    local child
    for child in $(pgrep -P "$1" 2>/dev/null || true); do
        kill_tree "$child"
    done
    kill -TERM "$1" 2>/dev/null || true
}

# fixture_running: whether a fixture process exists (matched by exact process name).
fixture_running() {
    pgrep -x "$FIXTURE_NAME" >/dev/null 2>&1
}

# wait_fixture_gone <tenths of a second>: true once no fixture process is left.
wait_fixture_gone() {
    local _
    for _ in $(seq 1 "$1"); do
        fixture_running || return 0
        sleep 0.1
    done
    ! fixture_running
}

# stop_fixture: closes the fixture's windows and ends it, as gently as it allows: a quit
# request first, then SIGTERM, then SIGKILL.
stop_fixture() {
    fixture_running || return 0
    if [[ -n "$CTL" && -x "$CTL" ]]; then
        "$CTL" fixture closeAll --timeout 5 >/dev/null 2>&1 9>&- || true
        "$CTL" fixture quit --timeout 5 >/dev/null 2>&1 9>&- || true
        wait_fixture_gone 50 && return 0
    fi
    pkill -TERM -x "$FIXTURE_NAME" 2>/dev/null || true
    wait_fixture_gone 30 && return 0
    pkill -KILL -x "$FIXTURE_NAME" 2>/dev/null || true
    wait_fixture_gone 20 || log "warning: a $FIXTURE_NAME process is still running"
}

# restore_config: hands the Debug Piccolo back to the config at the default location. Every test
# loads a temporary fresh-install config (config.load) and the tests undo that themselves, but a run
# that is interrupted or killed mid-test cannot. config.reload reads the default location only and
# never writes to it.
restore_config() {
    [[ -n "$CTL" && -x "$CTL" ]] || return 0
    "$CTL" app config.reload --timeout 5 >/dev/null 2>&1 9>&- || true
}

cleanup() {
    local rc=$?
    trap - EXIT INT TERM HUP
    set +e
    if [[ -n "$CHILD_PID" ]] && kill -0 "$CHILD_PID" 2>/dev/null; then
        kill_tree "$CHILD_PID"
        wait "$CHILD_PID" 2>/dev/null
    fi
    restore_config
    stop_fixture
    rm -f "$lock_info"
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# run <command...>: runs the command in the background and waits for it. A signal sent to
# this script is then handled at once; the shell would otherwise hold its trap back until
# a foreground command ended. The command does not get the lock descriptor.
run() {
    local rc=0
    "$@" 9>&- &
    CHILD_PID=$!
    wait "$CHILD_PID" || rc=$?
    CHILD_PID=""
    return "$rc"
}

# wait_for <seconds> <what> <command...>: polls until the command succeeds.
wait_for() {
    local deadline=$((SECONDS + $1)) what="$2"
    shift 2
    until "$@" >/dev/null 2>&1 9>&-; do
        ((SECONDS < deadline)) || die "timed out waiting for $what"
        sleep 0.2
    done
}

# --- Prepare the desktop. -----------------------------------------------------------

log "Acceptance lock acquired"
# A fixture left by an interrupted run belongs to an older build.
stop_fixture

run "$SCRIPT_DIR/install.sh" debug

log "Building piccoloctl"
run swift build --product piccoloctl
CTL="$(swift build --show-bin-path)/piccoloctl"
[[ -x "$CTL" ]] || die "piccoloctl was not built at $CTL"

wait_for 30 "the Debug Piccolo to answer on its control channel" "$CTL" app status

log "Launching the fixture"
[[ -d "$fixture_app" ]] || die "$fixture_app does not exist; scripts/build.sh debug builds it"
run open "$fixture_app"
wait_for 30 "the fixture to answer on its control channel" "$CTL" fixture list

# --- Run the tests. -----------------------------------------------------------------

test_log="$BUILD_DIR/accept-test.log"
test_filter="PiccoloAcceptanceTests"
if [[ -n "$filter" ]]; then
    test_filter="PiccoloAcceptanceTests.*$filter"
fi

log "Running the acceptance tests (filter: $test_filter; full log: ${test_log#"$PICCOLO_ROOT"/})"
test_exit=0
run env PICCOLO_ACCEPTANCE=1 PICCOLO_FIXTURE_APP="$fixture_app" \
    swift test --filter "$test_filter" >"$test_log" 2>&1 || test_exit=$?

# Swift Testing reports "Test run with N tests in M suites passed after S seconds."
run_line="$(grep -E 'Test run with [0-9]+ tests?' "$test_log" | tail -n 1 || true)"
skipped="$(grep -cE '^(➜|↳)? ?Test .* skipped' "$test_log" || true)"
ran="$(sed -nE 's/.*Test run with ([0-9]+) tests?.*/\1/p' <<<"$run_line")"
seconds="$(sed -nE 's/.* after ([0-9.]+) seconds.*/\1/p' <<<"$run_line")"

if ((test_exit == 0)) && [[ -z "$ran" || "$ran" == "0" ]]; then
    log "swift test succeeded but ran no acceptance test; does the filter '$filter' match a test name?"
    test_exit=1
fi

if ((test_exit == 0)); then
    grep -E '^(✔|✘|➜) ' "$test_log" >&2 || true
    noun="tests"
    [[ "$ran" == "1" ]] && noun="test"
    echo "accept: PASS - $ran $noun passed in ${seconds:-?} s (${skipped:-0} skipped)"
else
    # Everything: compiler errors, the failed expectations, the measurements.
    cat "$test_log" >&2
    echo "accept: FAIL - swift test exited with $test_exit (log: ${test_log#"$PICCOLO_ROOT"/})"
fi
exit "$test_exit"
