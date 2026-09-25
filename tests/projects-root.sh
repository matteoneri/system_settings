#!/bin/bash
# Tests for the per-machine projects root: the PROJECTS_ROOT variable, its
# declaration file and the @PROJECTS_ROOT@ placeholder round trip
# (docs/plans/2026-09-25-001-feat-projects-root-variable-plan.md).
#
# Sections are headed "== <area>: <topic> ==". The library sections exercise
# lib/projects-root.sh, each case in a fresh bash that sources it, so no state
# leaks between cases. HOME points into a mktemp scratch and PROJECTS_ROOT is
# unset first, so the machine's own value and config are never read or written.
# The conversion sections check the tracked files in the working tree. The
# sync sections run a copy of sync.sh in scratch repositories and scratch homes;
# they never touch this worktree's git state or the machine's own config.
#
# Run: bash tests/projects-root.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO_ROOT/lib/projects-root.sh"
PASSED=0
FAILED=0

pass() { echo "  ok: $*"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
MACHINE_HOME="$HOME"
export HOME="$SCRATCH/home"
mkdir -p "$HOME"
unset PROJECTS_ROOT
DECL="$HOME/.config/environment.d/50-projects-root.conf"
TOKEN='@PROJECTS_ROOT@'

# run_lib <code> [args...] -- run <code> in a fresh bash that has sourced the
# library, with args as $1...; sets OUT (stdout), ERR (stderr) and RC.
run_lib() {
    local code="$1"; shift
    OUT="$(bash -c 'source "$0" || exit 99; '"$code" "$LIB" "$@" 2>"$SCRATCH/stderr")"
    RC=$?
    ERR="$(<"$SCRATCH/stderr")"
}

show() {
    echo "      status: $RC"
    [[ -n "$OUT" ]] && sed 's/^/      out | /' <<<"$OUT"
    [[ -n "$ERR" ]] && sed 's/^/      err | /' <<<"$ERR"
    return 0
}

expect_rc() {
    if (( RC == $2 )); then pass "$1"; else fail "$1 (status $RC, want $2)"; show; fi
}
expect_out() {
    if [[ "$OUT" == "$2" ]]; then pass "$1"; else fail "$1"; printf '      want: %q\n' "$2"; show; fi
}
expect_has() {  # <desc> <needle> <haystack>
    if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1 (missing: $2)"; sed 's/^/      | /' <<<"$3"; fi
}
expect_lacks() {  # <desc> <needle> <haystack>
    if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1 (unexpected: $2)"; sed 's/^/      | /' <<<"$3"; fi
}
expect_file() {  # <desc> <file> <exact content>
    if [[ -f "$2" ]] && cmp -s "$2" <(printf '%s' "$3"); then
        pass "$1"
    else
        fail "$1"; printf '      want: %q\n' "$3"
        [[ -f "$2" ]] && printf '      got:  %q\n' "$(cat "$2"; printf x)" || echo "      got:  <no file>"
    fi
}
expect_mode() {  # <desc> <file> <octal mode>
    local got; got="$(stat -c '%a' "$2" 2>/dev/null)"
    if [[ "$got" == "$3" ]]; then pass "$1"; else fail "$1 (mode ${got:-<none>}, want $3)"; fi
}

decl() { mkdir -p "${DECL%/*}"; printf '%s' "$1" > "$DECL"; }
nodecl() { rm -f "$DECL"; }

echo "== library: sourcing =="
mkdir -p "$SCRATCH/src"
bash -c '
    before="$(set +o; shopt -p; declare -p PROJECTS_ROOT 2>/dev/null || echo "<unset>"; ls -A "$HOME")"
    source "$0" >"$1" 2>&1 || exit 99
    after="$(set +o; shopt -p; declare -p PROJECTS_ROOT 2>/dev/null || echo "<unset>"; ls -A "$HOME")"
    [[ "$before" == "$after" ]] || { diff <(echo "$before") <(echo "$after"); exit 1; }
' "$LIB" "$SCRATCH/src/output"
RC=$?; OUT=""; ERR=""
expect_rc "sourcing succeeds and leaves options, PROJECTS_ROOT and HOME alone" 0
expect_file "sourcing prints nothing" "$SCRATCH/src/output" ""
run_lib 'declare -F projects_root_declaration_file projects_root_resolve projects_root_fill projects_root_swap projects_root_scan projects_root_scan_placeholder >/dev/null && echo defined'
expect_out "the public functions are defined" "defined"
OUT="$(bash -c 'set -euo pipefail; source "$0"; source "$0"; echo "sourced"' "$LIB" 2>&1)"; RC=$?
expect_out "sourcing twice under set -euo pipefail works" "sourced"
run_lib 'projects_root_declaration_file'
expect_out "the declaration file is resolved against HOME" "$DECL"

echo "== library: resolve from the environment =="
nodecl
mkdir -p "$SCRATCH/x/Work" "$HOME/Projects" "$HOME/Other"
RESOLVE_EXPORTED='export PROJECTS_ROOT="$1"; projects_root_resolve'
run_lib "$RESOLVE_EXPORTED" "$SCRATCH/x/Work/"
expect_rc  "an exported root resolves" 0
expect_out "its trailing slash is stripped" "$SCRATCH/x/Work"
run_lib "$RESOLVE_EXPORTED" "$SCRATCH/x/Work///"
expect_out "every trailing slash is stripped" "$SCRATCH/x/Work"
run_lib "$RESOLVE_EXPORTED" "$SCRATCH/x/./Work//../Work"
expect_out "dot segments and doubled slashes are normalised" "$SCRATCH/x/Work"
run_lib "$RESOLVE_EXPORTED" '${HOME}/Projects'
expect_out "a literal \${HOME} in an exported value expands" "$HOME/Projects"
ln -s "$SCRATCH/x" "$SCRATCH/xlink"
run_lib "$RESOLVE_EXPORTED" "$SCRATCH/xlink/Work"
expect_out "a symlinked root keeps the spelling it was given" "$SCRATCH/xlink/Work"
decl 'PROJECTS_ROOT=${HOME}/Projects'
run_lib "$RESOLVE_EXPORTED" "$SCRATCH/x/Work"
expect_out "an exported value wins over the declaration file" "$SCRATCH/x/Work"
run_lib 'export PROJECTS_ROOT=; projects_root_resolve'
expect_out "an empty export falls back to the declaration file" "$HOME/Projects"
nodecl
run_lib 'set -u; unset HOME; export PROJECTS_ROOT="$1"; projects_root_resolve' "$SCRATCH/x/Work"
expect_out "an unset HOME does not trip set -u" "$SCRATCH/x/Work"

echo "== library: resolve from the declaration file =="
decl $'PROJECTS_ROOT=${HOME}/Projects\n'
run_lib 'projects_root_resolve'
expect_rc  "a declared root resolves" 0
expect_out "\${HOME} expands" "$HOME/Projects"
decl $'PROJECTS_ROOT=$HOME/Projects\n'
run_lib 'projects_root_resolve'
expect_out "\$HOME expands" "$HOME/Projects"
decl $'PROJECTS_ROOT=~/Projects\n'
run_lib 'projects_root_resolve'
expect_out "a leading ~ expands" "$HOME/Projects"
decl $'PROJECTS_ROOT=${HOME}/Projects\n# PROJECTS_ROOT=${HOME}/Other\n;PROJECTS_ROOT=${HOME}/Other\n   # PROJECTS_ROOT=/nowhere\n'
run_lib 'projects_root_resolve'
expect_out "commented-out lines are ignored" "$HOME/Projects"
decl $'PROJECTS_ROOT=${HOME}/Other\nPROJECTS_ROOT=${HOME}/Projects\n'
run_lib 'projects_root_resolve'
expect_out "the last PROJECTS_ROOT= line wins" "$HOME/Projects"
decl $'  PROJECTS_ROOT = "${HOME}/Projects"  \r\n'
run_lib 'projects_root_resolve'
expect_out "whitespace, double quotes and CRLF are stripped as systemd does" "$HOME/Projects"
decl "PROJECTS_ROOT='\${HOME}/Projects'"
run_lib 'projects_root_resolve'
expect_out "single quotes and a missing final newline are handled" "$HOME/Projects"
decl $'OTHER=1\nPROJECTS_ROOT=${HOME}/Projects\nMORE=2\n'
run_lib 'projects_root_resolve'
expect_out "other assignments in the file are skipped" "$HOME/Projects"

echo "== library: resolve failures =="
nodecl
run_lib 'projects_root_resolve'
expect_rc    "no export and no file fails" 1
expect_out   "nothing is printed on stdout" ""
expect_has   "the message names PROJECTS_ROOT" "PROJECTS_ROOT" "$ERR"
expect_has   "the message names the declaration file" "$DECL" "$ERR"
expect_has   "the example line uses the neutral path" 'PROJECTS_ROOT=${HOME}/path/to/projects' "$ERR"
expect_lacks "the example is not the Dell root" "Documents/Projects" "$ERR"
expect_lacks "the example is not the laptop root (~)" "~/Projects" "$ERR"
expect_lacks "the example is not the laptop root (\${HOME})" '{HOME}/Projects' "$ERR"
expect_lacks "the example is not the laptop root (\$HOME)" '$HOME/Projects' "$ERR"
if [[ "$(wc -l <<<"$ERR")" == 1 ]]; then pass "the failure is one message"; else fail "the failure is one message"; show; fi
decl $'NOT_PROJECTS_ROOT=${HOME}/Projects\n# PROJECTS_ROOT=${HOME}/Projects\n'
run_lib 'projects_root_resolve'
expect_rc  "a file without a live PROJECTS_ROOT= line fails" 1
expect_has "... naming the declaration file" "$DECL" "$ERR"

decl $'PROJECTS_ROOT=Projects\n'
run_lib 'projects_root_resolve'
expect_rc  "a relative declared value fails" 1
expect_out "... printing nothing on stdout" ""
expect_has "... naming PROJECTS_ROOT and the value" "PROJECTS_ROOT='Projects'" "$ERR"
expect_has "... naming the declaration file" "$DECL" "$ERR"
expect_has "... with the neutral example line" 'PROJECTS_ROOT=${HOME}/path/to/projects' "$ERR"
nodecl
run_lib "$RESOLVE_EXPORTED" "Projects"
expect_rc  "a relative exported value fails" 1
expect_has "... naming the declaration file" "$DECL" "$ERR"
decl $'PROJECTS_ROOT=~other/Projects\n'
run_lib 'projects_root_resolve'
expect_rc  "~user is not expanded, so it is relative and fails" 1
decl $'PROJECTS_ROOT=$HOMEDIR/Projects\n'
run_lib 'projects_root_resolve'
expect_rc  "\$HOMEDIR is not mistaken for \$HOME" 1
decl $'PROJECTS_ROOT=\n'
run_lib 'projects_root_resolve'
expect_rc  "an empty declared value fails" 1
decl $'PROJECTS_ROOT=${HOME}/Missing\n'
run_lib 'projects_root_resolve'
expect_rc  "an absolute root that does not exist fails" 1
expect_has "... naming the expanded value" "$HOME/Missing" "$ERR"
expect_has "... naming the declaration file" "$DECL" "$ERR"
nodecl
touch "$SCRATCH/plainfile"
run_lib "$RESOLVE_EXPORTED" "$SCRATCH/plainfile"
expect_rc  "a root that is a file, not a directory, fails" 1
run_lib "$RESOLVE_EXPORTED" "/"
expect_rc  "the filesystem root is refused" 1
run_lib "$RESOLVE_EXPORTED" "///"
expect_rc  "slashes alone are refused" 1
run_lib 'set -euo pipefail; r="$(projects_root_resolve)" || echo "caught $?"; echo "still running"'
expect_out "a failure can be caught under set -euo pipefail" $'caught 1\nstill running'

echo "== library: fill =="
F="$SCRATCH/fill"
mkdir -p "$F"
printf 'path = "@PROJECTS_ROOT@/ActiveProjects"\n' > "$F/t1"
run_lib 'projects_root_fill "$1" "$2" -' "/tmp/a b/Work" "$F/t1"
expect_rc  "fill to stdout succeeds" 0
expect_out "a root with a space and another basename survives exactly" 'path = "/tmp/a b/Work/ActiveProjects"'
META='/tmp/r.*[x]+$1\&|@{y}%s/W^o(r)k?'
printf 'a @PROJECTS_ROOT@ b @PROJECTS_ROOT@/c\r\nplain line\r\nend=@PROJECTS_ROOT@' > "$F/t2"
run_lib 'projects_root_fill "$1" "$2" "$3"' "$META" "$F/t2" "$F/out2"
expect_rc   "fill into a file succeeds" 0
expect_file "regex and replacement metacharacters survive; every token, CRLF and the missing final newline too" \
    "$F/out2" "a $META b $META/c"$'\r\nplain line\r\n'"end=$META"
printf 'no token here\n' > "$F/plain"
run_lib 'projects_root_fill /r/Work "$1" -' "$F/plain"
expect_out "a file without the token passes through unchanged" "no token here"
: > "$F/empty"
run_lib 'projects_root_fill /r/Work "$1" "$2"' "$F/empty" "$F/empty-out"
expect_file "an empty file fills to an empty file" "$F/empty-out" ""

chmod 0755 "$F/t1"
run_lib 'umask 022; projects_root_fill /r/Work "$1" "$2"' "$F/t1" "$F/new"
expect_file "a new destination gets the filled content" "$F/new" $'path = "/r/Work/ActiveProjects"\n'
expect_mode "a new destination takes the source mode minus the umask" "$F/new" 755
printf 'old\n' > "$F/existing"
chmod 0600 "$F/existing"
run_lib 'projects_root_fill /r/Work "$1" "$2"' "$F/t1" "$F/existing"
expect_file "an existing destination is replaced" "$F/existing" $'path = "/r/Work/ActiveProjects"\n'
expect_mode "an existing destination keeps its mode" "$F/existing" 600
printf 'old\n' > "$F/target"
ln -s target "$F/link"
run_lib 'projects_root_fill /r/Work "$1" "$2"' "$F/t1" "$F/link"
if [[ -L "$F/link" ]]; then pass "a symlinked destination stays a symlink"; else fail "a symlinked destination stays a symlink"; fi
expect_file "... and its target gets the filled content" "$F/target" $'path = "/r/Work/ActiveProjects"\n'

printf 'keep\n' > "$F/keep"
# A perl stub that writes half its output and then dies stands in for a fill
# that fails midway (disk full, killed); only the rewrite step is replaced.
FAILBIN="$SCRATCH/failbin"
mkdir -p "$FAILBIN"
printf '#!/bin/sh\nprintf half-written\nexit 1\n' > "$FAILBIN/perl"
chmod +x "$FAILBIN/perl"
run_lib 'PATH="$1:$PATH" projects_root_fill /r/Work "$2" "$3"' "$FAILBIN" "$F/t1" "$F/keep"
expect_rc   "a fill that fails midway is reported" 2
expect_has  "... naming the destination" "$F/keep" "$ERR"
expect_file "... leaving the destination as it was" "$F/keep" $'keep\n'
leftovers="$(find "$F" -name '.*')"
if [[ -z "$leftovers" ]]; then pass "no temporary files are left behind"; else fail "no temporary files are left behind: $leftovers"; fi
run_lib 'projects_root_fill /r/Work "$1" "$2"' "$F/missing" "$F/keep"
expect_rc   "a missing source fails" 2
expect_has  "... naming the source" "$F/missing" "$ERR"
expect_file "... leaving the destination untouched" "$F/keep" $'keep\n'
run_lib 'projects_root_fill /r/Work "$1" "$2"' "$F/t1" "$F/no/such/dir/out"
expect_rc   "a destination in a missing directory fails" 2
run_lib 'projects_root_fill "" "$1" "$2"' "$F/t1" "$F/keep"
expect_rc   "an empty root is refused" 2
expect_file "... leaving the destination untouched" "$F/keep" $'keep\n'
run_lib 'projects_root_fill Work "$1" -' "$F/t1"
expect_rc   "a relative root is refused" 2
run_lib 'projects_root_fill /r/Work "$1"' "$F/t1"
expect_rc   "a missing argument is a usage error" 2

echo "== library: swap =="
S="$SCRATCH/swap"
mkdir -p "$S"
# swap_case <desc> <home> <root> <input line> <expected line>
swap_case() {
    printf '%s\n' "$4" > "$S/case"
    run_lib 'HOME="$1" projects_root_swap "$2" "$3" -' "$2" "$3" "$S/case"
    if (( RC == 0 )) && [[ "$OUT" == "$5" ]]; then pass "$1"; else fail "$1"; printf '      want: %q\n' "$5"; show; fi
}
swap_case "absolute form"                    /r /r/Work '/r/Work/x'            "$TOKEN/x"
swap_case "~/ form when the root is under HOME" /r /r/Work '~/Work/x'          "$TOKEN/x"
swap_case "~/ form with a trailing slash on HOME" /r/ /r/Work '~/Work/x'       "$TOKEN/x"
swap_case "inside JSON quotes"               /r /r/Work '{"root": "/r/Work"}'  "{\"root\": \"$TOKEN\"}"
swap_case "at the end of a line"             /r /r/Work 'cd /r/Work'           "cd $TOKEN"
swap_case "before a colon"                   /r /r/Work 'PATH=/r/Work:/bin'    "PATH=$TOKEN:/bin"
swap_case "before a sentence-ending period"  /r /r/Work 'Projects live in ~/Work.' "Projects live in $TOKEN."
swap_case "inside parentheses"               /r /r/Work '(see ~/Work)'         "(see $TOKEN)"
swap_case "several on one line"              /r /r/Work '/r/Work/a ~/Work/b /r/WorkOld' "$TOKEN/a $TOKEN/b /r/WorkOld"
swap_case "sibling /r/WorkOld is untouched"  /r /r/Work '/r/WorkOld/x'         '/r/WorkOld/x'
swap_case "sibling /r/Work2 is untouched"    /r /r/Work '/r/Work2'             '/r/Work2'
swap_case "sibling ~/WorkOld is untouched"   /r /r/Work '~/WorkOld/x'          '~/WorkOld/x'
swap_case "sibling /r/Work.bak is untouched" /r /r/Work '/r/Work.bak'          '/r/Work.bak'
swap_case "sibling /r/Work.d/x is untouched" /r /r/Work '/r/Work.d/x'          '/r/Work.d/x'
swap_case "sibling /r/Work-old is untouched" /r /r/Work '/r/Work-old'          '/r/Work-old'
swap_case "sibling /r/Work_x is untouched"   /r /r/Work '/r/Work_x'            '/r/Work_x'
swap_case "sibling with a non-ASCII letter is untouched" /r /r/Work '/r/Workä/x' '/r/Workä/x'
swap_case "~/ is left alone when the root is not under HOME" /h /r/Work '~/Work/x /r/Work/x' "~/Work/x $TOKEN/x"
swap_case "a regex character in the root is literal" /h /r/W.rk '/r/Wxrk/y /r/W.rk/y' "/r/Wxrk/y $TOKEN/y"
swap_case "a root with a space"              /h '/tmp/a b/Work' '"/tmp/a b/Work/x"' "\"$TOKEN/x\""
swap_case "already swapped text is unchanged" /r /r/Work "$TOKEN/x ~/WorkOld" "$TOKEN/x ~/WorkOld"

mkdir -p "$SCRATCH/real/Work"
ln -s real "$SCRATCH/link"
swap_case "symlink-resolved form"            /h "$SCRATCH/link/Work" "$SCRATCH/real/Work/x" "$TOKEN/x"
swap_case "the given symlinked form as well" /h "$SCRATCH/link/Work" "$SCRATCH/link/Work/x" "$TOKEN/x"
mkdir -p "$SCRATCH/W X"
ln -s "W X" "$SCRATCH/W"
swap_case "the longest spelling wins"        /h "$SCRATCH/W" "$SCRATCH/W X/f" "$TOKEN/f"

printf '/r/Work/x\n' > "$S/inplace"
chmod 0640 "$S/inplace"
run_lib 'HOME=/r projects_root_swap /r/Work "$1" "$1"' "$S/inplace"
expect_rc   "swap in place succeeds" 0
expect_file "... rewriting the file" "$S/inplace" "$TOKEN/x"$'\n'
expect_mode "... keeping its mode" "$S/inplace" 640
printf '/r/Work/y\n' > "$S/inplace"
run_lib 'PATH="$1:$PATH" projects_root_swap /r/Work "$2" "$2"' "$FAILBIN" "$S/inplace"
expect_rc   "a swap in place that fails midway is reported" 2
expect_file "... leaving the file as it was" "$S/inplace" $'/r/Work/y\n'
: > "$S/empty"
run_lib 'projects_root_swap /r/Work "$1" "$2"' "$S/empty" "$S/empty-out"
expect_file "an empty file swaps to an empty file" "$S/empty-out" ""
printf '/r/Work/x\n' > "$S/guard"
for bad in "" "/" "/r/Work/" "Work"; do
    run_lib 'projects_root_swap "$1" "$2" "$2"' "$bad" "$S/guard"
    expect_rc   "root '$bad' is refused" 2
done
expect_file "... and the file is untouched" "$S/guard" $'/r/Work/x\n'
run_lib 'projects_root_swap /r/Work "$1" -' "$S/missing"
expect_rc   "a missing source fails" 2

echo "== library: swap and fill round trip =="
RT="$SCRATCH/rt"
mkdir -p "$RT"
for root in "$SCRATCH/m e.t*a[1]+(x)\$1/Work" "$HOME/Projects"; do
    printf '{"trust": ["%s", "%s/ActiveProjects"]}\r\nsiblings %sOld %s2 %s.bak\r\n# last line %s' \
        "$root" "$root" "$root" "$root" "$root" "$root" > "$RT/orig"
    run_lib 'projects_root_swap "$1" "$2" "$3" && projects_root_fill "$1" "$3" "$4"' \
        "$root" "$RT/orig" "$RT/swapped" "$RT/back"
    expect_rc "swap then fill runs for root $root" 0
    if cmp -s "$RT/orig" "$RT/back"; then pass "... reproducing the original byte for byte"; else fail "... reproducing the original byte for byte"; fi
    run_lib 'projects_root_scan "$1" "$2"' "$root" "$RT/swapped"
    expect_rc "... and the swapped copy passes the scan" 0
done
printf 'dir = "@PROJECTS_ROOT@/x"\n~ @PROJECTS_ROOT@\n' > "$RT/template"
run_lib 'projects_root_fill "$1" "$2" "$3" && projects_root_swap "$1" "$3" "$4"' \
    "$HOME/Projects" "$RT/template" "$RT/filled" "$RT/template-back"
if cmp -s "$RT/template" "$RT/template-back"; then pass "fill then swap reproduces the template"; else fail "fill then swap reproduces the template"; show; fi

echo "== library: scan for the root =="
C="$SCRATCH/scan"
mkdir -p "$C"
# scan_case <desc> <home> <root> <content> <expected status>
scan_case() {
    printf '%s\n' "$4" > "$C/case"
    run_lib 'HOME="$1" projects_root_scan "$2" "$3"' "$2" "$3" "$C/case"
    expect_rc "$1" "$5"
}
scan_case "flags the absolute form"          /r /r/Work '/r/Work/x'        1
scan_case "flags the ~/ form"                /r /r/Work 'cd ~/Work/x'      1
scan_case "flags the \$HOME/ form"           /r /r/Work 'cd $HOME/Work/x'  1
scan_case "flags the \${HOME}/ form"         /r /r/Work 'cd ${HOME}/Work/x' 1
scan_case "flags \$HOME/<rel> at the end of a line" /r /r/Work 'X=$HOME/Work' 1
scan_case "flags \${HOME}/<rel> inside quotes" /r /r/Work '"${HOME}/Work"' 1
scan_case "flags the symlink-resolved form"  /h "$SCRATCH/link/Work" "$SCRATCH/real/Work/x" 1
scan_case "passes a file holding only placeholders" /r /r/Work "$TOKEN/x \"$TOKEN\"" 0
scan_case "passes siblings"                  /r /r/Work '/r/WorkOld $HOME/WorkOld ~/Work2 ${HOME}/Work.bak' 0
scan_case "ignores \$HOME/<rel> when the root is not under HOME" /h /r/Work '$HOME/Work/x' 0
printf 'clean\nclean\r\n~/Work/x\r\n' > "$C/lines"
run_lib 'HOME=/r projects_root_scan /r/Work "$1"' "$C/lines"
expect_rc  "a leak is reported" 1
expect_out "... with its line number and text" "3:~/Work/x"
run_lib 'projects_root_scan /r/Work "$1"' "$C/missing"
expect_rc  "a missing file fails closed, not clean" 2
run_lib 'projects_root_scan "" "$1"' "$C/lines"
expect_rc  "an empty root is refused" 2

echo "== library: scan for the placeholder =="
printf 'a\n%s/x\n' "$TOKEN" > "$C/placeholder"
run_lib 'projects_root_scan_placeholder "$1"' "$C/placeholder"
expect_rc  "a file still holding the placeholder is flagged" 1
expect_out "... with its line number and text" "2:$TOKEN/x"
printf '%sx' "$TOKEN" > "$C/glued"
run_lib 'projects_root_scan_placeholder "$1"' "$C/glued"
expect_rc  "a placeholder followed by a name character is flagged too" 1
printf 'dir = "/r/Work/x"\n' > "$C/filled"
run_lib 'projects_root_scan_placeholder "$1"' "$C/filled"
expect_rc  "a filled file passes" 0
expect_out "... silently" ""
: > "$C/empty"
run_lib 'projects_root_scan_placeholder "$1"' "$C/empty"
expect_rc  "an empty file passes" 0
run_lib 'projects_root_scan_placeholder "$1"' "$C/missing"
expect_rc  "a missing file fails closed, not clean" 2

# ── conversion: the tracked files that cannot read PROJECTS_ROOT ──
# The nine templated files hold the placeholder instead of the root, and the
# credential hooks hold no projects path at all. These checks read only the
# working tree, so they hold on a dirty tree too (after a sync that adds a
# Codex trust entry, say) and never depend on what HEAD happens to contain.
TEMPLATED=(
    home/claude-code/own/settings.json home/claude-code/fna/settings.json
    home/claude-code/own/CLAUDE.md     home/claude-code/fna/CLAUDE.md
    home/codex/own/config.toml         home/codex/fna/config.toml
    home/codex/own/AGENTS.md           home/codex/fna/AGENTS.md
    home/codex/shared/MEMORY.md
)
HOOKS=home/claude-code/hooks
HOOK_FILES=("$HOOKS/protect-credentials.sh" "$HOOKS/protect-credentials.test.sh" "$HOOKS/protected-paths.txt")

count_of() { grep -oF -- "$1" | wc -l; }          # <fixed string>, text on stdin
toml_parses() { python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"; }

echo "== conversion: no literal root is left =="
for f in "${TEMPLATED[@]}" "${HOOK_FILES[@]}"; do
    hits="$(grep -nF -- 'Documents/Projects' "$REPO_ROOT/$f" 2>&1)"
    if (( $? == 1 )); then
        pass "$f names no Documents/Projects"
    else
        fail "$f names no Documents/Projects"; sed 's/^/      | /' <<<"$hits"
    fi
done

echo "== conversion: every templated file carries the placeholder =="
for f in "${TEMPLATED[@]}"; do
    got="$(count_of "$TOKEN" < "$REPO_ROOT/$f")"
    if (( got > 0 )); then
        pass "$f holds $got placeholder(s)"
    else
        fail "$f holds no placeholder; it is templated, so it should"
    fi
done

echo "== conversion: the converted files still parse =="
for f in "${TEMPLATED[@]}"; do
    case "$f" in
        *.json) err="$(jq empty "$REPO_ROOT/$f" 2>&1)" ;;
        *.toml) err="$(toml_parses "$REPO_ROOT/$f" 2>&1)" ;;
        *) continue ;;
    esac
    if (( $? == 0 )); then pass "$f parses"; else fail "$f parses"; sed 's/^/      | /' <<<"$err"; fi
done

echo "== conversion: the credential hooks are tracked =="
for f in "$HOOKS/protect-credentials.sh" "$HOOKS/protect-credentials.test.sh"; do
    if [[ -f "$REPO_ROOT/$f" && -x "$REPO_ROOT/$f" ]]; then pass "$f is tracked and executable"; else fail "$f is tracked and executable"; fi
done
if [[ -f "$REPO_ROOT/$HOOKS/protected-paths.txt" ]]; then pass "$HOOKS/protected-paths.txt is tracked"; else fail "$HOOKS/protected-paths.txt is tracked"; fi
# The hook suite finds the hook and its path list beside itself. Two of its
# cases name /home/<user> literally, so it runs with the machine's HOME; it
# only hands paths to the hook as text and writes nothing.
OUT="$(env -u FNET_PROTECTED_PATHS HOME="$MACHINE_HOME" "$REPO_ROOT/$HOOKS/protect-credentials.test.sh" 2>&1)"
RC=$?; ERR=""
if (( RC == 0 )); then
    pass "the repo copy of protect-credentials.test.sh passes ($(tail -n 1 <<<"$OUT"))"
else
    fail "the repo copy of protect-credentials.test.sh passes (status $RC)"
    grep -E 'FAIL|passed=' <<<"$OUT" | sed 's/^/      | /'
fi

# ── sync: sync.sh stages every output, swaps the root back, stops on a leak ──
# Each case runs sync.sh from a plain copy of the repo files it reads and
# writes, committed in a fresh git repository at <root>/system_settings. It is
# never a copy of this worktree, whose .git file points at the real gitdir. HOME
# is a scratch home seeded as a machine restored with that root would be; every
# live source it lacks is skipped. Stubs first on PATH stand in for pacman and
# log mktemp calls, and a private TMPDIR holds the staging mirror. The machine's
# own /etc and /usr/local/bin files are read, never written.
SY="$SCRATCH/sync"
STUBS="$SY/stubs"
mkdir -p "$STUBS" "$SY/tmp"
cat > "$STUBS/pacman" <<'EOF'
#!/bin/sh
# Lists that differ from the fixture's, so a sync that reaches the repo changes them.
case "$1" in
    -Qe) printf 'zsh\nbash\nparu-bin\n' ;;
    -Qm) printf 'paru-bin\n' ;;
    *) echo "pacman stub: unexpected arguments: $*" >&2; exit 1 ;;
esac
EOF
cat > "$STUBS/mktemp" <<EOF
#!/bin/sh
# Log each call, so a case can tell whether sync got as far as staging.
echo "\$*" >> "$SY/mktemp.log"
exec "$(command -v mktemp)" "\$@"
EOF
chmod +x "$STUBS/pacman" "$STUBS/mktemp"

# sgit <repo> <git args...>: git in a scratch repo, blind to the machine's git config.
sgit() {
    local repo="$1"; shift
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$repo" \
        -c user.name=sync-test -c user.email=sync-test -c commit.gpgsign=false "$@"
}

# make_repo <root>: commit <root>/system_settings as a plain copy of sync.sh,
# lib/ and the trees sync writes. The package lists and the etc/ and usr/
# copies hold fixture text, so a sync that reaches the repo changes them.
make_repo() {
    local repo="$1/system_settings" f
    mkdir -p "$repo"
    cp -R "$REPO_ROOT/sync.sh" "$REPO_ROOT/lib" "$REPO_ROOT/home" "$REPO_ROOT/etc" "$REPO_ROOT/usr" "$repo/"
    for f in explicit aur official; do printf 'fixture\n' > "$repo/packages-$f.txt"; done
    while IFS= read -r -d '' f; do
        printf 'fixture %s\n' "${f#"$repo"/}" > "$f"
    done < <(find "$repo/etc" "$repo/usr" -type f -print0)
    sgit "$repo" init -q && sgit "$repo" add -A && sgit "$repo" commit -qm fixture
}

# reset_repo <repo>: back to the committed fixture.
reset_repo() { sgit "$1" reset -q --hard && sgit "$1" clean -qfdx; }

# fill_to <root> <template> <dest>: install a filled copy, as restore would.
fill_to() {
    mkdir -p "$(dirname "$3")"
    run_lib 'projects_root_fill "$1" "$2" "$3"' "$1" "$2" "$3"
    (( RC == 0 )) || { fail "could not fill $2 for the sync fixture"; show; }
}

# seed_home <home> <root> <repo>: the live files of a machine restored from
# <repo> with projects root <root>: the nine templated files filled in, the
# credential hooks (the FNA copies, with own/ entries linking to them), the two
# tracked fish functions, a real git identity and Claude preferences with
# secret keys. Nothing else exists, so sync skips every other source.
seed_home() {
    local h="$1" root="$2" repo="$3" acct f
    for acct in own fna; do
        fill_to "$root" "$repo/home/claude-code/$acct/CLAUDE.md"     "$h/.claude-$acct/CLAUDE.md"
        fill_to "$root" "$repo/home/claude-code/$acct/settings.json" "$h/.claude-$acct/settings.json"
        fill_to "$root" "$repo/home/codex/$acct/config.toml"         "$h/.codex-$acct/config.toml"
        fill_to "$root" "$repo/home/codex/$acct/AGENTS.md"           "$h/.codex-$acct/AGENTS.md"
    done
    fill_to "$root" "$repo/home/codex/shared/MEMORY.md" "$h/.codex-shared/MEMORY.md"
    mkdir -p "$h/.claude-fna/hooks" "$h/.claude-own/hooks" "$h/.config/fish/functions"
    for f in "$repo/home/claude-code/hooks/"*; do
        cp -p "$f" "$h/.claude-fna/hooks/"
        ln -sfn "$h/.claude-fna/hooks/${f##*/}" "$h/.claude-own/hooks/${f##*/}"
    done
    cp "$repo/home/.config/fish/functions/claude.fish" "$repo/home/.config/fish/functions/codex.fish" \
        "$h/.config/fish/functions/"
    sed -e 's/YOUR_NAME/Real Person/' -e 's/YOUR_EMAIL/real-person-at-host/' \
        "$repo/home/.gitconfig" > "$h/.gitconfig"
    jq '. + {"oauthAccount": {"accountUuid": "secret"}, "userID": "secret"}' \
        "$repo/home/claude-code/own/preferences.json" > "$h/.claude-own/.claude.json"
}

# run_sync <repo> <home> <PROJECTS_ROOT, or "" for none exported>: run the
# repo's sync.sh as that machine; sets OUT (stdout and stderr) and RC.
run_sync() {
    local envs=(HOME="$2" PATH="$STUBS:$PATH" TMPDIR="$SY/tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)
    [[ -n "$3" ]] && envs+=(PROJECTS_ROOT="$3")
    : > "$SY/mktemp.log"
    OUT="$(env -u PROJECTS_ROOT "${envs[@]}" bash "$1/sync.sh" 2>&1)"
    RC=$?
    ERR=""
}

expect_fail() {
    if (( RC != 0 )); then pass "$1"; else fail "$1 (status 0, want non-zero)"; show; fi
}
expect_equal() {  # <desc> <got> <want>
    if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1"; printf '      want: %q\n      got:  %q\n' "$3" "$2"; fi
}
# expect_clean <desc> <repo> [pathspec...]: git status shows no change there.
expect_clean() {
    local desc="$1" repo="$2" st
    shift 2
    st="$(sgit "$repo" status --porcelain --untracked-files=all -- "$@" 2>&1)"
    if [[ -z "$st" ]]; then pass "$desc"; else fail "$desc"; sed 's/^/      | /' <<<"$st"; fi
}
# expect_no_staging <desc>: the private TMPDIR is empty again after a run.
expect_no_staging() {
    local left
    left="$(ls -A "$SY/tmp")"
    if [[ -z "$left" ]]; then pass "$1"; else fail "$1 (left behind: $left)"; rm -rf "${SY:?}/tmp/"*; fi
}
# expect_not_staged <desc>: the run never called mktemp.
expect_not_staged() {
    if [[ ! -s "$SY/mktemp.log" ]]; then pass "$1"; else fail "$1"; sed 's/^/      mktemp | /' "$SY/mktemp.log"; fi
}
expect_absent() {  # <desc> <path>
    if [[ ! -e "$2" && ! -L "$2" ]]; then pass "$1"; else fail "$1 ($2 exists)"; fi
}

# Machine A: root with a space, outside HOME. Machine B: root at ~/Projects,
# as on the laptop, so the ~/, $HOME/ and ${HOME}/ spellings apply too.
ROOT_A="$SY/a b/Work";   HOME_A="$SY/home-a"; REPO_A="$ROOT_A/system_settings"
ROOT_B="$SY/c/Projects"; HOME_B="$SY/c";      REPO_B="$ROOT_B/system_settings"
mkdir -p "$ROOT_A" "$HOME_A" "$ROOT_B"
make_repo "$ROOT_A"
make_repo "$ROOT_B"
seed_home "$HOME_A" "$ROOT_A" "$REPO_A"
seed_home "$HOME_B" "$ROOT_B" "$REPO_B"

echo "== sync: two machines with different roots leave the repo as it was (AE2) =="
run_sync "$REPO_A" "$HOME_A" "$ROOT_A"
expect_rc    "sync succeeds for a root with a space, outside HOME" 0
expect_clean "... leaving home/ as committed: the templated files, hooks and fish functions byte-identical" "$REPO_A" home
expect_lacks "... with the git identity scrubbed in staging" "Real Person" "$(cat "$REPO_A/home/.gitconfig")"
expect_lacks "... and only the allowlisted Claude preferences kept" "oauthAccount" "$(cat "$REPO_A/home/claude-code/own/preferences.json")"
expect_file  "... writing the package lists from pacman" "$REPO_A/packages-explicit.txt" $'bash\nparu-bin\nzsh\n'
expect_file  "... the official list being explicit minus AUR" "$REPO_A/packages-official.txt" $'bash\nzsh\n'
expect_has   "... reporting an absent live source (the i3 config) as skipped" "skip (absent): ~/.config/i3/config" "$OUT"
expect_clean "... and leaving the repo's i3 config as it was" "$REPO_A" home/.config/i3/config
expect_absent "... never copying the own/ hook links" "$REPO_A/home/claude-code/own/hooks"
expect_no_staging "... and removing its staging mirror"
run_sync "$REPO_B" "$HOME_B" "$ROOT_B"
expect_rc    "sync succeeds on a second machine whose root is ~/Projects" 0
expect_clean "... again leaving home/ as committed" "$REPO_B" home
differ=""
for f in "${TEMPLATED[@]}"; do cmp -s "$REPO_A/$f" "$REPO_B/$f" || differ+=" $f"; done
if [[ -z "$differ" ]]; then pass "both machines leave the same templated bytes: no flip-flop"; else fail "the machines' templated copies differ:$differ"; fi

echo "== sync: the root can come from the declaration file =="
reset_repo "$REPO_B"
mkdir -p "$HOME_B/.config/environment.d"
printf 'PROJECTS_ROOT=${HOME}/Projects\n' > "$HOME_B/.config/environment.d/50-projects-root.conf"
run_sync "$REPO_B" "$HOME_B" ""
expect_rc    "sync resolves a declared root when none is exported" 0
expect_clean "... and leaves home/ as committed" "$REPO_B" home
rm "$HOME_B/.config/environment.d/50-projects-root.conf"

echo "== sync: live edits reach the repo with the root swapped back (R9) =="
reset_repo "$REPO_B"
printf 'New: %s/ActiveProjects/OWN/new and ~/Projects/x.\n' "$ROOT_B" >> "$HOME_B/.claude-fna/CLAUDE.md"
jq --arg d "$ROOT_B/extra" '.extraRoot = $d' "$HOME_B/.claude-own/settings.json" > "$SY/settings.tmp"
mv "$SY/settings.tmp" "$HOME_B/.claude-own/settings.json"
printf '\n[projects."%s/ActiveProjects/OWN/new"]\ntrust_level = "trusted"\n' "$ROOT_B" >> "$HOME_B/.codex-own/config.toml"
printf '~/.extra-secret\n' >> "$HOME_B/.claude-fna/hooks/protected-paths.txt"
run_sync "$REPO_B" "$HOME_B" "$ROOT_B"
expect_rc "sync succeeds" 0
expect_equal "an absolute and a ~/ path in CLAUDE.md both become the placeholder" \
    "$(tail -n 1 "$REPO_B/home/claude-code/fna/CLAUDE.md")" "New: $TOKEN/ActiveProjects/OWN/new and $TOKEN/x."
expect_equal "a path added to settings.json becomes the placeholder after the jq filter" \
    "$(jq -r .extraRoot "$REPO_B/home/claude-code/own/settings.json")" "$TOKEN/extra"
expect_has "a new Codex trust entry is stored with the placeholder" \
    "[projects.\"$TOKEN/ActiveProjects/OWN/new\"]" "$(cat "$REPO_B/home/codex/own/config.toml")"
expect_equal "a changed hook path list reaches the repo" \
    "$(tail -n 1 "$REPO_B/home/claude-code/hooks/protected-paths.txt")" "~/.extra-secret"
expect_equal "no file in the repo holds the machine's root" \
    "$(grep -rlF --exclude-dir=.git -- "$ROOT_B" "$REPO_B")" ""
reset_repo "$REPO_B"
seed_home "$HOME_B" "$ROOT_B" "$REPO_B"

echo "== sync: only the three tracked fish files are copied (KTD14) =="
reset_repo "$REPO_A"
mkdir -p "$HOME_A/.config/fish/conf.d"
printf 'function extra\nend\n' > "$HOME_A/.config/fish/functions/extra.fish"
printf '# projects-root loader\n' > "$HOME_A/.config/fish/conf.d/projects-root.fish"
printf '# other\n' > "$HOME_A/.config/fish/conf.d/other.fish"
run_sync "$REPO_A" "$HOME_A" "$ROOT_A"
expect_rc     "sync succeeds" 0
expect_file   "the fish projects-root loader is copied" "$REPO_A/home/.config/fish/conf.d/projects-root.fish" $'# projects-root loader\n'
expect_absent "an extra fish function is not" "$REPO_A/home/.config/fish/functions/extra.fish"
expect_absent "nor another conf.d file" "$REPO_A/home/.config/fish/conf.d/other.fish"
rm "$HOME_A/.config/fish/functions/extra.fish" "$HOME_A/.config/fish/conf.d/other.fish" \
    "$HOME_A/.config/fish/conf.d/projects-root.fish"

echo "== sync: a leak stops the sync with the repo untouched (AE3, R10) =="
reset_repo "$REPO_A"
printf 'export WORK="%s/ActiveProjects"\n' "$ROOT_A" > "$HOME_A/.zshrc"
run_sync "$REPO_A" "$HOME_A" "$ROOT_A"
expect_fail  "a live .zshrc holding the literal root stops the sync"
expect_has   "... naming the live .zshrc" "~/.zshrc" "$OUT"
expect_clean "... leaving the whole repo as committed" "$REPO_A"
expect_file  "... the package lists included" "$REPO_A/packages-explicit.txt" $'fixture\n'
expect_clean "... and etc/ and usr/local/bin/" "$REPO_A" etc usr
expect_no_staging "... and removing its staging mirror"
rm "$HOME_A/.zshrc"
printf 'See ${HOME}/Projects/notes.\n' >> "$HOME_B/.claude-fna/CLAUDE.md"
run_sync "$REPO_B" "$HOME_B" "$ROOT_B"
expect_fail  "a templated file holding a spelling the swap leaves (\${HOME}/) stops the sync"
expect_has   "... naming that file" "~/.claude-fna/CLAUDE.md" "$OUT"
expect_clean "... leaving the repo as committed" "$REPO_B"
seed_home "$HOME_B" "$ROOT_B" "$REPO_B"

echo "== sync: a live templated file restore never filled in is refused (KTD8) =="
cp "$REPO_A/home/claude-code/own/settings.json" "$HOME_A/.claude-own/settings.json"
run_sync "$REPO_A" "$HOME_A" "$ROOT_A"
expect_fail  "a live settings.json still holding $TOKEN stops the sync"
expect_has   "... naming the file" "~/.claude-own/settings.json" "$OUT"
expect_has   "... and telling the user to run restore" "restore.sh" "$OUT"
expect_clean "... leaving the repo as committed" "$REPO_A"
expect_no_staging "... and removing its staging mirror"

echo "== sync: the settings.json jq filter fails the run =="
printf '{"permissions": ' > "$HOME_A/.claude-own/settings.json"
run_sync "$REPO_A" "$HOME_A" "$ROOT_A"
expect_fail  "invalid JSON in a live settings.json stops the sync"
expect_has   "... naming the file" "~/.claude-own/settings.json" "$OUT"
expect_clean "... leaving the repo, its settings.json included, as committed" "$REPO_A"
expect_no_staging "... and removing its staging mirror"
fill_to "$ROOT_A" "$REPO_A/home/claude-code/own/settings.json" "$HOME_A/.claude-own/settings.json"
jq 'del(.permissions.deny)' "$HOME_A/.claude-own/settings.json" > "$SY/settings.tmp"
mv "$SY/settings.tmp" "$HOME_A/.claude-own/settings.json"
run_sync "$REPO_A" "$HOME_A" "$ROOT_A"
expect_rc "a settings.json without a deny list still syncs: the filter has nothing to drop" 0
expect_equal "... and reaches the repo" "$(jq -c '.permissions.deny' "$REPO_A/home/claude-code/own/settings.json")" "null"
reset_repo "$REPO_A"
seed_home "$HOME_A" "$ROOT_A" "$REPO_A"

echo "== sync: an unresolved root stops before anything is staged (R4) =="
run_sync "$REPO_A" "$HOME_A" ""
expect_fail  "no exported and no declared root stops the sync"
expect_has   "... naming PROJECTS_ROOT" "PROJECTS_ROOT" "$OUT"
expect_has   "... and the declaration file" "$HOME_A/.config/environment.d/50-projects-root.conf" "$OUT"
expect_not_staged "... before creating the staging mirror"
expect_clean "... leaving the repo as committed" "$REPO_A"

echo "== sync: a root that does not contain the repo is refused (KTD4) =="
mkdir -p "$SY/elsewhere"
run_sync "$REPO_A" "$HOME_A" "$SY/elsewhere"
expect_fail  "an existing root without the repo below it stops the sync"
expect_has   "... naming the repo" "$REPO_A" "$OUT"
expect_has   "... and the root" "$SY/elsewhere" "$OUT"
expect_not_staged "... before copying anything"
expect_clean "... leaving the repo as committed" "$REPO_A"

echo
echo "Passed: $PASSED, failed: $FAILED"
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
