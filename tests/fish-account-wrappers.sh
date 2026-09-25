#!/bin/bash
# Tests for the fish ports of the claude/codex account wrappers
# (home/.config/fish/functions/{claude,codex}.fish), which must behave like the
# claude()/codex() functions in home/.zshrc: --own/--fna pick the account, the
# project directory picks it otherwise, and outside a project a one-key prompt
# asks, FNA by default.
#
# The real claude and codex are replaced by stubs on PATH that print the config
# directory they were given and each argument on its own line, so the suite
# never starts either CLI. HOME points into a mktemp scratch.
#
# Needs fish. Run: bash tests/fish-account-wrappers.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FUNCS="$REPO_ROOT/home/.config/fish/functions"
FAILED=0

if ! command -v fish >/dev/null 2>&1; then
    echo "cannot run: fish is not installed on this machine (install fish, or run this on the CachyOS laptop)" >&2
    exit 1
fi

fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }
pass() { echo "  ok: $*"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
export HOME="$SCRATCH/home"
NEUTRAL="$HOME/elsewhere"
OWN_REPO="$HOME/Documents/Projects/ActiveProjects/OWN/some-repo"
OWN_ROOT="$HOME/Documents/Projects/ActiveProjects/OWN"
FNA_REPO="$HOME/Documents/Projects/ActiveProjects/FNA/some-repo"
OWNER_DIR="$HOME/Documents/Projects/ActiveProjects/OWNER"
mkdir -p "$NEUTRAL" "$OWN_REPO" "$FNA_REPO" "$OWNER_DIR"

STUBBIN="$SCRATCH/bin"
mkdir -p "$STUBBIN"
for cli in claude codex; do
    cat > "$STUBBIN/$cli" <<'STUB'
#!/bin/bash
echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
echo "CODEX_HOME=${CODEX_HOME:-<unset>}"
for a in "$@"; do echo "ARG[$a]"; done
exit "${STUB_EXIT:-0}"
STUB
    chmod +x "$STUBBIN/$cli"
done

# run_fish <function> <dir> <stdin> [args...] -- prints combined output.
# --no-config keeps the machine's own fish config (and any installed copy of
# these functions) out of the run, so only the tracked file is exercised.
run_fish() {
    local fn="$1" dir="$2" input="$3"; shift 3
    printf '%s' "$input" | PATH="$STUBBIN:$PATH" fish --no-config -c \
        'source $argv[1]; cd $argv[2]; or exit 99; '"$fn"' $argv[3..-1]' \
        -- "$FUNCS/$fn.fish" "$dir" "$@" 2>&1
}

assert_has()  { local d="$1" want="$2" out="$3"; if grep -qxF -- "$want" <<<"$out"; then pass "$d"; else fail "$d (missing line: $want)"; echo "$out" | sed 's/^/      | /'; fi; }
assert_lacks() { local d="$1" bad="$2" out="$3"; if grep -qF -- "$bad" <<<"$out"; then fail "$d (unexpected: $bad)"; echo "$out" | sed 's/^/      | /'; else pass "$d"; fi; }

echo "== claude: explicit flags =="
out="$(run_fish claude "$NEUTRAL" "" --own)"
assert_has   "--own uses the OWN config dir"          "CLAUDE_CONFIG_DIR=$HOME/.claude-own" "$out"
assert_has   "--own announces the account"            "Claude: using OWN account" "$out"
assert_has   "permissions flag is added"              "ARG[--dangerously-skip-permissions]" "$out"
assert_lacks "--own is not passed to claude"          "ARG[--own]" "$out"
assert_lacks "no prompt when the flag decides"        "Account: [1]" "$out"

out="$(run_fish claude "$NEUTRAL" "" --fna -p "two words")"
assert_has   "--fna uses the FNA config dir"          "CLAUDE_CONFIG_DIR=$HOME/.claude-fna" "$out"
assert_has   "an argument with a space stays whole"   "ARG[two words]" "$out"
expected_args=$'ARG[--dangerously-skip-permissions]\nARG[-p]\nARG[two words]'
if [[ "$(grep '^ARG\[' <<<"$out")" == "$expected_args" ]]; then pass "arguments keep their order"; else fail "arguments keep their order"; echo "$out" | sed 's/^/      | /'; fi

out="$(run_fish claude "$OWN_REPO" "" --fna)"
assert_has   "a flag beats the project directory"     "CLAUDE_CONFIG_DIR=$HOME/.claude-fna" "$out"

echo "== claude: project directory =="
out="$(run_fish claude "$OWN_REPO" "")"
assert_has   "inside an OWN project -> OWN"           "CLAUDE_CONFIG_DIR=$HOME/.claude-own" "$out"
assert_has   "inside an OWN project announces it"     "Claude: using OWN account" "$out"
assert_lacks "inside a project there is no prompt"    "Account: [1]" "$out"
out="$(run_fish claude "$OWN_ROOT" "")"
assert_has   "the OWN folder itself -> OWN"           "CLAUDE_CONFIG_DIR=$HOME/.claude-own" "$out"
out="$(run_fish claude "$FNA_REPO" "")"
assert_has   "inside an FNA project -> FNA"           "CLAUDE_CONFIG_DIR=$HOME/.claude-fna" "$out"
assert_has   "inside an FNA project announces it"     "Claude: using FNA account" "$out"
out="$(run_fish claude "$OWNER_DIR" "2")"
assert_has   "OWNER is not OWN: it prompts"           "Account: [1] FNA (default)  [2] OWN" "$out"

echo "== claude: prompt outside a project =="
out="$(run_fish claude "$NEUTRAL" "2")"
assert_has   "the prompt is shown"                    "Account: [1] FNA (default)  [2] OWN" "$out"
assert_has   "answer 2 -> OWN"                        "CLAUDE_CONFIG_DIR=$HOME/.claude-own" "$out"
out="$(run_fish claude "$NEUTRAL" "1")"
assert_has   "answer 1 -> FNA"                        "CLAUDE_CONFIG_DIR=$HOME/.claude-fna" "$out"
out="$(run_fish claude "$NEUTRAL" $'\n')"
assert_has   "Enter -> FNA (default)"                 "CLAUDE_CONFIG_DIR=$HOME/.claude-fna" "$out"
out="$(run_fish claude "$NEUTRAL" "")"
assert_has   "end of input -> FNA (default)"          "CLAUDE_CONFIG_DIR=$HOME/.claude-fna" "$out"

echo "== claude: exit status =="
STUB_EXIT=3 run_fish claude "$NEUTRAL" "" --own >/dev/null
rc=$?
if (( rc == 3 )); then pass "claude's exit status comes back"; else fail "claude's exit status comes back (got $rc)"; fi

echo "== codex: explicit flags =="
out="$(run_fish codex "$NEUTRAL" "" --own)"
assert_has   "--own uses the OWN codex home"          "CODEX_HOME=$HOME/.codex-own" "$out"
assert_has   "--own announces the account"            "Codex: using OWN account" "$out"
assert_lacks "--own is not passed to codex"           "ARG[--own]" "$out"
assert_lacks "no claude-only flag leaks into codex"   "dangerously" "$out"
out="$(run_fish codex "$NEUTRAL" "" --fna exec "two words")"
assert_has   "--fna uses the FNA codex home"          "CODEX_HOME=$HOME/.codex-fna" "$out"
assert_has   "an argument with a space stays whole"   "ARG[two words]" "$out"

echo "== codex: project directory and prompt =="
out="$(run_fish codex "$FNA_REPO" "")"
assert_has   "inside an FNA project -> FNA"           "CODEX_HOME=$HOME/.codex-fna" "$out"
assert_has   "inside an FNA project announces it"     "Codex: using FNA account" "$out"
out="$(run_fish codex "$OWN_REPO" "")"
assert_has   "inside an OWN project -> OWN"           "CODEX_HOME=$HOME/.codex-own" "$out"
out="$(run_fish codex "$NEUTRAL" "2")"
assert_has   "the prompt is shown"                    "Account: [1] FNA (default)  [2] OWN" "$out"
assert_has   "answer 2 -> OWN"                        "CODEX_HOME=$HOME/.codex-own" "$out"
out="$(run_fish codex "$NEUTRAL" "")"
assert_has   "end of input -> FNA (default)"          "CODEX_HOME=$HOME/.codex-fna" "$out"
STUB_EXIT=4 run_fish codex "$NEUTRAL" "" --fna >/dev/null
rc=$?
if (( rc == 4 )); then pass "codex's exit status comes back"; else fail "codex's exit status comes back (got $rc)"; fi

echo
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
