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

assert_true()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
assert_false() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }

# Asserts a command's stderr contains a substring.
assert_err_contains() {
    local desc="$1" needle="$2"; shift 2
    local err
    err="$("$@" 2>&1 >/dev/null)"
    if [[ "$err" == *"$needle"* ]]; then pass "$desc"; else fail "$desc (stderr: '$err')"; fi
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

# ---------------------------------------------------------------------------
# run: both rankings, safe replacement, the lock, and the state write.
# Every external is a stub whose behaviour is set per scenario through STUB_*
# variables; both mirrorlists are scratch files.
# ---------------------------------------------------------------------------
mkdir -p "$SCRATCH/etc"
export MIRROR_RERANK_MIRRORLIST="$SCRATCH/etc/mirrorlist"
export MIRROR_RERANK_EOS_MIRRORLIST="$SCRATCH/etc/endeavouros-mirrorlist"
export MIRROR_RERANK_LOCK="$XDG_RUNTIME_DIR/mirror-rerank.lock"
export SUDO_LOG="$SCRATCH/sudo.log"
export REFLECTOR_ARGS="$SCRATCH/reflector.args"
export EOS_CALLS="$SCRATCH/eos.calls"

# reflector: record argv, copy STUB_REFLECTOR_OUT to the --save path, print
# STUB_REFLECTOR_STDERR to stderr, exit STUB_REFLECTOR_EXIT.
cat > "$STUBBIN/reflector" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$REFLECTOR_ARGS"
save=""
while (( $# )); do
    case "$1" in --save) save="$2"; shift ;; esac
    shift
done
[[ -n "${STUB_REFLECTOR_STDERR:-}" ]] && cat "$STUB_REFLECTOR_STDERR" >&2
[[ -n "${STUB_REFLECTOR_OUT:-}" && -n "$save" ]] && cp "$STUB_REFLECTOR_OUT" "$save"
exit "${STUB_REFLECTOR_EXIT:-0}"
STUB

# eos-rankmirrors: record the call, print STUB_EOS_STDERR, advance the
# mirrorlist mtime when STUB_EOS_TOUCH is set, exit STUB_EOS_EXIT.
cat > "$STUBBIN/eos-rankmirrors" <<'STUB'
#!/bin/bash
printf 'eos-rankmirrors %s\n' "$*" >> "$EOS_CALLS"
[[ -n "${STUB_EOS_STDERR:-}" ]] && printf '%s\n' "$STUB_EOS_STDERR" >&2
if [[ -n "${STUB_EOS_TOUCH:-}" ]]; then sleep 0.01; touch "$MIRROR_RERANK_EOS_MIRRORLIST"; fi
exit "${STUB_EOS_EXIT:-0}"
STUB

# sudo: record argv, fail when STUB_SUDO_FAIL is set, otherwise emulate
# `install <opts> -- src dst` as a plain copy so the suite can inspect what
# landed without being root.
cat > "$STUBBIN/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$SUDO_LOG"
[[ -n "${STUB_SUDO_FAIL:-}" ]] && exit 1
if [[ "$1" == install ]]; then
    while (( $# )) && [[ "$1" != -- ]]; do shift; done
    [[ "$1" == -- ]] && shift
    cp -- "$1" "$2"
    exit $?
fi
exit 0
STUB
chmod +x "$STUBBIN"/*
export MIRROR_RERANK_REFLECTOR="$STUBBIN/reflector"
export MIRROR_RERANK_EOS_RANKMIRRORS="$STUBBIN/eos-rankmirrors"
export MIRROR_RERANK_SUDO="$STUBBIN/sudo"

# Fixtures: what reflector might hand back. $repo/$arch stay literal.
FX="$SCRATCH/fx"
mkdir -p "$FX"
{
    printf '# generated by reflector stub\n'
    for i in $(seq 1 20); do printf 'Server = https://m%02d.example/archlinux/$repo/os/$arch\n' "$i"; done
} > "$FX/good.list"
{
    printf 'rating 20 mirror(s) by download speed\nServer  Rate  Time\n'
    for i in $(seq 1 20); do printf 'https://m%02d.example/archlinux/  %8.2f KiB/s  %7.2f s\n' "$i" 1234.56 7.20; done
} > "$FX/good.log"
head -4 "$FX/good.list" > "$FX/truncated.list"
: > "$FX/empty.list"
sed '5s|https://|http://|' "$FX/good.list" > "$FX/plaintext.list"
{
    printf 'rating 20 mirror(s) by download speed\nServer  Rate  Time\n'
    for i in $(seq 1 20); do
        printf 'failed to rate http(s) download (https://m%02d.example/...): timed out\n' "$i"
        printf 'https://m%02d.example/archlinux/      0.00 KiB/s     0.00 s\n' "$i"
    done
} > "$FX/allfailed.log"

EOS_OK_NOTICE="Moving old EndeavourOS mirrorlist to .bak. Writing new ranked EndeavourOS mirrorlist."
EOS_UNCHANGED_NOTICE="The new EndeavourOS mirrorlist file was not ranked, not saving it."

# reset_run: armed by age, live lists in place, every stub set to succeed.
reset_run() {
    printf '# old arch list\nServer = https://old.example/$repo/os/$arch\n' > "$MIRROR_RERANK_MIRRORLIST"
    printf '# old eos list\nServer = https://old-eos.example/$repo/$arch\n' > "$MIRROR_RERANK_EOS_MIRRORLIST"
    rm -f "$MIRROR_RERANK_MIRRORLIST.bak" "$SUDO_LOG" "$REFLECTOR_ARGS" "$EOS_CALLS"
    write_state Asia/Dubai $((NOW - 31 * DAY))
    export STUB_TZ=Asia/Dubai
    export STUB_REFLECTOR_OUT="$FX/good.list" STUB_REFLECTOR_STDERR="$FX/good.log" STUB_REFLECTOR_EXIT=0
    export STUB_EOS_STDERR="$EOS_OK_NOTICE" STUB_EOS_TOUCH=1 STUB_EOS_EXIT=0
    unset STUB_SUDO_FAIL
}
state_ranked_at_is() { grep -qx "ranked_at=$1" "$MIRROR_RERANK_STATE"; }
live_list_is_old()   { grep -q 'old.example' "$MIRROR_RERANK_MIRRORLIST"; }
no_temp_left()       { [[ -z "$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'mirror-rerank.*' -type d)" ]]; }
STALE=$((NOW - 31 * DAY))

echo "== run: both rankings succeed and the state records zone and time =="
reset_run
rm -rf "$SCRATCH/state"
assert_exit "run exits 0 when both rankings succeed" 0 bash "$SCRIPT" run
assert_true "the state file's parent directory was created" test -f "$MIRROR_RERANK_STATE"
assert_true "state records the live zone"        grep -qx 'zone=Asia/Dubai' "$MIRROR_RERANK_STATE"
assert_true "state records the current timestamp" state_ranked_at_is "$NOW"
assert_true "reflector was invoked"        test -s "$REFLECTOR_ARGS"
assert_true "eos-rankmirrors was invoked"  test -s "$EOS_CALLS"
assert_true "the validated list is installed as the live Arch mirrorlist" grep -q 'm01.example' "$MIRROR_RERANK_MIRRORLIST"
assert_true "the temp directory was removed" no_temp_left

echo "== run: reflector is asked for a wide fresh pool, verbose, keeping twenty =="
reset_run
bash "$SCRIPT" run >/dev/null 2>&1
assert_true "reflector gets --age 12"       grep -q -- '--age 12'       "$REFLECTOR_ARGS"
assert_true "reflector gets --latest 60"    grep -q -- '--latest 60'    "$REFLECTOR_ARGS"
assert_true "reflector gets --sort rate"    grep -q -- '--sort rate'    "$REFLECTOR_ARGS"
assert_true "reflector gets --number 20"    grep -q -- '--number 20'    "$REFLECTOR_ARGS"
assert_true "reflector gets --protocol https" grep -q -- '--protocol https' "$REFLECTOR_ARGS"
assert_true "reflector gets --verbose so rates are observable" grep -q -- '--verbose' "$REFLECTOR_ARGS"

echo "== run: eos-rankmirrors is called bare, never through sudo =="
reset_run
bash "$SCRIPT" run >/dev/null 2>&1
assert_true  "eos-rankmirrors was called directly" grep -q 'eos-rankmirrors' "$EOS_CALLS"
assert_false "sudo was never asked to run eos-rankmirrors" grep -q 'eos-rankmirrors' "$SUDO_LOG"

echo "== run: reflector failing leaves everything untouched =="
reset_run
export STUB_REFLECTOR_EXIT=1
assert_exit  "run exits non-zero when reflector fails" 1 bash "$SCRIPT" run
assert_true  "the live Arch list is untouched" live_list_is_old
assert_true  "no backup was written"           test ! -e "$MIRROR_RERANK_MIRRORLIST.bak"
assert_true  "the state file is unchanged"     state_ranked_at_is "$STALE"
assert_false "eos-rankmirrors was not reached" test -e "$EOS_CALLS"
assert_true  "the temp directory does not survive a failed run" no_temp_left

echo "== run: the validation gate rejects a truncated or empty list =="
reset_run
export STUB_REFLECTOR_OUT="$FX/truncated.list"
assert_exit "a 3-server list is rejected"       1 bash "$SCRIPT" run
assert_true "live list untouched after truncated" live_list_is_old
assert_true "state unchanged after truncated"     state_ranked_at_is "$STALE"
reset_run
export STUB_REFLECTOR_OUT="$FX/empty.list"
assert_exit "an empty list is rejected"        1 bash "$SCRIPT" run
assert_true "live list untouched after empty"  live_list_is_old

echo "== run: the validation gate rejects a plaintext server line =="
reset_run
export STUB_REFLECTOR_OUT="$FX/plaintext.list"
assert_exit "a list with one http:// line is rejected" 1 bash "$SCRIPT" run
assert_true "live list untouched after plaintext"       live_list_is_old
assert_true "state unchanged after plaintext"           state_ranked_at_is "$STALE"

echo "== run: the validation gate rejects a list where no mirror was actually rated =="
reset_run
export STUB_REFLECTOR_STDERR="$FX/allfailed.log"
assert_exit "twenty https lines with every rate 0.00 are rejected" 1 bash "$SCRIPT" run
assert_true "live list untouched after all-failed"  live_list_is_old
assert_true "state unchanged after all-failed"      state_ranked_at_is "$STALE"

echo "== run: the previous Arch list is recoverable from .bak =="
reset_run
bash "$SCRIPT" run >/dev/null 2>&1
assert_true "the backup exists"                       test -f "$MIRROR_RERANK_MIRRORLIST.bak"
assert_true "the backup holds the previous contents"  grep -q 'old.example' "$MIRROR_RERANK_MIRRORLIST.bak"

echo "== run: the privileged step is argv-form install with root ownership, never a shell =="
reset_run
bash "$SCRIPT" run >/dev/null 2>&1
assert_true  "sudo ran install with -o root -g root -m 0644 --" grep -q 'install -o root -g root -m 0644 --' "$SUDO_LOG"
assert_false "sudo never ran bash -c"                          grep -qE 'bash -c|sh -c' "$SUDO_LOG"

echo "== run: a refused password leaves the state untouched =="
reset_run
export STUB_SUDO_FAIL=1
assert_exit "run exits non-zero when sudo fails" 1 bash "$SCRIPT" run
assert_true "live list untouched after sudo failure" live_list_is_old
assert_true "state unchanged after sudo failure"     state_ranked_at_is "$STALE"

echo "== run: eos-rankmirrors exiting zero after printing Failed is a failure =="
reset_run
export STUB_EOS_STDERR="$EOS_OK_NOTICE Failed." STUB_EOS_TOUCH= STUB_EOS_EXIT=0
assert_exit "run exits non-zero when the EndeavourOS write silently failed" 1 bash "$SCRIPT" run
assert_true "state unchanged after the silent EndeavourOS failure"           state_ranked_at_is "$STALE"
# Failed. must win even beside the no-change notice: the tool's messages are
# not a contract, and a printed failure is never read as success.
reset_run
export STUB_EOS_STDERR="$EOS_UNCHANGED_NOTICE Failed." STUB_EOS_TOUCH= STUB_EOS_EXIT=0
assert_exit "Failed. beside the no-change notice is still a failure" 1 bash "$SCRIPT" run
assert_true "state unchanged when Failed. accompanies the no-change notice" state_ranked_at_is "$STALE"

echo "== run: eos-rankmirrors reporting no change is a success =="
reset_run
export STUB_EOS_STDERR="$EOS_UNCHANGED_NOTICE" STUB_EOS_TOUCH= STUB_EOS_EXIT=0
assert_exit "run exits 0 when the EndeavourOS list was already optimal" 0 bash "$SCRIPT" run
assert_true "state updated after the no-change success"                  state_ranked_at_is "$NOW"

echo "== run: eos-rankmirrors advancing the mirrorlist mtime is a success =="
reset_run
export STUB_EOS_STDERR="" STUB_EOS_TOUCH=1 STUB_EOS_EXIT=0
assert_exit "run exits 0 when the EndeavourOS list was rewritten" 0 bash "$SCRIPT" run
assert_true "state updated after the rewrite"                     state_ranked_at_is "$NOW"

echo "== run: eos-rankmirrors exiting non-zero is a failure =="
reset_run
export STUB_EOS_EXIT=1
assert_exit "run exits non-zero when eos-rankmirrors dies" 1 bash "$SCRIPT" run
assert_true "state unchanged after eos-rankmirrors died"    state_ranked_at_is "$STALE"

echo "== run: a held lock is reported and nothing is written =="
reset_run
exec 8>"$MIRROR_RERANK_LOCK"
flock -n 8
assert_exit  "run exits non-zero while another run holds the lock" 1 bash "$SCRIPT" run
assert_err_contains "the held lock is reported"                      "already in progress" bash "$SCRIPT" run
assert_false "reflector was not invoked under a held lock"           test -e "$REFLECTOR_ARGS"
assert_true  "live list untouched under a held lock"                 live_list_is_old
assert_true  "state unchanged under a held lock"                     state_ranked_at_is "$STALE"
exec 8>&-

echo "== run: a free lock but fresh state exits quietly without ranking =="
reset_run
write_state Asia/Dubai $((NOW - 1 * DAY))
assert_exit   "run exits 0 when the state is already fresh" 0 bash "$SCRIPT" run
assert_silent "run prints nothing when the state is already fresh" bash "$SCRIPT" run
assert_false  "reflector was not invoked when already fresh" test -e "$REFLECTOR_ARGS"
assert_true   "state unchanged when already fresh"           state_ranked_at_is $((NOW - 1 * DAY))

echo "== run: with no runtime dir, a planted fallback parent refuses to start =="
reset_run
mkdir -p "$SCRATCH/tmpfb"
: > "$SCRATCH/tmpfb/mirror-rerank-$(id -u)"
assert_exit  "run refuses when the fallback parent exists and is not a directory" 2 \
    env -u XDG_RUNTIME_DIR -u MIRROR_RERANK_LOCK TMPDIR="$SCRATCH/tmpfb" bash "$SCRIPT" run
assert_err_contains "the refusal says why, so it is not mistaken for a usage error" "refusing" \
    env -u XDG_RUNTIME_DIR -u MIRROR_RERANK_LOCK TMPDIR="$SCRATCH/tmpfb" bash "$SCRIPT" run
assert_false "reflector was not invoked after the refused fallback" test -e "$REFLECTOR_ARGS"

echo
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
