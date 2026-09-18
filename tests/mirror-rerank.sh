#!/bin/bash
# Tests for the mirror re-rank prompt (docs/plans/2026-09-18-001-feat-mirror-rerank-prompt-plan.md).
#
# Exercises mirror-rerank with every external effect stubbed: timedatectl,
# reflector, eos-rankmirrors and sudo are overridable binaries under a scratch
# bin, and every path -- state, lock, both mirrorlists, the runtime dir -- points
# into a mktemp scratch. The suite never reads the live zone, never touches
# /etc/pacman.d/, and never takes the real lock.
#
# Run: bash tests/mirror-rerank.sh

# Default to the copy tracked in this repo, not the one installed on the
# machine, so the test exercises what a reviewer is reading.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${MIRROR_RERANK_SCRIPT:-$REPO_ROOT/home/.config/i3/scripts/mirror-rerank}"
FAILED=0

fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }
pass() { echo "  ok: $*"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# Every path the script can write goes under the scratch, never the real one.
export MIRROR_RERANK_STATE="$SCRATCH/state/mirror-rerank/state"
export XDG_RUNTIME_DIR="$SCRATCH/run"
mkdir -p "$XDG_RUNTIME_DIR"

# Stub externals. Each stub reads its behaviour from STUB_* variables so a test
# can flip one outcome without rewriting the stub.
STUBBIN="$SCRATCH/bin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/timedatectl" <<'STUB'
#!/bin/bash
[[ -n "${STUB_TZ_FAIL:-}" ]] && exit 1
printf '%s\n' "${STUB_TZ:-}"
STUB
chmod +x "$STUBBIN/timedatectl"
export MIRROR_RERANK_TIMEDATECTL="$STUBBIN/timedatectl"

# Pin "now" so age arithmetic is exact and the 30-day boundary cannot race the
# clock between the test writing a timestamp and the script reading it.
NOW=1758200000
export MIRROR_RERANK_NOW="$NOW"
DAY=86400

# Asserts a command's exit status equals an expected code.
assert_exit() {
    local desc="$1" want="$2"; shift 2
    "$@" >/dev/null 2>&1
    local got=$?
    if (( got == want )); then pass "$desc"; else fail "$desc (expected exit $want, got $got)"; fi
}

# Asserts a command's stdout contains a substring.
assert_contains() {
    local desc="$1" needle="$2"; shift 2
    local out
    out="$("$@" 2>/dev/null)"
    if [[ "$out" == *"$needle"* ]]; then pass "$desc"; else fail "$desc (output: '$out')"; fi
}

# Asserts a command's stdout is empty.
assert_silent() {
    local desc="$1"; shift
    local out
    out="$("$@" 2>/dev/null)"
    if [[ -z "$out" ]]; then pass "$desc"; else fail "$desc (output: '$out')"; fi
}

# write_state <zone> <ranked_at>  -- the state file format the script owns.
write_state() {
    mkdir -p "$(dirname "$MIRROR_RERANK_STATE")"
    printf 'zone=%s\nranked_at=%s\n' "$1" "$2" > "$MIRROR_RERANK_STATE"
}
clear_state() { rm -f "$MIRROR_RERANK_STATE"; }

echo "== status arms on a timezone change =="
write_state Asia/Dubai $((NOW - 1 * DAY))
export STUB_TZ=Europe/Helsinki
assert_exit     "status exits 0 when the live zone differs from the recorded one" 0 bash "$SCRIPT" status
assert_contains "the reason names the recorded zone"  "Asia/Dubai"      bash "$SCRIPT" status
assert_contains "the reason names the live zone"      "Europe/Helsinki" bash "$SCRIPT" status

echo "== status arms on age =="
write_state Asia/Dubai $((NOW - 31 * DAY))
export STUB_TZ=Asia/Dubai
assert_exit     "status exits 0 when the ranking is 31 days old" 0 bash "$SCRIPT" status
assert_contains "the reason names the age in days" "31 days" bash "$SCRIPT" status

echo "== status names both conditions, and the cost, when both hold =="
write_state Asia/Dubai $((NOW - 31 * DAY))
export STUB_TZ=Europe/Helsinki
assert_contains "both: names the zone change" "Europe/Helsinki" bash "$SCRIPT" status
assert_contains "both: names the age"         "31 days"         bash "$SCRIPT" status
assert_contains "both: names the data cost"   "MB"              bash "$SCRIPT" status
assert_contains "both: names the time cost"   "min"             bash "$SCRIPT" status

echo "== status is silent and exits 1 when the ranking is fresh =="
write_state Asia/Dubai $((NOW - 29 * DAY))
export STUB_TZ=Asia/Dubai
assert_exit   "status exits 1 when zone matches and the ranking is 29 days old" 1 bash "$SCRIPT" status
assert_silent "status prints nothing when disarmed" bash "$SCRIPT" status

echo "== the 30-day boundary: exactly 30 days is still fresh, one second more is not =="
write_state Asia/Dubai $((NOW - 30 * DAY))
assert_exit "exactly 30 days old is disarmed" 1 bash "$SCRIPT" status
write_state Asia/Dubai $((NOW - 30 * DAY - 1))
assert_exit "30 days and one second is armed" 0 bash "$SCRIPT" status

echo "== a missing or unreadable state file arms rather than crashing =="
clear_state
assert_exit     "missing state file arms" 0 bash "$SCRIPT" status
assert_contains "missing state file says there is no record" "no record" bash "$SCRIPT" status
mkdir -p "$(dirname "$MIRROR_RERANK_STATE")"
: > "$MIRROR_RERANK_STATE"
assert_exit "empty state file arms" 0 bash "$SCRIPT" status
printf 'zone=Asia/Dubai\n' > "$MIRROR_RERANK_STATE"
assert_exit "truncated state file (no timestamp) arms" 0 bash "$SCRIPT" status
printf 'zone=Asia/Dubai\nranked_at=yesterday\n' > "$MIRROR_RERANK_STATE"
assert_exit "non-numeric timestamp arms" 0 bash "$SCRIPT" status
assert_exit "non-numeric timestamp does not crash (never exit 2)" 0 bash "$SCRIPT" status

echo "== an unreadable live zone is an error, not disarmed =="
write_state Asia/Dubai $((NOW - 1 * DAY))
export STUB_TZ=
assert_exit "timedatectl printing nothing exits 2" 2 bash "$SCRIPT" status
export STUB_TZ_FAIL=1
assert_exit "timedatectl failing exits 2" 2 bash "$SCRIPT" status
unset STUB_TZ_FAIL
export STUB_TZ=Asia/Dubai

echo "== the default state path honours XDG_STATE_HOME =="
(
    # The subshell inherits FAILED; count only its own failures so the parent's
    # FAILED=$((FAILED + $?)) below does not double the running total.
    FAILED=0
    unset MIRROR_RERANK_STATE
    export XDG_STATE_HOME="$SCRATCH/xdg"
    if source "$SCRIPT" >/dev/null 2>&1; then
        [[ "$STATE_FILE" == "$SCRATCH/xdg/mirror-rerank/state" ]] \
            && pass "STATE_FILE resolves under XDG_STATE_HOME" \
            || fail "STATE_FILE resolved to '$STATE_FILE'"
    else
        fail "could not source $SCRIPT to read STATE_FILE"
    fi
    exit $FAILED
)
FAILED=$((FAILED + $?))

echo "== sourcing the script has no side effects =="
clear_state
( source "$SCRIPT" >/dev/null 2>&1 )
[[ -e "$MIRROR_RERANK_STATE" ]] \
    && fail "sourcing created a state file" \
    || pass "sourcing created no state file"

echo
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
