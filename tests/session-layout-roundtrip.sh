#!/bin/bash
# Round-trip test for session-restore's layout synthesis.
# Feeds hand-authored snapshots through `session-restore --plan` and asserts the
# generated i3 layout preserves nesting, container modes, and split ratios, drops
# slots for windows the feature does not restore, and renormalizes their siblings.
#
# Run: bash tests/session-layout-roundtrip.sh

# Default to the copy tracked in this repo, not the one installed on the
# machine, so the test exercises what a reviewer is reading.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESTORE="${RESTORE_SCRIPT:-$REPO_ROOT/home/.config/i3/scripts/session-restore}"
FIXTURES="$(cd "$(dirname "$0")/fixtures" && pwd)"
FAILED=0

fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }
pass() { echo "  ok: $*"; }

# Asserts a jq expression is true against the plan for a fixture+workspace.
assert_jq() {
    local fixture="$1" ws="$2" expr="$3" desc="$4" plan
    plan=$("$RESTORE" --plan "$FIXTURES/$fixture" "$ws" 2>/dev/null)
    if [[ -z "$plan" ]]; then
        fail "$desc (no plan emitted)"
        return
    fi
    if echo "$plan" | jq -e "$expr" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc"
        echo "        plan was: $(echo "$plan" | jq -c . 2>/dev/null || echo "$plan")"
    fi
}

echo "== nesting and container modes survive =="
assert_jq nested.json A '.layout | length == 2' "two top-level containers"
assert_jq nested.json A '.layout[0].layout == "splitv"' "first container keeps splitv"
assert_jq nested.json A '.layout[1].layout == "stacked"' "second container keeps stacked"
assert_jq nested.json A '.layout[0].nodes | length == 2' "splitv holds two slots"
assert_jq nested.json A '.layout[1].nodes | length == 3' "stacked holds three slots"

echo "== ratios survive as proportions =="
assert_jq nested.json A '(.layout[0].percent - 0.25) | fabs < 0.0001' "outer ratio 0.25 preserved"
assert_jq nested.json A '(.layout[1].percent - 0.75) | fabs < 0.0001' "outer ratio 0.75 preserved"
assert_jq nested.json A '[.layout[1].nodes[].percent] | add | (. - 1.0) | fabs < 0.0001' "stacked children sum to 1"

echo "== every slot gets a distinct swallow criterion =="
assert_jq nested.json A '[.. | objects | select(has("swallows")) | .swallows[0].instance] | (length == 5 and (unique | length) == 5)' "five unique instance criteria"
assert_jq nested.json A '[.. | objects | select(has("swallows")) | .swallows[0].instance] | all(test("^\\^[A-Za-z0-9-]+\\$$"))' "criteria are anchored and regex-safe"

echo "== terminals are enumerated with their specs =="
assert_jq nested.json A '.terminals | length == 5' "five terminals"
assert_jq nested.json A '[.terminals[] | select(.agent == "claude")] | length == 1' "one claude terminal"
assert_jq nested.json A '[.terminals[] | select(.agent == "codex")] | length == 1' "one codex terminal"
assert_jq nested.json A '.terminals[0].cwd == "/tmp/fixture-a"' "first terminal keeps its cwd"
assert_jq nested.json A '[.terminals[].instance] | unique | length == 5' "terminal instances are unique"
assert_jq nested.json A '([.terminals[].instance] | sort) == ([.. | objects | select(has("swallows")) | .swallows[0].instance | ltrimstr("^") | rtrimstr("$")] | sort)' "manifest matches the layout criteria"

echo "== unrestorable slots are dropped and siblings renormalized =="
assert_jq mixed.json B '.layout[0].nodes | length == 1' "browser slot dropped from tabbed container"
assert_jq mixed.json B '(.layout[0].nodes[0].percent - 1.0) | fabs < 0.0001' "surviving sibling renormalized to full width"
assert_jq mixed.json B '.terminals | length == 1' "only the terminal is enumerated"
assert_jq mixed.json B '.layout[0].layout == "tabbed"' "container mode still tabbed"

echo "== single-terminal workspace =="
assert_jq single.json C '.layout | length == 1' "one top-level slot"
assert_jq single.json C '.layout[0] | has("swallows")' "top-level leaf becomes a swallow slot"
assert_jq single.json C '.terminals | length == 1' "one terminal"

echo "== a workspace with nothing restorable yields no layout =="
# Must succeed AND emit an empty layout. Accepting empty output would also pass
# if the script crashed and printed nothing.
plan=$("$RESTORE" --plan "$FIXTURES/unrestorable.json" D 2>/dev/null)
rc=$?
if (( rc != 0 )); then
    fail "all-unrestorable workspace should still succeed, exited $rc"
elif echo "$plan" | jq -e '(.layout | length) == 0 and (.terminals | length) == 0' >/dev/null 2>&1; then
    pass "all-unrestorable workspace yields an empty layout, not a crash"
else
    fail "expected an empty layout for an all-unrestorable workspace, got: $plan"
fi

echo "== siblings with no recorded ratio split evenly =="
assert_jq zerosum.json E '.layout[0].nodes | length == 3' "all three terminals kept"
assert_jq zerosum.json E '[.layout[0].nodes[].percent] | add | (. - 1.0) | fabs < 0.0001' "zero-sum siblings renormalized to sum 1"
assert_jq zerosum.json E '[.layout[0].nodes[].percent] | all((. - (1/3)) | fabs < 0.0001)' "split evenly rather than left at zero"

echo "== bad input is rejected with a message, not a silent exit =="
for bad in "$FIXTURES/malformed.json:X:malformed snapshot" "$FIXTURES/does-not-exist.json:X:missing snapshot file" "$FIXTURES/single.json:NO_SUCH_WS:unknown workspace name"; do
    path=${bad%%:*}; rest=${bad#*:}; ws=${rest%%:*}; desc=${rest#*:}
    err=$("$RESTORE" --plan "$path" "$ws" 2>&1 >/dev/null)
    rc=$?
    if (( rc == 0 )); then
        fail "$desc should exit non-zero"
    elif [[ -z "$err" ]]; then
        fail "$desc exited non-zero but said nothing"
    else
        pass "$desc rejected with a message"
    fi
done

echo "== input validators reject what they are meant to =="
# Sourcing exposes the helpers without running a restore.
# shellcheck disable=SC1090
if source "$RESTORE" >/dev/null 2>&1; then
    assert_true()  { if "$@" >/dev/null 2>&1; then pass "accepts: ${*:2}"; else fail "should accept: ${*:2}"; fi; }
    assert_false() { if "$@" >/dev/null 2>&1; then fail "should reject: ${*:2}"; else pass "rejects: ${*:2}"; fi; }
    assert_true  valid_workspace_name "2"
    assert_true  valid_workspace_name "10:󰍡"
    assert_false valid_workspace_name 'a"b'
    assert_false valid_workspace_name 'a;exec evil'
    assert_false valid_workspace_name ""
    assert_true  valid_session_id "6cd56b4f-6031-410a-b6ba-4f868099fab7"
    assert_false valid_session_id "not-a-uuid"
    assert_false valid_session_id ""
    assert_true  valid_cwd "/tmp"
    assert_false valid_cwd "tmp"
    assert_false valid_cwd "/nonexistent-$$"
    assert_true  valid_config_dir "$HOME/.claude-fna"
    assert_false valid_config_dir "/etc"
else
    fail "could not source $RESTORE to reach the validators"
fi

echo "== the tracked copy matches the installed one =="
# The plan's sync-fidelity gate, mechanised: sync.sh copies live -> repo, so a
# live edit that was never synced would leave the tracked copy behind.
if [[ -n "${RESTORE_SCRIPT:-}" ]]; then
    pass "skipped — RESTORE_SCRIPT was set explicitly"
else
    drift=0
    for rel in .config/i3/scripts/session-restore .config/i3/scripts/session-snapshot; do
        if [[ -e "$HOME/$rel" ]] && ! diff -q "$HOME/$rel" "$REPO_ROOT/home/$rel" >/dev/null 2>&1; then
            fail "tracked copy of $rel differs from the installed one — run sync.sh"
            drift=1
        fi
    done
    (( drift == 0 )) && pass "tracked and installed copies match"
fi

echo "== fixtures carry no real paths or identifiers =="
if rg -q "/home/" "$FIXTURES" 2>/dev/null; then
    fail "a fixture contains a real home path"
else
    pass "no home paths in fixtures"
fi
if rg -o "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" "$FIXTURES" 2>/dev/null | rg -qv "00000000-0000-0000-0000-0000000000"; then
    fail "a fixture contains a non-synthetic session id"
else
    pass "session ids are synthetic"
fi

echo
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
