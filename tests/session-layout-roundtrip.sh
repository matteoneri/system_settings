#!/bin/bash
# Round-trip test for session-restore's layout synthesis.
# Feeds hand-authored snapshots through `session-restore --plan` and asserts the
# generated i3 layout preserves nesting, container modes, and split ratios, drops
# slots for windows the feature does not restore, and renormalizes their siblings.
#
# Run: bash tests/session-layout-roundtrip.sh

RESTORE="${RESTORE_SCRIPT:-$HOME/.config/i3/scripts/session-restore}"
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
plan=$("$RESTORE" --plan "$FIXTURES/unrestorable.json" D 2>/dev/null)
if [[ -z "$plan" ]] || echo "$plan" | jq -e '(.layout | length) == 0' >/dev/null 2>&1; then
    pass "no layout emitted for an all-unrestorable workspace"
else
    fail "expected no layout for an all-unrestorable workspace, got: $plan"
fi

echo "== malformed snapshot is rejected, not partially planned =="
if "$RESTORE" --plan "$FIXTURES/malformed.json" X >/dev/null 2>&1; then
    fail "malformed snapshot should exit non-zero"
else
    pass "malformed snapshot rejected"
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
