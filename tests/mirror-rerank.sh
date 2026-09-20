#!/bin/bash
# Tests for the mirror re-rank prompt (docs/plans/2026-09-18-001-feat-mirror-rerank-prompt-plan.md).
#
# Exercises mirror-rerank with every external effect stubbed: timedatectl,
# reflector, eos-rankmirrors and sudo are overridable binaries under a scratch
# bin, and every path -- state, lock, both mirrorlists, the runtime dir -- points
# into a mktemp scratch. The suite never reads the live zone, never touches
# /etc/pacman.d/, and never takes the real lock. The zsh prompt helpers are
# extracted from the tracked .zshrc and driven under a pseudo-terminal.
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

# Asserts a command's stdout equals an expected string.
assert_out() {
    local desc="$1" expected="$2"; shift 2
    local actual
    actual="$("$@" 2>/dev/null)"
    if [[ "$actual" == "$expected" ]]; then pass "$desc"; else fail "$desc (expected '$expected', got '$actual')"; fi
}

# Asserts a command's stdout does not contain a substring.
assert_not_contains() {
    local desc="$1" needle="$2"; shift 2
    local out
    out="$("$@" 2>/dev/null)"
    if [[ "$out" != *"$needle"* ]]; then pass "$desc"; else fail "$desc (output: '$out')"; fi
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
export SUDO_CALLS="$SCRATCH/sudo.calls"
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

# sudo: record argv and a call count; fail every call when STUB_SUDO_FAIL is
# set, or only the Nth call when STUB_SUDO_FAIL_ON=N. The script's calls, in
# order, are: 1 `sudo -v` (the up-front password), 2 the backup install, 3 the
# live install, then one `rm` per superseded .pacnew. `-v` succeeds silently;
# `install <opts> -- src dst` is emulated as a plain copy and `rm -f -- path`
# as a plain remove, so the suite can inspect both what landed and what was
# discarded without being root.
cat > "$STUBBIN/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$SUDO_LOG"
n=$(( $(cat "$SUDO_CALLS" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$n" > "$SUDO_CALLS"
[[ -n "${STUB_SUDO_FAIL:-}" ]] && exit 1
[[ -n "${STUB_SUDO_FAIL_ON:-}" && "$n" == "$STUB_SUDO_FAIL_ON" ]] && exit 1
[[ "$1" == -v ]] && exit 0
if [[ "$1" == install ]]; then
    while (( $# )) && [[ "$1" != -- ]]; do shift; done
    [[ "$1" == -- ]] && shift
    cp -- "$1" "$2"
    exit $?
fi
if [[ "$1" == rm ]]; then
    while (( $# )) && [[ "$1" != -- ]]; do shift; done
    [[ "$1" == -- ]] && shift
    rm -f -- "$@"
    exit $?
fi
exit 0
STUB
chmod +x "$STUBBIN"/*
export MIRROR_RERANK_REFLECTOR="$STUBBIN/reflector"
export MIRROR_RERANK_EOS_RANKMIRRORS="$STUBBIN/eos-rankmirrors"
export MIRROR_RERANK_SUDO="$STUBBIN/sudo"

# Fixtures: what reflector might hand back. The list is the twenty kept
# mirrors; the log is the sixty rated ones, at realistic URL lengths so it is
# larger than one stdio buffer -- a gate that reads it with an early-exiting
# grep -q under pipefail can be killed by SIGPIPE and reject a good list.
# rated_log <rated> <total> writes a log where the first <rated> mirrors have a
# real rate and the rest timed out at 0.00 KiB/s. $repo/$arch stay literal.
FX="$SCRATCH/fx"
mkdir -p "$FX"
{
    printf '# generated by reflector stub\n'
    for i in $(seq 1 20); do printf 'Server = https://m%02d.example/archlinux/$repo/os/$arch\n' "$i"; done
} > "$FX/good.list"
# The line shapes below are copied from a real `reflector --verbose --sort rate`
# run on this machine (reflector 2023-5), including the `[date] LEVEL: ` prefix
# its logging handler adds. A synthetic format the tool never emits would let a
# later line-anchored regex pass this suite and fail against the real thing.
rated_log() {
    local rated="$1" total="$2" i
    printf '[2026-09-19 17:58:42] INFO: rating %s mirror(s) by download speed\n' "$total"
    printf '[2026-09-19 17:58:42] INFO: Server                                         Rate       Time\n'
    for i in $(seq 1 "$total"); do
        if (( i <= rated )); then
            printf '[2026-09-19 17:58:45] INFO: https://mirror%02d.some-long-hosting-provider-name.example/pub/archlinux/  %8.2f KiB/s  %7.2f s\n' "$i" 1234.56 7.20
        else
            printf '[2026-09-19 17:58:45] WARNING: failed to rate http(s) download (https://mirror%02d.some-long-hosting-provider-name.example/pub/archlinux/extra/os/x86_64/extra.db): Download timed out after 5 second(s).\n' "$i"
            printf '[2026-09-19 17:58:45] INFO: https://mirror%02d.some-long-hosting-provider-name.example/pub/archlinux/      0.00 KiB/s     0.00 s\n' "$i"
        fi
    done
}
rated_log 60 60 > "$FX/good.log"
rated_log  0 60 > "$FX/allfailed.log"
rated_log  1 60 > "$FX/onerated.log"
rated_log  9 60 > "$FX/ninerated.log"
rated_log 10 60 > "$FX/tenrated.log"
head -4 "$FX/good.list" > "$FX/truncated.list"
: > "$FX/empty.list"
sed '5s|https://|http://|' "$FX/good.list" > "$FX/plaintext.list"
(( $(wc -c < "$FX/good.log") > 4096 )) \
    && pass "the good reflector log exceeds one 4096-byte stdio buffer ($(wc -c < "$FX/good.log") bytes)" \
    || fail "the good reflector log is too small to exercise the pipe buffer boundary"

EOS_OK_NOTICE="Moving old EndeavourOS mirrorlist to .bak. Writing new ranked EndeavourOS mirrorlist."
EOS_UNCHANGED_NOTICE="The new EndeavourOS mirrorlist file was not ranked, not saving it."
# What eos-rankmirrors-helper prints for one unreachable mirror during a run
# that otherwise succeeds; it must never be read as the write failing.
EOS_OFFLINE_MIRROR="Failed to connect, the mirror may be currently offline."

# reset_run: armed by age, live lists in place, every stub set to succeed.
reset_run() {
    printf '# old arch list\nServer = https://old.example/$repo/os/$arch\n' > "$MIRROR_RERANK_MIRRORLIST"
    printf '# old eos list\nServer = https://old-eos.example/$repo/$arch\n' > "$MIRROR_RERANK_EOS_MIRRORLIST"
    # Both lists are pacman backup files we keep modified, so every upgrade of
    # their packages leaves a .pacnew behind: a run starts with one waiting for
    # each. The third belongs to another package and must survive untouched.
    printf '# upstream arch list\n' > "$MIRROR_RERANK_MIRRORLIST.pacnew"
    printf '# upstream eos list\n'  > "$MIRROR_RERANK_EOS_MIRRORLIST.pacnew"
    printf '# someone else\n'       > "$SCRATCH/etc/pacman.conf.pacnew"
    rm -f "$MIRROR_RERANK_MIRRORLIST.bak" "$SUDO_LOG" "$SUDO_CALLS" "$REFLECTOR_ARGS" "$EOS_CALLS"
    write_state Asia/Dubai $((NOW - 31 * DAY))
    export STUB_TZ=Asia/Dubai
    export STUB_REFLECTOR_OUT="$FX/good.list" STUB_REFLECTOR_STDERR="$FX/good.log" STUB_REFLECTOR_EXIT=0
    export STUB_EOS_STDERR="$EOS_OK_NOTICE" STUB_EOS_TOUCH=1 STUB_EOS_EXIT=0
    unset STUB_SUDO_FAIL STUB_SUDO_FAIL_ON
}
state_ranked_at_is()  { grep -qx "ranked_at=$1" "$MIRROR_RERANK_STATE"; }
live_list_is_old()    { grep -q 'old.example' "$MIRROR_RERANK_MIRRORLIST"; }
no_temp_left()        { [[ -z "$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'mirror-rerank.*' -type d)" ]]; }
no_install_attempted() { ! grep -q '^install ' "$SUDO_LOG" 2>/dev/null; }
both_pacnew_gone()     { [[ ! -e "$MIRROR_RERANK_MIRRORLIST.pacnew" && ! -e "$MIRROR_RERANK_EOS_MIRRORLIST.pacnew" ]]; }
both_pacnew_present()  { [[ -e "$MIRROR_RERANK_MIRRORLIST.pacnew" && -e "$MIRROR_RERANK_EOS_MIRRORLIST.pacnew" ]]; }
foreign_pacnew_kept()  { [[ -e "$SCRATCH/etc/pacman.conf.pacnew" ]]; }
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

echo "== run: the work is visible while it happens, not only after it =="
# The rate test is 5-10 minutes long; both tools' progress must reach the
# terminal, not just the log the gate parses. The log is still written -- the
# validation scenarios below would not be able to reject anything otherwise.
reset_run
run_out="$(bash "$SCRIPT" run 2>/dev/null)"
[[ "$run_out" == *' KiB/s '* ]] \
    && pass "reflector's per-mirror rates are shown as they are measured" \
    || fail "reflector's rating output never reached the terminal"
[[ "$run_out" == *'mirror01.some-long-hosting-provider-name.example'* ]] \
    && pass "each mirror is named as it is rated" \
    || fail "the rated mirrors were not named on the terminal"
(( $(printf '%s' "$run_out" | grep -c ' KiB/s ') >= 60 )) \
    && pass "every rated mirror in the pool is reported, not just a summary" \
    || fail "only $(printf '%s' "$run_out" | grep -c ' KiB/s ') of 60 rated mirrors were reported"
[[ "$run_out" == *'Writing new ranked EndeavourOS mirrorlist'* ]] \
    && pass "eos-rankmirrors' progress is shown too" \
    || fail "eos-rankmirrors' output never reached the terminal"
reset_run
export STUB_REFLECTOR_STDERR="$FX/allfailed.log"
rejected_out="$(bash "$SCRIPT" run 2>/dev/null)"
[[ "$rejected_out" == *' KiB/s '* ]] \
    && pass "the rating is shown even on a run the gate goes on to reject" \
    || fail "a rejected run showed nothing of the work it did"

echo "== run: the password is asked first, while the user is still at the keyboard =="
reset_run
bash "$SCRIPT" run >/dev/null 2>&1
assert_out "the first sudo call is -v, before any download" "-v" head -n 1 "$SUDO_LOG"
reset_run
export STUB_SUDO_FAIL=1
assert_exit         "run exits non-zero when the password is refused" 1 bash "$SCRIPT" run
assert_err_contains "the refusal is reported"                          "sudo" bash "$SCRIPT" run
assert_false        "a refused password starts no download"            test -e "$REFLECTOR_ARGS"
assert_true         "live list untouched after a refused password"     live_list_is_old
assert_true         "state unchanged after a refused password"         state_ranked_at_is "$STALE"

echo "== run: a good rate test is accepted every time, not most times =="
# The rated gate reads a log larger than one stdio buffer; twenty back-to-back
# runs would surface an early-exit pipeline being killed by SIGPIPE.
flaky=0
for _ in $(seq 1 20); do
    reset_run
    bash "$SCRIPT" run >/dev/null 2>&1 || flaky=$((flaky + 1))
done
(( flaky == 0 )) \
    && pass "twenty consecutive runs on the 60-line log all succeeded" \
    || fail "$flaky of twenty runs on the 60-line log were rejected"

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
assert_true  "no install was attempted"        no_install_attempted
assert_true  "the temp directory does not survive a failed run" no_temp_left

echo "== run: the validation gate rejects a truncated or empty list, before any install =="
reset_run
export STUB_REFLECTOR_OUT="$FX/truncated.list"
assert_exit "a 3-server list is rejected"       1 bash "$SCRIPT" run
assert_true "live list untouched after truncated" live_list_is_old
assert_true "state unchanged after truncated"     state_ranked_at_is "$STALE"
assert_true "no install was attempted for the truncated list" no_install_attempted
reset_run
export STUB_REFLECTOR_OUT="$FX/empty.list"
assert_exit "an empty list is rejected"        1 bash "$SCRIPT" run
assert_true "live list untouched after empty"  live_list_is_old
assert_true "no install was attempted for the empty list" no_install_attempted

echo "== run: the validation gate rejects a plaintext server line, before any install =="
reset_run
export STUB_REFLECTOR_OUT="$FX/plaintext.list"
assert_exit "a list with one http:// line is rejected" 1 bash "$SCRIPT" run
assert_true "live list untouched after plaintext"       live_list_is_old
assert_true "state unchanged after plaintext"           state_ranked_at_is "$STALE"
assert_true "no install was attempted for the plaintext list" no_install_attempted

echo "== run: the validation gate requires at least ten mirrors actually rated =="
reset_run
export STUB_REFLECTOR_STDERR="$FX/allfailed.log"
assert_exit "sixty https lines with every rate 0.00 are rejected" 1 bash "$SCRIPT" run
assert_true "live list untouched after all-failed"  live_list_is_old
assert_true "state unchanged after all-failed"      state_ranked_at_is "$STALE"
assert_true "no install was attempted for the unrated list" no_install_attempted
reset_run
export STUB_REFLECTOR_STDERR="$FX/onerated.log"
assert_exit         "one rated mirror out of sixty is rejected" 1 bash "$SCRIPT" run
assert_err_contains "the rejection says how many were rated"     "1 of 60" bash "$SCRIPT" run
assert_true         "live list untouched after one-rated"        live_list_is_old
assert_true         "no install was attempted for the one-rated list" no_install_attempted
reset_run
export STUB_REFLECTOR_STDERR="$FX/ninerated.log"
assert_exit "nine rated mirrors are rejected (floor is ten)" 1 bash "$SCRIPT" run
assert_true "state unchanged after nine-rated"                state_ranked_at_is "$STALE"
reset_run
export STUB_REFLECTOR_STDERR="$FX/tenrated.log"
assert_exit "ten rated mirrors are accepted (the floor)" 0 bash "$SCRIPT" run
assert_true "state updated after ten-rated"               state_ranked_at_is "$NOW"

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

echo "== run: the backup failing after the password was accepted is a failure =="
# One invocation per scenario: the stub's call counter spans the scenario.
reset_run
export STUB_SUDO_FAIL_ON=2
bash "$SCRIPT" run >/dev/null 2>"$SCRATCH/backup-fail.err"
rc=$?
(( rc == 1 )) \
    && pass "run exits 1 when the backup install fails" \
    || fail "run exits 1 when the backup install fails (got $rc)"
grep -q 'could not back up' "$SCRATCH/backup-fail.err" \
    && pass "the failure names the backup" \
    || fail "the failure names the backup (stderr: '$(cat "$SCRATCH/backup-fail.err")')"
assert_true "live list untouched when the backup fails" live_list_is_old
assert_true "state unchanged when the backup fails"     state_ranked_at_is "$STALE"
assert_true "the temp directory does not survive a backup failure" no_temp_left
unset STUB_SUDO_FAIL_ON

echo "== run: the backup succeeding but the live install failing is still a failure =="
reset_run
export STUB_SUDO_FAIL_ON=3
bash "$SCRIPT" run >/dev/null 2>"$SCRATCH/install-fail.err"
rc=$?
(( rc == 1 )) \
    && pass "run exits 1 when the live install fails" \
    || fail "run exits 1 when the live install fails (got $rc)"
grep -q 'could not install' "$SCRATCH/install-fail.err" \
    && pass "the failure names the install, not the backup" \
    || fail "the failure names the install, not the backup (stderr: '$(cat "$SCRATCH/install-fail.err")')"
assert_true "the backup was written before the install was attempted" test -f "$MIRROR_RERANK_MIRRORLIST.bak"
assert_true "the live list is untouched when its install fails"        live_list_is_old
assert_true "state unchanged when the live install fails"              state_ranked_at_is "$STALE"
unset STUB_SUDO_FAIL_ON

echo "== run: eos-rankmirrors exiting zero after printing Failed is a failure =="
reset_run
export STUB_EOS_STDERR="$EOS_OK_NOTICE Failed." STUB_EOS_TOUCH= STUB_EOS_EXIT=0
assert_exit "run exits non-zero when the EndeavourOS write silently failed" 1 bash "$SCRIPT" run
assert_true "state unchanged after the silent EndeavourOS failure"           state_ranked_at_is "$STALE"
assert_true "the temp directory does not survive an EndeavourOS failure"     no_temp_left
# Failed. must win even beside the no-change notice: the tool's messages are
# not a contract, and a printed failure is never read as success.
reset_run
export STUB_EOS_STDERR="$EOS_UNCHANGED_NOTICE Failed." STUB_EOS_TOUCH= STUB_EOS_EXIT=0
assert_exit "Failed. beside the no-change notice is still a failure" 1 bash "$SCRIPT" run
assert_true "state unchanged when Failed. accompanies the no-change notice" state_ranked_at_is "$STALE"

echo "== run: one unreachable EndeavourOS mirror is not a failed write =="
reset_run
export STUB_EOS_STDERR="$EOS_OFFLINE_MIRROR $EOS_OK_NOTICE" STUB_EOS_TOUCH=1 STUB_EOS_EXIT=0
assert_exit "run exits 0 when a mirror was offline but the list was written" 0 bash "$SCRIPT" run
assert_true "state updated despite the offline-mirror notice"                 state_ranked_at_is "$NOW"

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

echo "== run: a successful run discards the .pacnew files it has just superseded =="
# Both lists are pacman `backup` files this feature keeps permanently modified,
# so every upgrade of their packages leaves a .pacnew -- forever, by design.
# Neither holds a mirror the run did not already consider, and the EndeavourOS
# one is worse than noise: EndeavourOS's own hook overwrites it with an older
# ranking that pacdiff would then offer to install over what this run wrote.
reset_run
assert_exit "run still exits 0"                                 0 bash "$SCRIPT" run
assert_true "the superseded Arch .pacnew is gone"               test ! -e "$MIRROR_RERANK_MIRRORLIST.pacnew"
assert_true "the superseded EndeavourOS .pacnew is gone"        test ! -e "$MIRROR_RERANK_EOS_MIRRORLIST.pacnew"
assert_true "another package's .pacnew is left alone"           foreign_pacnew_kept
assert_true "the live Arch list itself survives"                test -s "$MIRROR_RERANK_MIRRORLIST"
assert_true "the live EndeavourOS list itself survives"         test -s "$MIRROR_RERANK_EOS_MIRRORLIST"
assert_true "the .bak of the previous Arch list survives"       test -s "$MIRROR_RERANK_MIRRORLIST.bak"
assert_true "the removal is argv-form rm through sudo"          grep -qx "rm -f -- $MIRROR_RERANK_MIRRORLIST.pacnew" "$SUDO_LOG"
reset_run
assert_contains "the run says what it discarded" ".pacnew" bash "$SCRIPT" run

echo "== run: a failed run leaves both .pacnew files for the next attempt =="
# Discarding is only safe once this run has actually replaced both lists.
reset_run
export STUB_REFLECTOR_EXIT=1
assert_exit "a failed rate test still fails"                    1 bash "$SCRIPT" run
assert_true "both .pacnew files survive a failed rate test"     both_pacnew_present
reset_run
export STUB_REFLECTOR_OUT="$FX/truncated.list"
assert_exit "a rejected list still fails"                       1 bash "$SCRIPT" run
assert_true "both .pacnew files survive a rejected list"        both_pacnew_present
reset_run
export STUB_EOS_EXIT=1
assert_exit "a failed EndeavourOS ranking still fails"          1 bash "$SCRIPT" run
assert_true "both .pacnew files survive a failed EOS ranking"   both_pacnew_present

echo "== run: a .pacnew that cannot be removed warns but does not fail the run =="
# The ranking already cost a 5-10 minute download. A cleanup failure must not
# withhold the state and charge for the whole thing again at the next terminal.
reset_run
export STUB_SUDO_FAIL_ON=4
assert_exit "the run still exits 0 when a .pacnew cannot be removed" 0 bash "$SCRIPT" run
assert_true "the state is still written"                             state_ranked_at_is "$NOW"
reset_run
export STUB_SUDO_FAIL_ON=4
assert_err_contains "the failure names the consequence" "pacdiff" bash "$SCRIPT" run
unset STUB_SUDO_FAIL_ON

echo "== run: no .pacnew waiting is not an error =="
reset_run
rm -f "$MIRROR_RERANK_MIRRORLIST.pacnew" "$MIRROR_RERANK_EOS_MIRRORLIST.pacnew"
assert_exit         "run exits 0 with nothing to discard"     0 bash "$SCRIPT" run
reset_run
rm -f "$MIRROR_RERANK_MIRRORLIST.pacnew" "$MIRROR_RERANK_EOS_MIRRORLIST.pacnew"
assert_not_contains "no removal is claimed"      "Removed"    bash "$SCRIPT" run
assert_true         "an absent .pacnew is not created"        test ! -e "$MIRROR_RERANK_MIRRORLIST.pacnew"

echo "== run: a held lock is reported and nothing is written =="
reset_run
exec 8>"$MIRROR_RERANK_LOCK"
flock -n 8
assert_exit  "run exits non-zero while another run holds the lock" 1 bash "$SCRIPT" run
assert_err_contains "the held lock is reported"                      "already in progress" bash "$SCRIPT" run
assert_false "reflector was not invoked under a held lock"           test -e "$REFLECTOR_ARGS"
assert_false "no password was asked under a held lock"               test -e "$SUDO_LOG"
assert_true  "live list untouched under a held lock"                 live_list_is_old
assert_true  "state unchanged under a held lock"                     state_ranked_at_is "$STALE"
exec 8>&-

echo "== run: a lock file that cannot be opened is a setup error, not a held lock =="
reset_run
mkdir -p "$SCRATCH/ro"
chmod 0555 "$SCRATCH/ro"
assert_exit         "run exits 2 when the lock file cannot be created" 2 \
    env MIRROR_RERANK_LOCK="$SCRATCH/ro/mirror-rerank.lock" bash "$SCRIPT" run
assert_err_contains "the unopenable lock is reported as such" "cannot open" \
    env MIRROR_RERANK_LOCK="$SCRATCH/ro/mirror-rerank.lock" bash "$SCRIPT" run
assert_false        "reflector was not invoked when the lock could not be opened" test -e "$REFLECTOR_ARGS"
chmod 0755 "$SCRATCH/ro"

echo "== run: a free lock but fresh state exits quietly without ranking, and asks for no password =="
reset_run
write_state Asia/Dubai $((NOW - 1 * DAY))
assert_exit         "run exits 0 when the state is already fresh" 0 bash "$SCRIPT" run
assert_silent       "run prints nothing on stdout when the state is already fresh" bash "$SCRIPT" run
assert_err_contains "run tells the operator the ranking is fresh" "fresh" bash "$SCRIPT" run
assert_false        "reflector was not invoked when already fresh" test -e "$REFLECTOR_ARGS"
assert_false        "no password was asked when already fresh"     test -e "$SUDO_LOG"
assert_true         "state unchanged when already fresh"           state_ranked_at_is $((NOW - 1 * DAY))
assert_true         "nothing is discarded when already fresh"      both_pacnew_present

echo "== run: with no runtime dir, a planted fallback parent refuses to start =="
reset_run
mkdir -p "$SCRATCH/tmpfb"
: > "$SCRATCH/tmpfb/mirror-rerank-$(id -u)"
assert_exit  "run refuses when the fallback parent exists and is not a directory" 2 \
    env -u XDG_RUNTIME_DIR -u MIRROR_RERANK_LOCK TMPDIR="$SCRATCH/tmpfb" bash "$SCRIPT" run
assert_err_contains "the refusal says why, so it is not mistaken for a usage error" "refusing" \
    env -u XDG_RUNTIME_DIR -u MIRROR_RERANK_LOCK TMPDIR="$SCRATCH/tmpfb" bash "$SCRIPT" run
assert_false "reflector was not invoked after the refused fallback" test -e "$REFLECTOR_ARGS"

# ---------------------------------------------------------------------------
# The zsh side: _ask_yn, the mirror hook, and the weekly sync check's guard,
# each extracted from the tracked .zshrc and driven in isolation. Non-interactive
# checks run under plain `zsh -c`; prompt checks run under a pseudo-terminal,
# because zsh's `read -k` reads the terminal, not stdin. ZDOTDIR points at an
# empty directory so the real rc files stay out.
# ---------------------------------------------------------------------------
ZSHRC="${MIRROR_RERANK_ZSHRC:-$REPO_ROOT/home/.zshrc}"
# Exported: the missing-script scenarios re-declare pty_run inside `env ... bash -c`.
export HOOK="$SCRATCH/hook.zsh"
export SYNC="$SCRATCH/sync.zsh"
export ASKYN="$SCRATCH/askyn.zsh"
sed -n '/^_ask_yn() {/,/^}/p' "$ZSHRC" > "$ASKYN"
{ cat "$ASKYN"; sed -n '/^_mirror_rerank_check() {/,/^}/p' "$ZSHRC"; } > "$HOOK"
{ cat "$ASKYN"; sed -n '/^_settings_sync_check() {/,/^}/p' "$ZSHRC"; } > "$SYNC"
export ZDOTDIR="$SCRATCH/zdot"
mkdir -p "$ZDOTDIR"
# An empty .zshrc, or `zsh -i` runs zsh-newuser-install and its menu swallows
# the keystroke meant for the hook's prompt.
: > "$ZDOTDIR/.zshrc"
export MIRROR_RERANK_BIN="$SCRIPT"
# The sync check hardcodes $HOME/Documents/Projects/system_settings/.last_sync;
# a scratch HOME with a stale stamp (epoch 0) makes it want to prompt, without
# a sync.sh to run and without ever reading the real stamp.
export STALE_HOME="$SCRATCH/home"
mkdir -p "$STALE_HOME/Documents/Projects/system_settings"
printf '0\n' > "$STALE_HOME/Documents/Projects/system_settings/.last_sync"

# pty_cmd <zsh-command> : run it in an interactive zsh under a pseudo-terminal,
# feeding <keys> only after the prompt has had time to render -- the hook must
# ignore anything typed before it. Prints the terminal transcript. The timeout
# turns a prompt that blocks forever into one failed assertion, not a hung
# suite: script does not pass the pipe's EOF to the terminal, so an unanswered
# read would wait indefinitely.
pty_cmd() {
    local keys="$1" cmd="$2"
    { sleep 1.5; printf '%s' "$keys"; sleep 0.5; } \
        | timeout 20 script -qec "zsh -i -c '$cmd'" /dev/null 2>/dev/null
}
# pty_cmd_typeahead : <keys> arrive before zsh even starts, as a user typing
# while the terminal opens, and Enter follows once the prompt is up -- the
# realistic sequence, and the one that must not be read as a yes.
pty_cmd_typeahead() {
    local keys="$1" cmd="$2"
    { printf '%s' "$keys"; sleep 1.5; printf '\n'; sleep 0.5; } \
        | timeout 20 script -qec "zsh -i -c '$cmd'" /dev/null 2>/dev/null
}
HOOK_CMD="source \"$HOOK\"; _mirror_rerank_check; print SENTINEL_AFTER_HOOK"
export HOOK_CMD
pty_run()       { pty_cmd "$1" "$HOOK_CMD"; }
pty_typeahead() { pty_cmd_typeahead "$1" "$HOOK_CMD"; }
ASK_CMD="source \"$ASKYN\"; if _ask_yn \"Question? [y/N] \"; then print ANSWER_YES; else print ANSWER_NO; fi; print SENTINEL_AFTER_ASK"
pty_ask()           { pty_cmd "$1" "$ASK_CMD"; }
pty_ask_typeahead() { pty_cmd_typeahead "$1" "$ASK_CMD"; }
SYNC_CMD="source \"$SYNC\"; _settings_sync_check; print SENTINEL_AFTER_SYNC"
pty_sync() {
    { sleep 1.5; printf '%s' "$1"; sleep 0.5; } \
        | timeout 20 script -qec "env HOME=\"$STALE_HOME\" zsh -i -c '$SYNC_CMD'" /dev/null 2>/dev/null
}
hook_noninteractive()      { zsh -c "source \"$HOOK\"; _mirror_rerank_check; print rc=\$?"; }
# Interactive forced on, but stdin is a pipe, not a terminal: the guard's
# mixed case, and the one that keeps a blocking read out of automation.
hook_interactive_no_tty()  { printf '' | zsh -i -c "source \"$HOOK\"; _mirror_rerank_check; print rc=\$?"; }
sync_noninteractive()      { env HOME="$STALE_HOME" zsh -c "source \"$SYNC\"; _settings_sync_check; print rc=\$?"; }
sync_interactive_no_tty()  { printf '' | env HOME="$STALE_HOME" zsh -i -c "source \"$SYNC\"; _settings_sync_check; print rc=\$?"; }

echo "== _ask_yn is defined once and used by every prompt =="
assert_true "_ask_yn is defined"                          grep -q '^_ask_yn() {' "$ZSHRC"
assert_true "the mirror hook asks through _ask_yn"        bash -c "grep -A40 '^_mirror_rerank_check() {' '$ZSHRC' | grep -q '_ask_yn'"
assert_true "the sync check asks through _ask_yn"         bash -c "grep -A40 '^_settings_sync_check() {' '$ZSHRC' | grep -q '_ask_yn'"
# The claude() and codex() account pickers keep their own [1]/[2] read; the
# y/N reads are what _ask_yn owns, so exactly one of those remains.
assert_out  "no inline y/N read remains in .zshrc outside _ask_yn" "1" bash -c "grep -c 'read -r -k 1 answer' '$ZSHRC'"

echo "== _ask_yn: y is yes, everything else is no, typed-ahead keys are ignored =="
assert_contains "y answers yes"                    "ANSWER_YES" pty_ask y
assert_contains "n answers no"                     "ANSWER_NO"  pty_ask n
assert_contains "Enter answers no"                 "ANSWER_NO"  pty_ask $'\n'
assert_contains "a y typed before the prompt is discarded" "ANSWER_NO" pty_ask_typeahead y
assert_contains "the caller continues after the answer"    "SENTINEL_AFTER_ASK" pty_ask n

echo "== the hook is defined in .zshrc and called after the sync check, before fastfetch =="
assert_true "the hook function is defined"  grep -q '^_mirror_rerank_check() {' "$ZSHRC"
assert_true "the hook is called at startup" grep -q '^_mirror_rerank_check$'    "$ZSHRC"
assert_true "the call sits between _settings_sync_check and fastfetch" \
    bash -c "sed -n '/^_settings_sync_check\$/,/^fastfetch\$/p' '$ZSHRC' | grep -q '^_mirror_rerank_check\$'"

echo "== non-interactive shells never see the prompt and never block =="
reset_run
assert_out "sourced in a non-interactive zsh, the hook returns 0 and prints nothing" "rc=0" hook_noninteractive
assert_false "no re-rank was started from a non-interactive shell" test -e "$REFLECTOR_ARGS"
assert_true  "state unchanged after the non-interactive call" state_ranked_at_is "$STALE"

echo "== an interactive shell without a terminal on stdin never sees the prompt either =="
reset_run
assert_out   "interactive but no TTY: the hook returns 0 and prints nothing" "rc=0" hook_interactive_no_tty
assert_false "no re-rank was started from the interactive-no-TTY shell" test -e "$REFLECTOR_ARGS"

echo "== an interactive terminal with the flag armed sees the reasons, the cost, and the prompt =="
reset_run
export STUB_TZ=Europe/Helsinki
assert_contains "the banner names the recorded zone" "Asia/Dubai"          pty_run n
assert_contains "the banner names the live zone"     "Europe/Helsinki"     pty_run n
assert_contains "the banner names the age"           "31 days"             pty_run n
assert_contains "the banner names the cost"          "MB"                  pty_run n
assert_contains "the prompt is asked"                "Update mirrors now?" pty_run n

echo "== answering n leaves the flag armed and starts nothing =="
reset_run
pty_run n >/dev/null
assert_false "no re-rank was started after n" test -e "$REFLECTOR_ARGS"
assert_true  "state unchanged after n"         state_ranked_at_is "$STALE"

echo "== pressing Enter at the prompt is not a yes =="
reset_run
pty_run $'\n' >/dev/null
assert_false "no re-rank was started after Enter" test -e "$REFLECTOR_ARGS"
assert_true  "state unchanged after Enter"         state_ranked_at_is "$STALE"

echo "== answering y runs the re-rank and clears the flag =="
reset_run
pty_run y >/dev/null
assert_true "reflector was invoked after y"      test -e "$REFLECTOR_ARGS"
assert_true "state updated after a successful y" state_ranked_at_is "$NOW"

echo "== a y typed before the prompt appeared is not an answer =="
reset_run
typeahead_out="$(pty_typeahead y)"
[[ "$typeahead_out" == *SENTINEL_AFTER_HOOK* ]] \
    && pass "the hook returned normally after discarding the buffered y" \
    || fail "the hook did not return after the buffered y (transcript: '$typeahead_out')"
assert_false "a buffered y did not start a re-rank" test -e "$REFLECTOR_ARGS"
assert_true  "state unchanged after the buffered y"  state_ranked_at_is "$STALE"

echo "== Ctrl-C at the prompt dismisses it and the rest of .zshrc still runs =="
reset_run
assert_contains "the line after the hook call still executes after Ctrl-C" "SENTINEL_AFTER_HOOK" pty_run $'\003'
assert_false    "no re-rank was started by Ctrl-C" test -e "$REFLECTOR_ARGS"
assert_true     "state unchanged after Ctrl-C"      state_ranked_at_is "$STALE"

echo "== an interactive terminal with the flag disarmed sees no prompt =="
reset_run
write_state Asia/Dubai $((NOW - 1 * DAY))
assert_not_contains "no prompt when fresh" "Update mirrors now?" pty_run n
assert_not_contains "no banner when fresh" "[mirrors]"           pty_run n

echo "== a missing or broken script is reported once, never mistaken for disarmed =="
reset_run
assert_contains     "a missing script is reported"        "not being checked"  env MIRROR_RERANK_BIN="$SCRATCH/no-such-script" bash -c "$(declare -f pty_cmd pty_run); pty_run n"
assert_not_contains "a missing script does not prompt"    "Update mirrors now?" env MIRROR_RERANK_BIN="$SCRATCH/no-such-script" bash -c "$(declare -f pty_cmd pty_run); pty_run n"
export STUB_TZ_FAIL=1
assert_contains     "a script exiting 2 is reported"      "not being checked"  pty_run n
assert_not_contains "a script exiting 2 does not prompt"  "Update mirrors now?" pty_run n
unset STUB_TZ_FAIL

echo "== the weekly sync check is guarded the same way: silent off a terminal, survives Ctrl-C =="
assert_out      "a stale stamp in a non-interactive zsh: returns 0, prints nothing" "rc=0" sync_noninteractive
assert_out      "a stale stamp in an interactive shell with no TTY: returns 0, prints nothing" "rc=0" sync_interactive_no_tty
assert_contains "on a terminal a stale stamp still prompts"         "Run sync now?"       pty_sync n
assert_contains "answering n returns and the rest of .zshrc runs"   "SENTINEL_AFTER_SYNC" pty_sync n
assert_contains "Ctrl-C at the sync prompt returns and the rest of .zshrc runs" "SENTINEL_AFTER_SYNC" pty_sync $'\003'

echo "== the tzupdate wrapper and its header are gone =="
assert_false "no tzupdate function definition remains" grep -q '^tzupdate() {' "$ZSHRC"
assert_false "no Timezone update header remains"       grep -q 'Timezone update' "$ZSHRC"

echo
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
