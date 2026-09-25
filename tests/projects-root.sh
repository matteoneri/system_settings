#!/bin/bash
# Tests for the per-machine projects root: the PROJECTS_ROOT variable, its
# declaration file and the @PROJECTS_ROOT@ placeholder round trip
# (docs/plans/2026-09-25-001-feat-projects-root-variable-plan.md).
#
# Sections are headed "== <area>: <topic> ==". The library sections exercise
# lib/projects-root.sh, each case in a fresh bash that sources it, so no state
# leaks between cases. HOME points into a mktemp scratch and PROJECTS_ROOT is
# unset first, so the machine's own value and config are never read or written.
# The conversion sections check the tracked files in the working tree.
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

echo
echo "Passed: $PASSED, failed: $FAILED"
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
