#!/bin/bash
# Tests for data saving mode (docs/plans/2026-09-14-001-feat-data-saving-mode-plan.md).
#
# Exercises the pure functions of datasave-status and datasave-toggle by sourcing
# them behind their BASH_SOURCE guard, with every external effect stubbed:
# SYSTEMCTL and NMCLI are overridable, and DATASAVE_STATE points at a temporary
# file, so the suite never starts or stops a real service and never touches the
# live mode state.
#
# Run: bash tests/datasave-mode.sh

# Default to the copy tracked in this repo, not the one installed on the
# machine, so the test exercises what a reviewer is reading.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATUS="${DATASAVE_STATUS_SCRIPT:-$REPO_ROOT/home/.config/i3/scripts/datasave-status}"
TOGGLE="${DATASAVE_TOGGLE_SCRIPT:-$REPO_ROOT/home/.config/i3/scripts/datasave-toggle}"
FAILED=0

fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }
pass() { echo "  ok: $*"; }

# Every test runs against a scratch state file, never the live one.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
export DATASAVE_STATE="$SCRATCH/datasave-state"

# Asserts a command's stdout equals an expected string.
assert_out() {
    local desc="$1" expected="$2"; shift 2
    local actual
    actual="$("$@" 2>/dev/null)"
    if [[ "$actual" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected '$expected', got '$actual')"
    fi
}

assert_true()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
assert_false() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }

state_on()  { : > "$DATASAVE_STATE"; }
state_off() { rm -f "$DATASAVE_STATE"; }

echo "== datasave-status renders both states =="
if source "$STATUS" >/dev/null 2>&1; then
    assert_out "render on prints the on glyph"   "$GLYPH_ON"  render on
    assert_out "render off prints the off glyph" "$GLYPH_OFF" render off
    [[ "$GLYPH_ON" != "$GLYPH_OFF" ]] \
        && pass "the two glyphs differ" \
        || fail "the two glyphs are identical, so the indicator cannot show state"
else
    fail "could not source $STATUS to reach its functions"
fi

echo "== sourcing the status script has no side effects =="
state_off
( source "$STATUS" >/dev/null 2>&1 )
[[ -e "$DATASAVE_STATE" ]] \
    && fail "sourcing created a state file" \
    || pass "sourcing created no state file"

echo "== is-on reflects the state file =="
state_off
assert_false "is-on exits non-zero when the mode is off" bash "$STATUS" is-on
state_on
assert_true  "is-on exits zero when the mode is on" bash "$STATUS" is-on
state_off

echo "== stopped <name> reads the recorded consumers =="
state_on
printf 'pcloud\n' > "$DATASAVE_STATE"
assert_true  "stopped pcloud is true when recorded"        bash "$STATUS" stopped pcloud
assert_false "stopped keyring is false when not recorded"  bash "$STATUS" stopped keyring
assert_false "stopped with no name is rejected"            bash "$STATUS" stopped
state_off
assert_false "stopped pcloud is false when the mode is off" bash "$STATUS" stopped pcloud

echo "== record and clear maintain the state file =="
state_off
bash "$STATUS" record pcloud >/dev/null 2>&1
assert_true "record turns the mode on"          bash "$STATUS" is-on
assert_true "record registers the consumer"     bash "$STATUS" stopped pcloud
bash "$STATUS" record pcloud >/dev/null 2>&1
[[ "$(grep -c '^pcloud$' "$DATASAVE_STATE")" == "1" ]] \
    && pass "recording twice does not duplicate the entry" \
    || fail "recording twice duplicated the entry"
bash "$STATUS" clear >/dev/null 2>&1
assert_false "clear turns the mode off" bash "$STATUS" is-on
[[ -e "$DATASAVE_STATE" ]] \
    && fail "clear left the state file behind" \
    || pass "clear removed the state file"

echo "== the status script follows the repo's CLI convention =="
assert_false "an unknown subcommand exits non-zero" bash "$STATUS" bogus
out="$(bash "$STATUS" bogus 2>&1 >/dev/null)"
[[ "$out" == usage:* ]] \
    && pass "an unknown subcommand prints usage to stderr" \
    || fail "an unknown subcommand printed '$out' instead of a usage line"
bash "$STATUS" bogus >/dev/null 2>&1
[[ $? -eq 2 ]] \
    && pass "an unknown subcommand exits 2" \
    || fail "an unknown subcommand did not exit 2"

echo
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
