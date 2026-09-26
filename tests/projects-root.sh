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
# sync and restore sections run a copy of sync.sh or restore.sh in scratch
# repositories and scratch homes; they never touch this worktree's git state or
# the machine's own config. The shell sections run the zsh loader extracted
# from home/.zshrc and project-launch, with its externals stubbed, in the same
# scratch homes. The fish loader has its own suite, tests/fish-projects-root.sh.
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
run_lib 'declare -F projects_root_declaration_file projects_root_resolve projects_root_check_repo projects_root_fill projects_root_swap projects_root_scan projects_root_scan_placeholder >/dev/null && echo defined'
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

echo "== library: check the repo is <root>/system_settings =="
K="$SCRATCH/chk"
mkdir -p "$K/w x/Work/system_settings/.worktrees/feat" "$K/w x/Work/other" "$K/w x/Work/system_settings.bak" \
    "$K/home/system_settings"
ln -s "w x" "$K/wlink"
ln -s home "$K/homelink"
CHECK_REPO='projects_root_check_repo "$1" "$2"'
run_lib "$CHECK_REPO" "$K/w x/Work" "$K/w x/Work/system_settings"
expect_rc  "a repo at <root>/system_settings passes, for a root with a space whose basename is not Projects" 0
expect_out "... silently" ""
run_lib "$CHECK_REPO" "$K/w x/Work" "$K/w x/Work/system_settings/.worktrees/feat"
expect_rc  "a git worktree inside <root>/system_settings passes" 0
run_lib "$CHECK_REPO" "$K/wlink/Work" "$K/w x/Work/system_settings"
expect_rc  "a root spelled through a symlink passes: real paths are compared" 0
run_lib "$CHECK_REPO" "$K/w x/Work" "$K/wlink/Work/system_settings/"
expect_rc  "... and so does a repo spelled through one" 0
run_lib "$CHECK_REPO" "$K/w x/Work" "$K/w x/Work/other"
expect_rc    "a repo directly under the root but not named system_settings fails" 1
expect_out   "... printing nothing on stdout" ""
expect_has   "... naming PROJECTS_ROOT and the root" "PROJECTS_ROOT ($K/w x/Work)" "$ERR"
expect_has   "... naming the repo" "$K/w x/Work/other" "$ERR"
expect_has   "... and the expected layout" "<root>/system_settings" "$ERR"
expect_has   "... naming the declaration file" "$DECL" "$ERR"
expect_has   "... with the neutral example line" 'PROJECTS_ROOT=${HOME}/path/to/projects' "$ERR"
expect_lacks "... the example is not the Dell root" "Documents/Projects" "$ERR"
if [[ "$(wc -l <<<"$ERR")" == 1 ]]; then pass "... in one message"; else fail "... in one message"; show; fi
run_lib "$CHECK_REPO" "$K/w x/Work" "$K/w x/Work/system_settings.bak"
expect_rc    "a sibling whose name starts with system_settings fails" 1
run_lib "$CHECK_REPO" "$K/w x" "$K/w x/Work/system_settings"
expect_rc    "the parent of the right root fails" 1
expect_has   "... naming the expected layout" "<root>/system_settings" "$ERR"
run_lib 'HOME="$3" projects_root_check_repo "$1" "$2"' "$K/home" "$K/home/system_settings" "$K/home"
expect_rc    "a root equal to HOME fails, even with the repo at \$HOME/system_settings" 1
expect_has   "... saying the leak scan cannot tell the root from home paths" "leak scan cannot tell" "$ERR"
expect_has   "... naming the declaration file under that HOME" "$K/home/.config/environment.d/50-projects-root.conf" "$ERR"
expect_has   "... with the neutral example line" 'PROJECTS_ROOT=${HOME}/path/to/projects' "$ERR"
if [[ "$(wc -l <<<"$ERR")" == 1 ]]; then pass "... in one message"; else fail "... in one message"; show; fi
run_lib 'HOME="$3" projects_root_check_repo "$1" "$2"' "$K/homelink" "$K/home/system_settings" "$K/home"
expect_rc    "... also when the root spells HOME through a symlink" 1
run_lib 'HOME="$3" projects_root_check_repo "$1" "$2"' "$K/home" "$K/home/system_settings" "$K/homelink/"
expect_rc    "... or HOME is spelled through one" 1
run_lib 'set -u; unset HOME; projects_root_check_repo "$1" "$2"' "$K/w x/Work" "$K/w x/Work/system_settings"
expect_rc    "an unset HOME does not trip set -u, and matches no root" 0
run_lib "$CHECK_REPO" "$K/w x/Work" "$K/missing"
expect_rc    "a repo directory that does not exist is bad input" 2
run_lib "$CHECK_REPO" "Work" "$K/w x/Work/system_settings"
expect_rc    "a relative root is refused" 2
run_lib 'projects_root_check_repo "$1"' "$K/w x/Work"
expect_rc    "a missing argument is a usage error" 2

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

echo "== sync: a filtered glob copies only the files that match =="
mkdir -p "$HOME_A/.config/kitty/themes"
printf 'background #101010\nforeground #e0e0e0\n' > "$HOME_A/.config/kitty/themes/custom.conf"
printf 'not a theme\n' > "$HOME_A/.config/kitty/themes/notes.txt"
run_sync "$REPO_A" "$HOME_A" "$ROOT_A"
expect_rc "sync succeeds with a kitty theme present" 0
if cmp -s "$HOME_A/.config/kitty/themes/custom.conf" "$REPO_A/home/.config/kitty/themes/custom.conf"; then
    pass "... copying the *.conf theme to home/.config/kitty/themes/, byte for byte"
else
    fail "... copying the *.conf theme to home/.config/kitty/themes/, byte for byte"
fi
expect_absent "... and not the sibling that does not match *.conf" "$REPO_A/home/.config/kitty/themes/notes.txt"
rm -r "$HOME_A/.config/kitty"
reset_repo "$REPO_A"

# Root ignores file modes, so the copy cannot be made to fail that way there.
echo "== sync: a final copy that fails partway says the repo may be mixed =="
if (( EUID == 0 )); then
    echo "  skip: running as root, which ignores the read-only mode this case relies on"
else
    chmod 0444 "$REPO_A/packages-aur.txt"
    run_sync "$REPO_A" "$HOME_A" "$ROOT_A"
    chmod 0644 "$REPO_A/packages-aur.txt"
    expect_fail  "a read-only file in the repo fails the sync"
    expect_has   "... saying the copy into the repo failed partway" "failed partway" "$OUT"
    expect_has   "... that the repo may hold a mix of old and new files" "mix of old and new files" "$OUT"
    expect_has   "... how to see what changed" "git -C $(printf '%q' "$REPO_A") status" "$OUT"
    expect_has   "... how to discard the partial copy" "git -C $(printf '%q' "$REPO_A") checkout -- ." "$OUT"
    expect_has   "... and to run sync.sh again once the cause is fixed" "run sync.sh again" "$OUT"
    expect_lacks "... never reporting it done" "Done." "$OUT"
    expect_no_staging "... and removing its staging mirror"
    reset_repo "$REPO_A"
fi

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

echo "== sync: a root above the repo's own, or equal to HOME, is refused =="
run_sync "$REPO_A" "$HOME_A" "$SY/a b"
expect_fail  "the parent of the right root stops the sync"
expect_has   "... naming the expected layout" "<root>/system_settings" "$OUT"
expect_has   "... and saying nothing was synced" "Nothing was synced." "$OUT"
expect_not_staged "... before staging anything"
expect_clean "... leaving the repo as committed" "$REPO_A"
HOME_SH="$SY/home-is-root"
make_repo "$HOME_SH"
run_sync "$HOME_SH/system_settings" "$HOME_SH" "$HOME_SH"
expect_fail  "a root equal to HOME stops the sync, even with the repo at \$HOME/system_settings"
expect_has   "... saying the leak scan cannot tell the root from home paths" "leak scan cannot tell" "$OUT"
expect_has   "... and nothing was synced" "Nothing was synced." "$OUT"
expect_not_staged "... before staging anything"
expect_clean "... leaving the repo as committed" "$HOME_SH/system_settings"

# ── restore: restore.sh resolves the root first, then fills the configs in ──
# Each case runs restore.sh from a plain copy of the repo files it reads,
# committed in a fresh git repository at <root>/system_settings; never a copy
# of this worktree. env -i hands it only HOME (a scratch home), PATH, TMPDIR
# and, when the case sets one, PROJECTS_ROOT; stdin is closed. PATH holds
# logging stubs for every command that would touch the machine and links to
# the plain tools restore needs, with jq in a directory of its own so a case
# can leave it out. Nothing else is on PATH, so a step no stub covers fails
# instead of reaching the machine.
RS="$SCRATCH/restore"
RSTUBS="$RS/stubs"; RTOOLS="$RS/tools"; RJQ="$RS/jq"; CALLS="$RS/calls.log"
mkdir -p "$RSTUBS" "$RTOOLS" "$RJQ" "$RS/tmp"
for tool in sudo pacman paru curl git makepkg chsh xrdb; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$tool" "$CALLS" > "$RSTUBS/$tool"
    chmod +x "$RSTUBS/$tool"
done
for tool in bash sh env cat cp mv rm ln mkdir chmod dirname basename readlink realpath stat mktemp perl python3 sed grep; do
    if [[ -x "/usr/bin/$tool" ]]; then ln -s "/usr/bin/$tool" "$RTOOLS/$tool"; else fail "the restore cases need /usr/bin/$tool"; fi
done
ln -s /usr/bin/jq "$RJQ/jq"

# make_restore_repo <root>: commit <root>/system_settings as a plain copy of
# restore.sh, lib/ and home/, with fixture package lists.
make_restore_repo() {
    local repo="$1/system_settings" f
    mkdir -p "$repo"
    cp -R "$REPO_ROOT/restore.sh" "$REPO_ROOT/lib" "$REPO_ROOT/home" "$repo/"
    for f in official aur; do printf 'fixture\n' > "$repo/packages-$f.txt"; done
    sgit "$repo" init -q && sgit "$repo" add -A && sgit "$repo" commit -qm fixture
}

# run_restore <repo> <home> <PROJECTS_ROOT, or "" for none exported> [args...]:
# run the repo's restore.sh as that machine; sets OUT (stdout and stderr) and
# RC. NOJQ=1 before the call leaves jq off PATH.
run_restore() {
    local repo="$1" home="$2" root="$3" path="$RSTUBS:$RJQ:$RTOOLS"
    shift 3
    [[ -n "${NOJQ-}" ]] && path="$RSTUBS:$RTOOLS"
    local envs=(HOME="$home" PATH="$path" TMPDIR="$RS/tmp")
    [[ -n "$root" ]] && envs+=(PROJECTS_ROOT="$root")
    : > "$CALLS"
    OUT="$(env -i "${envs[@]}" bash "$repo/restore.sh" "$@" 2>&1 </dev/null)"
    RC=$?
    ERR=""
}

fresh_home() { rm -rf -- "$1"; mkdir -p "$1"; }
# expect_empty_home <desc> <home>: the run created nothing there.
expect_empty_home() {
    local left
    left="$(cd "$2" && find . -mindepth 1 | head -n 5)"
    if [[ -z "$left" ]]; then pass "$1"; else fail "$1"; sed 's/^/      created | /' <<<"$left"; fi
}
# expect_no_calls <desc>: the run called no stub (sudo, a package manager, curl...).
expect_no_calls() {
    if [[ ! -s "$CALLS" ]]; then pass "$1"; else fail "$1"; sed 's/^/      call | /' "$CALLS"; fi
}
# expect_filled <desc> <root> <template> <installed>: the installed file is the
# template with every placeholder replaced by the root, byte for byte.
expect_filled() {
    local want got
    want="$(cat -- "$3"; printf x)"; want="${want%x}"; want="${want//"$TOKEN"/"$2"}"
    got="$(cat -- "$4" 2>/dev/null; printf x)"; got="${got%x}"
    if [[ -f "$4" && "$got" == "$want" ]]; then pass "$1"; else fail "$1"; fi
}
expect_link() {  # <desc> <link> <target it must name>
    local got; got="$(readlink -- "$2" 2>/dev/null)"
    if [[ -L "$2" && "$got" == "$3" ]]; then pass "$1"; else fail "$1 (${got:-not a link})"; fi
}
expect_copy() {  # <desc> <repo file> <installed file>: same bytes, and executable when the repo file is
    if [[ -f "$3" ]] && cmp -s "$2" "$3" && { [[ ! -x "$2" ]] || [[ -x "$3" ]]; }; then pass "$1"; else fail "$1"; fi
}
# trust_count <config.toml> <root>: how many lines are exactly the portwatch trust header.
trust_count() { grep -cxF "[projects.\"$2/ActiveProjects/OWN/portwatch\"]" "$1" 2>/dev/null; }
# own_hook <home> <file path>: the own/ hook link, run as Claude Code runs it on a Read.
own_hook() {
    printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$2" \
        | env -u FNET_PROTECTED_PATHS HOME="$1" "$1/.claude-own/hooks/protect-credentials.sh" 2>&1
}

# A root with a space, outside HOME, whose basename is not Projects.
ROOT_R="$RS/a b/Work"; REPO_R="$ROOT_R/system_settings"; HOME_R="$RS/home-r"
mkdir -p "$ROOT_R"
make_restore_repo "$ROOT_R"
CLAUDE_HOOKS=(protect-credentials.sh protect-credentials.test.sh protected-paths.txt)
FISH_FILES=(.config/fish/functions/claude.fish .config/fish/functions/codex.fish .config/fish/conf.d/projects-root.fish)

echo "== restore: --help and --list-components run without a root =="
fresh_home "$HOME_R"
run_restore "$REPO_R" "$HOME_R" "" --list-components
expect_rc    "--list-components succeeds with PROJECTS_ROOT unset" 0
expect_has   "... listing fish as part of --all" "(in --all)" "$(grep -E '^  fish ' <<<"$OUT")"
run_restore "$REPO_R" "$HOME_R" "" --help
expect_rc    "--help succeeds with PROJECTS_ROOT unset" 0
expect_has   "... naming PROJECTS_ROOT" "PROJECTS_ROOT" "$OUT"
expect_has   "... and the fish component" "fish" "$OUT"
expect_has   "... printing the header through its last line" "restore stops before installing or writing anything." "$OUT"
expect_lacks "... and no code" "set -euo pipefail" "$OUT"
expect_empty_home "... and neither creates anything under HOME" "$HOME_R"

echo "== restore: an unresolved root stops before any write (AE4, R4) =="
run_restore "$REPO_R" "$HOME_R" "" --configs --components claude,codex,fish
expect_fail  "no exported and no declared root stops the restore"
expect_has   "... naming PROJECTS_ROOT" "PROJECTS_ROOT" "$OUT"
expect_has   "... and the declaration file" "$HOME_R/.config/environment.d/50-projects-root.conf" "$OUT"
expect_empty_home "... creating nothing under HOME" "$HOME_R"
run_restore "$REPO_R" "$HOME_R" ""
expect_fail  "a bare restore.sh (packages, then every config) stops too"
expect_no_calls "... before the package step runs sudo, pacman or paru"
expect_empty_home "... and before any component writes" "$HOME_R"
expect_clean "... leaving the repo as committed" "$REPO_R"

echo "== restore: a root that does not contain the repo is refused (KTD4) =="
mkdir -p "$RS/elsewhere"
run_restore "$REPO_R" "$HOME_R" "$RS/elsewhere" --configs --components claude,codex,fish
expect_fail  "an existing root without the repo below it stops the restore"
expect_has   "... naming the repo" "$REPO_R" "$OUT"
expect_has   "... and the root" "$RS/elsewhere" "$OUT"
expect_empty_home "... creating nothing under HOME" "$HOME_R"
run_restore "$REPO_R" "$HOME_R" "$RS/elsewhere" --packages
expect_fail  "--packages alone is refused too"
expect_no_calls "... before the package step starts"

echo "== restore: a root above the repo's own, or equal to HOME, is refused =="
fresh_home "$HOME_R"
run_restore "$REPO_R" "$HOME_R" "$RS/a b" --configs --components claude,codex,fish
expect_fail  "the parent of the right root stops the restore"
expect_has   "... naming the expected layout" "<root>/system_settings" "$OUT"
expect_has   "... and saying nothing was restored" "Nothing was restored." "$OUT"
expect_empty_home "... creating nothing under HOME" "$HOME_R"
run_restore "$REPO_R" "$HOME_R" "$RS/a b"
expect_fail  "a bare restore.sh is refused too"
expect_no_calls "... before the package step starts"
expect_empty_home "... or any component writes" "$HOME_R"
HOME_RH="$RS/home-is-root"
make_restore_repo "$HOME_RH"
run_restore "$HOME_RH/system_settings" "$HOME_RH" "$HOME_RH" --configs --components claude,codex,fish
expect_fail  "a root equal to HOME stops the restore, even with the repo at \$HOME/system_settings"
expect_has   "... saying the leak scan cannot tell the root from home paths" "leak scan cannot tell" "$OUT"
expect_has   "... and nothing was restored" "Nothing was restored." "$OUT"
expect_equal "... creating nothing under HOME beside the repo" "$(ls -A "$HOME_RH")" "system_settings"

echo "== restore: claude and codex install their configs with the root filled in (AE1, R8, R11) =="
fresh_home "$HOME_R"
run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components claude,codex
expect_rc "restore claude,codex succeeds for a root with a space, outside HOME" 0
RESTORED="$OUT"
expect_has   "... the preferences merge, with no .claude.json yet, reporting 'log in first'" "log in first" "$RESTORED"
expect_absent "... creating no .claude.json" "$HOME_R/.claude-own/.claude.json"
expect_link  "... linking ~/.codex to .codex-own" "$HOME_R/.codex" ".codex-own"
expect_no_calls "... running no stubbed command"
expect_clean "... and leaving the repo as committed" "$REPO_R"
for acct in own fna; do
    expect_equal "the installed codex-$acct config.toml trusts <root>/ActiveProjects/OWN/portwatch" \
        "$(trust_count "$HOME_R/.codex-$acct/config.toml" "$ROOT_R")" 1
done
for acct in own fna; do
    for f in settings.json CLAUDE.md; do
        expect_filled "~/.claude-$acct/$f is the repo copy with the root filled in" "$ROOT_R" \
            "$REPO_R/home/claude-code/$acct/$f" "$HOME_R/.claude-$acct/$f"
    done
    for f in config.toml AGENTS.md; do
        expect_filled "~/.codex-$acct/$f is the repo copy with the root filled in" "$ROOT_R" \
            "$REPO_R/home/codex/$acct/$f" "$HOME_R/.codex-$acct/$f"
    done
done
expect_filled "~/.codex-shared/MEMORY.md is the repo copy with the root filled in" "$ROOT_R" \
    "$REPO_R/home/codex/shared/MEMORY.md" "$HOME_R/.codex-shared/MEMORY.md"
expect_equal "no installed file holds $TOKEN or Documents/Projects" \
    "$(grep -rlF -e "$TOKEN" -e 'Documents/Projects' "$HOME_R" 2>&1)" ""
for acct in own fna; do
    for f in statusline.sh title-hook.sh; do
        expect_copy "~/.claude-$acct/$f is the repo copy, executable" \
            "$REPO_R/home/claude-code/$acct/$f" "$HOME_R/.claude-$acct/$f"
    done
done
for f in "${CLAUDE_HOOKS[@]}"; do
    if [[ -L "$HOME_R/.claude-fna/hooks/$f" ]]; then
        fail "~/.claude-fna/hooks/$f is a real file (it is a link)"
    else
        expect_copy "~/.claude-fna/hooks/$f is the repo copy" "$REPO_R/home/claude-code/hooks/$f" "$HOME_R/.claude-fna/hooks/$f"
    fi
    expect_link "~/.claude-own/hooks/$f links to its FNA counterpart" \
        "$HOME_R/.claude-own/hooks/$f" "$HOME_R/.claude-fna/hooks/$f"
done
expect_equal "protected-paths.txt reads the same through the own/ link" \
    "$(cat "$HOME_R/.claude-own/hooks/protected-paths.txt" 2>&1)" "$(cat "$REPO_R/home/claude-code/hooks/protected-paths.txt")"
OUT="$(own_hook "$HOME_R" '~/notes.txt')"; RC=$?; ERR=""
if (( RC == 0 )) && [[ -z "$OUT" ]]; then
    pass "the hook run through the own/ link finds its path list and allows an ordinary read"
else
    fail "the hook run through the own/ link finds its path list and allows an ordinary read"; show
fi
expect_has "... and denies a read under ~/.ssh" '"permissionDecision":"deny"' "$(own_hook "$HOME_R" '~/.ssh/id_ed25519')"

echo "== restore: a re-run over a restored home, now logged in =="
rm "$HOME_R/.claude-own/hooks/protected-paths.txt"
printf 'stale\n' > "$HOME_R/.claude-own/hooks/protected-paths.txt"
printf '{"userID": "kept", "theme": "light"}\n' > "$HOME_R/.claude-own/.claude.json"
run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components claude
expect_rc    "a second restore succeeds" 0
expect_link  "a stale own/ hook file is replaced by the link" \
    "$HOME_R/.claude-own/hooks/protected-paths.txt" "$HOME_R/.claude-fna/hooks/protected-paths.txt"
expect_equal "the tracked preferences are merged into .claude.json" \
    "$(jq -r .theme "$HOME_R/.claude-own/.claude.json")" "dark-daltonized"
expect_equal "... keeping the keys the account wrote" "$(jq -r .userID "$HOME_R/.claude-own/.claude.json")" "kept"
rm -f "$REPO_R/home/claude-code/fna/preferences.json"
printf '{"userID": "fna"}\n' > "$HOME_R/.claude-fna/.claude.json"
run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components claude
expect_rc    "a checkout without fna/preferences.json (it is gitignored) still restores" 0
expect_has   "... reporting that there is nothing to merge, not 'log in first'" "No preferences.json for claude-fna" "$OUT"
expect_file  "... leaving that account's .claude.json as it was" "$HOME_R/.claude-fna/.claude.json" $'{"userID": "fna"}\n'
reset_repo "$REPO_R"

# Claude Code runs the hooks on every tool call, so one may be reading a hook
# while restore replaces it; it must never see a half-written file.
echo "== restore: a re-run replaces each hook whole, never rewriting it in place =="
HOOK_R="$HOME_R/.claude-fna/hooks/protect-credentials.sh"
cp "$HOOK_R" "$RS/hook-before"
printf '# a newer hook\n' >> "$REPO_R/home/claude-code/hooks/protect-credentials.sh"
exec 3< "$HOOK_R"
run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components claude
expect_rc "a re-run over installed hooks succeeds" 0
if cmp -s "$RS/hook-before" - <&3; then
    pass "... a reader that opened the old hook before the re-run still reads it whole"
else
    fail "... a reader that opened the old hook before the re-run still reads it whole"
fi
exec 3<&-
expect_copy "... the installed hook is the new repo copy, executable" \
    "$REPO_R/home/claude-code/hooks/protect-credentials.sh" "$HOOK_R"
expect_link "... still linked from ~/.claude-own/hooks" \
    "$HOME_R/.claude-own/hooks/protect-credentials.sh" "$HOOK_R"
leftovers="$(find "$HOME_R/.claude-fna/hooks" -mindepth 1 -name '.*')"
if [[ -z "$leftovers" ]]; then pass "... leaving no temporary file beside the hooks"; else fail "... leaving no temporary file beside the hooks: $leftovers"; fi
reset_repo "$REPO_R"

# Linking each own/ entry through such a directory would link a hook onto
# itself; ln refuses ("are the same file"), and the FNA files must survive.
echo "== restore: a linked ~/.claude-own/hooks directory stops restore, hooks intact =="
fresh_home "$HOME_R"
run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components claude
rm -rf "$HOME_R/.claude-own/hooks"
ln -s "$HOME_R/.claude-fna/hooks" "$HOME_R/.claude-own/hooks"
run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components claude
expect_fail  "restore claude stops when ~/.claude-own/hooks links to the FNA hooks"
for f in "${CLAUDE_HOOKS[@]}"; do
    expect_copy "... leaving ~/.claude-fna/hooks/$f intact" "$REPO_R/home/claude-code/hooks/$f" "$HOME_R/.claude-fna/hooks/$f"
done

echo "== restore: the root can come from the declaration file =="
HOME_D="$RS/d"; ROOT_D="$HOME_D/Projects"
mkdir -p "$ROOT_D" "$HOME_D/.config/environment.d"
make_restore_repo "$ROOT_D"
printf 'PROJECTS_ROOT=${HOME}/Projects\n' > "$HOME_D/.config/environment.d/50-projects-root.conf"
run_restore "$ROOT_D/system_settings" "$HOME_D" "" --configs --components codex
expect_rc    "restore resolves a declared \${HOME}/Projects root when none is exported" 0
expect_equal "... and the installed config.toml trusts ~/Projects/ActiveProjects/OWN/portwatch" \
    "$(trust_count "$HOME_D/.codex-own/config.toml" "$ROOT_D")" 1

echo "== restore: without jq, claude stops before installing anything (KTD10) =="
fresh_home "$HOME_R"
NOJQ=1 run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components claude
expect_fail  "restore claude with no jq on PATH fails"
expect_has   "... with an error naming jq" "jq" "$(grep -F ERROR <<<"$OUT")"
expect_absent "... installing no hook" "$HOME_R/.claude-fna/hooks"
expect_absent "... and no settings.json" "$HOME_R/.claude-own/settings.json"
expect_empty_home "... nor anything else" "$HOME_R"

echo "== restore: fish installs the tracked fish files (KTD14) =="
mkdir -p "$REPO_R/home/.config/fish/conf.d"
printf '# projects-root loader fixture\n' > "$REPO_R/home/.config/fish/conf.d/projects-root.fish"
fresh_home "$HOME_R"
run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components fish
expect_rc "restore fish succeeds" 0
for rel in "${FISH_FILES[@]}"; do
    expect_copy "~/$rel is the repo copy" "$REPO_R/home/$rel" "$HOME_R/$rel"
done
rm "$REPO_R/home/.config/fish/conf.d/projects-root.fish"
fresh_home "$HOME_R"
run_restore "$REPO_R" "$HOME_R" "$ROOT_R" --configs --components fish
expect_rc    "restore fish succeeds when the repo has no projects-root loader" 0
expect_has   "... reporting the loader as skipped" "skip" "$(grep -F conf.d/projects-root.fish <<<"$OUT")"
expect_absent "... installing no loader" "$HOME_R/.config/fish/conf.d/projects-root.fish"
for rel in "${FISH_FILES[@]:0:2}"; do
    expect_copy "... and still installing ~/$rel" "$REPO_R/home/$rel" "$HOME_R/$rel"
done
reset_repo "$REPO_R"

# ── shell consumers ──────────────────────────────────────────────
# An installed shell or script cannot source this repo's library, so the zsh
# loader in home/.zshrc and the resolver in project-launch repeat its rules.
# Their functions are extracted from the tracked files and run on the same
# cases as the library. zsh runs with -f, so no rc file is read; the
# interactive cases run under a pseudo-terminal (script), where -t 0 holds.
# project-launch runs whole, with rofi, kitty, i3-msg, notify-send, the
# browsers, obsidian and sleep stubbed on PATH, in a scratch HOME.

ZSHRC="$REPO_ROOT/home/.zshrc"
LAUNCH="$REPO_ROOT/home/.config/i3/scripts/project-launch"
ZLOADER="$SCRATCH/zloader.zsh"
LRESOLVER="$SCRATCH/lresolver.sh"
sed -n '/^_projects_root_[a-z_]*() {/,/^}/p' "$ZSHRC" > "$ZLOADER"
sed -n '/^_projects_root_[a-z_]*() {/,/^}/p; /^resolve_projects_root() {/,/^}/p' "$LAUNCH" > "$LRESOLVER"
mkdir -p "$HOME/Projects" "$HOME/Other" "$SCRATCH/sx/Work"
ln -sfn "$SCRATCH/sx" "$SCRATCH/sxlink"
touch "$SCRATCH/plainfile"

expect_true() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
line_no() { grep -n -m1 -e "$1" "$ZSHRC" | cut -d: -f1; }  # <regex>: first matching line of .zshrc
# What each consumer resolves from the current HOME, declaration file and
# PROJECTS_ROOT: the root, or <fail>.
lib_root()    { bash -c 'source "$0" && projects_root_resolve 2>/dev/null || echo "<fail>"' "$LIB"; }
zsh_root()    { timeout 10 zsh -f -c 'source "$1"; _projects_root_load; print -r -- "${PROJECTS_ROOT-<fail>}"' zsh "$ZLOADER" 2>/dev/null; }
launch_root() { bash -c 'source "$0"; if resolve_projects_root; then printf "%s\n" "$PROJECTS_ROOT"; else echo "<fail>"; fi' "$LRESOLVER" 2>/dev/null; }
parity() {  # <desc> <expected root or <fail>>
    local lib zsh launch
    lib="$(lib_root)"; zsh="$(zsh_root)"; launch="$(launch_root)"
    if [[ "$lib" == "$2" && "$zsh" == "$2" && "$launch" == "$2" ]]; then
        pass "$1"
    else
        fail "$1"
        printf '      want: %s\n      library: %s\n      zsh loader: %s\n      project-launch: %s\n' "$2" "$lib" "$zsh" "$launch"
    fi
}
# zload [code] -- the zsh loader in a non-interactive zsh, then code; sets
# OUT, ERR and RC (124 when it hangs).
zload() {
    OUT="$(timeout 10 zsh -f -c 'source "$1" || exit 99; _projects_root_load; print -r -- "rc=$?"; eval "$2"' zsh "$ZLOADER" "${1-}" 2>"$SCRATCH/stderr")"
    RC=$?
    ERR="$(<"$SCRATCH/stderr")"
}
# zpty -- the zsh loader in an interactive zsh under a pseudo-terminal; prints
# the transcript, CRs dropped, ending in "SENTINEL rc=<status> root=<root>".
zpty() {
    printf 'source %q\n_projects_root_load\nprint -r -- "SENTINEL rc=$? root=${PROJECTS_ROOT-<unset>}"\n' "$ZLOADER" > "$SCRATCH/zdrive.zsh"
    timeout 20 script -qec "zsh -f -i -c 'source $SCRATCH/zdrive.zsh'" /dev/null </dev/null 2>/dev/null | tr -d '\r'
}

echo "== shell: the zsh loader is a named function, called before the steps that need the root =="
expect_true "home/.zshrc parses (zsh -n)"                  zsh -n "$ZSHRC"
expect_true "_projects_root_load is defined in .zshrc"     grep -q '^_projects_root_load() {' "$ZSHRC"
expect_true "the extracted loader defines it"              grep -q '^_projects_root_load() {' "$ZLOADER"
load_at="$(line_no '^_projects_root_load$')"
sync_at="$(line_no '^_settings_sync_check$')"
title_at="$(line_no '^[^#]*terminal-title\.zsh')"
omz_at="$(line_no '^source "$ZSH/oh-my-zsh.sh"')"
if [[ -n "$load_at" && -n "$sync_at" && -n "$title_at" && -n "$omz_at" ]] \
    && (( load_at < omz_at && load_at < sync_at && load_at < title_at )); then
    pass "the loader runs near the top, before Oh My Zsh, the sync check and the terminal-title hook"
else
    fail "the loader runs near the top (loader ${load_at:-none}, omz ${omz_at:-none}, sync ${sync_at:-none}, title ${title_at:-none})"
fi

echo "== shell: the zsh loader and project-launch resolve as the library does =="
nodecl; unset PROJECTS_ROOT
decl $'PROJECTS_ROOT=${HOME}/Projects\n';                 parity "\${HOME} expands"                         "$HOME/Projects"
decl $'PROJECTS_ROOT=$HOME/Projects\n';                   parity "\$HOME expands"                           "$HOME/Projects"
decl $'PROJECTS_ROOT=~/Projects\n';                       parity "a leading ~ expands"                      "$HOME/Projects"
decl $'PROJECTS_ROOT=~\n';                                parity "a bare ~ is HOME"                         "$HOME"
decl $'PROJECTS_ROOT=${HOME}/./Projects//\n';             parity "dot segments and trailing slashes go"     "$HOME/Projects"
decl $'PROJECTS_ROOT=${HOME}/Projects\n# PROJECTS_ROOT=${HOME}/Other\n;PROJECTS_ROOT=${HOME}/Other\n   # PROJECTS_ROOT=/nowhere\n'
parity "commented-out lines are ignored" "$HOME/Projects"
decl $'PROJECTS_ROOT=${HOME}/Other\nPROJECTS_ROOT=${HOME}/Projects\n'; parity "the last PROJECTS_ROOT= line wins" "$HOME/Projects"
decl $'  PROJECTS_ROOT = "${HOME}/Projects"  \r\n';          parity "whitespace, double quotes and CRLF are stripped" "$HOME/Projects"
decl "PROJECTS_ROOT='\${HOME}/Projects'";                    parity "single quotes and no final newline"      "$HOME/Projects"
decl $'OTHER=1\nPROJECTS_ROOT=${HOME}/Projects\nMORE=2\n';   parity "other assignments are skipped"           "$HOME/Projects"
decl $'PROJECTS_ROOT="${HOME}/Projects\n';                   parity "an unbalanced quote stays, so it is relative" "<fail>"
decl $'PROJECTS_ROOT=""\n';                                  parity "an empty quoted value fails"             "<fail>"
decl $'PROJECTS_ROOT=\n';                                    parity "an empty value fails"                    "<fail>"
decl $'PROJECTS_ROOT=Projects\n';                            parity "a relative value fails"                  "<fail>"
decl $'PROJECTS_ROOT=~other/Projects\n';                     parity "~user is not expanded"                   "<fail>"
decl $'PROJECTS_ROOT=$HOMEDIR/Projects\n';                   parity "\$HOMEDIR is not \$HOME"                  "<fail>"
decl $'PROJECTS_ROOT=${HOME}/Missing\n';                     parity "a missing directory fails"               "<fail>"
decl $'PROJECTS_ROOT=///\n';                                 parity "the filesystem root is refused"          "<fail>"
decl $'NOT_PROJECTS_ROOT=${HOME}/Projects\n# PROJECTS_ROOT=${HOME}/Projects\n'; parity "no live PROJECTS_ROOT= line fails" "<fail>"
nodecl;                                                      parity "no export and no file fails"             "<fail>"
export PROJECTS_ROOT="$SCRATCH/sx/./Work//../Work/";         parity "an exported value is normalised"         "$SCRATCH/sx/Work"
export PROJECTS_ROOT="$SCRATCH/sxlink/Work";                 parity "a symlinked root keeps its spelling"     "$SCRATCH/sxlink/Work"
export PROJECTS_ROOT='${HOME}/Projects';                     parity "a literal \${HOME} in an export expands"  "$HOME/Projects"
export PROJECTS_ROOT='~/Projects';                           parity "a literal ~ in an export expands"        "$HOME/Projects"
export PROJECTS_ROOT="$SCRATCH/plainfile";                   parity "an exported file, not a directory, fails" "<fail>"
export PROJECTS_ROOT=/;                                      parity "an exported / fails"                     "<fail>"
decl $'PROJECTS_ROOT=${HOME}/Projects\n'
export PROJECTS_ROOT="$HOME/Other";                          parity "an export wins over the declaration file" "$HOME/Other"
export PROJECTS_ROOT=Projects;                               parity "a bad export fails, never falling back to the file" "<fail>"
export PROJECTS_ROOT=;                                       parity "an empty export falls back to the file"  "$HOME/Projects"
unset PROJECTS_ROOT

echo "== shell: the zsh loader exports the root and stays silent off a terminal =="
decl $'PROJECTS_ROOT=${HOME}/Projects/\n'
zload 'printenv PROJECTS_ROOT'
expect_out "a declared root is exported, normalised" $'rc=0\n'"$HOME/Projects"
nodecl
zload 'print -r -- "${PROJECTS_ROOT-<unset>}"'
expect_rc  "no file, non-interactive: returns promptly with status 0" 0
expect_out "... PROJECTS_ROOT stays unset, and nothing else is printed" $'rc=0\n<unset>'
if [[ -z "$ERR" ]]; then pass "... and nothing goes to stderr"; else fail "... and nothing goes to stderr"; show; fi
OUT="$(printf '' | timeout 10 zsh -f -i -c 'source "$1"; _projects_root_load; print -r -- "rc=$?"' zsh "$ZLOADER" 2>&1)"; RC=$?; ERR=""
expect_out "no file, interactive but no terminal on stdin: silent" "rc=0"
PROJECTS_ROOT=Projects zload 'print -r -- "${PROJECTS_ROOT-<unset>}"'
expect_out "a bad export is unset, so the steps that need it skip, silently here" $'rc=0\n<unset>'
if [[ -z "$ERR" ]]; then pass "... with nothing on stderr"; else fail "... with nothing on stderr"; show; fi

echo "== shell: an interactive terminal gets exactly one warning line, and startup goes on (AE5) =="
nodecl
T="$(zpty)"
body="$(grep -v '^SENTINEL' <<<"$T" | grep -c .)"
if [[ "$body" == 1 ]]; then pass "no file: exactly one line is printed besides the sentinel"; else fail "no file: exactly one line is printed (got $body)"; sed 's/^/      | /' <<<"$T"; fi
expect_has   "... the loader returns 0 and PROJECTS_ROOT is unset" "SENTINEL rc=0 root=<unset>" "$T"
warning="$(grep -v '^SENTINEL' <<<"$T")"
expect_has   "... the warning names PROJECTS_ROOT" "PROJECTS_ROOT is not set" "$warning"
expect_has   "... the warning names the declaration file" "$DECL" "$warning"
expect_has   "... the warning shows the neutral example line" 'PROJECTS_ROOT=${HOME}/path/to/projects' "$warning"
expect_has   "... the warning says what is skipped" "sync check" "$warning"
expect_lacks "... the example is not the Dell root" "Documents/Projects" "$warning"
expect_lacks "... the example is not the laptop root (~)" "~/Projects" "$warning"
expect_lacks "... the example is not the laptop root (\${HOME})" '{HOME}/Projects' "$warning"
expect_lacks "... the example is not the laptop root (\$HOME)" '$HOME/Projects' "$warning"
decl $'PROJECTS_ROOT=${HOME}/Missing\n'
T="$(zpty)"
expect_has   "a declared missing directory warns, naming the value" "PROJECTS_ROOT='$HOME/Missing' (declared) is not an existing directory" "$T"
expect_has   "... and PROJECTS_ROOT is left unset" "SENTINEL rc=0 root=<unset>" "$T"
decl $'PROJECTS_ROOT=${HOME}/Projects\n'
T="$(PROJECTS_ROOT=Projects zpty)"
expect_has   "a bad export warns, naming it as exported" "PROJECTS_ROOT='Projects' (exported) is not an absolute path" "$T"
T="$(zpty)"
expect_has   "a declared root on a terminal: exported" "SENTINEL rc=0 root=$HOME/Projects" "$T"
expect_lacks "... with no warning" "[projects-root]" "$T"
nodecl

echo "== shell: the terminal-title hook is sourced only when the root and the hook exist =="
TITLE_BLOCK="$SCRATCH/title.zsh"
grep -A1 -e '^\[\[ -n "\$PROJECTS_ROOT" && -f .*terminal-title\.zsh" \]\] \\$' "$ZSHRC" > "$TITLE_BLOCK"
expect_true  "the guarded source is found in .zshrc" test "$(wc -l < "$TITLE_BLOCK")" -eq 2
expect_true  "no unguarded terminal-title source remains" test "$(grep -c '^source .*terminal-title' "$ZSHRC")" -eq 0
HOOK_DIR="$SCRATCH/titleroot/ActiveProjects/OWN/claude-code-terminal-title/shell"
mkdir -p "$HOOK_DIR"
title_run() { timeout 10 zsh -f -c 'source "$1"; print -r -- "after"' zsh "$TITLE_BLOCK" 2>&1; }
unset PROJECTS_ROOT
OUT="$(title_run)"
expect_out "PROJECTS_ROOT unset: skipped without an error" "after"
OUT="$(PROJECTS_ROOT="$SCRATCH/titleroot" title_run)"
expect_out "the hook missing under the root: skipped without an error" "after"
printf 'print -r -- TITLE_HOOK_LOADED\n' > "$HOOK_DIR/terminal-title.zsh"
OUT="$(PROJECTS_ROOT="$SCRATCH/titleroot" title_run)"
expect_out "the hook present under the root: sourced" $'TITLE_HOOK_LOADED\nafter'

echo "== shell: project-launch finds projects under \$PROJECTS_ROOT/ActiveProjects =="
PL="$SCRATCH/pl"
PLHOME="$PL/home"
PLROOT="$PLHOME/Projects"
PLDECL="$PLHOME/.config/environment.d/50-projects-root.conf"
export PL_CALLS="$PL/calls"
mkdir -p "$PL/bin" "$PLROOT/ActiveProjects/OWN/alpha" "$PLROOT/ActiveProjects/FNA/beta" "$PLROOT/ActiveProjects/loose" "${PLDECL%/*}"
# One recording stub for every external: each call appends "CALL [arg]..." to
# $PL_CALLS/<name>. rofi also saves the list it was given and picks nothing
# unless STUB_ROFI_PICK says otherwise; i3-msg answers queries with no workspaces.
cat > "$PL/bin/stub" <<'STUB'
#!/bin/bash
name="${0##*/}"
{ printf 'CALL'; printf ' [%s]' "$@"; printf '\n'; } >> "$PL_CALLS/$name"
case "$name" in
    rofi) cat > "$PL_CALLS/rofi.stdin"; printf '%s\n' "${STUB_ROFI_PICK-}" ;;
    i3-msg) [[ "${1-}" == -t ]] && echo '[]' ;;
esac
exit 0
STUB
chmod +x "$PL/bin/stub"
for name in rofi kitty i3-msg notify-send brave firefox obsidian sleep; do ln -sfn stub "$PL/bin/$name"; done
# launch [args...] -- project-launch in the scratch HOME with the stubs first on
# PATH and PROJECTS_ROOT as the caller left it; sets OUT, ERR and RC.
launch() {
    rm -rf "$PL_CALLS"; mkdir -p "$PL_CALLS"
    OUT="$(HOME="$PLHOME" PATH="$PL/bin:$PATH" timeout 20 bash "$LAUNCH" "$@" 2>"$SCRATCH/stderr")"
    RC=$?
    ERR="$(<"$SCRATCH/stderr")"
}
# wait_for <file> <fixed string> -- the launcher backgrounds kitty, so its
# calls may land just after it exits.
wait_for() {
    local i
    for i in $(seq 50); do grep -qF -- "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done
    return 1
}
calls() { cat "$PL_CALLS/$1" 2>/dev/null; }

expect_true "project-launch parses (bash -n)" bash -n "$LAUNCH"
unset PROJECTS_ROOT
printf 'PROJECTS_ROOT=${HOME}/Projects/\n' > "$PLDECL"
launch
expect_rc  "declared root, nothing picked: exits 0" 0
lst="$(cat "$PL_CALLS/rofi.stdin" 2>/dev/null)"
expect_true "rofi lists OWN/alpha" grep -qx 'OWN/alpha' <<<"$lst"
expect_true "rofi lists FNA/beta"  grep -qx 'FNA/beta'  <<<"$lst"
expect_true "rofi lists loose"     grep -qx 'loose'     <<<"$lst"

launch OWN/alpha
expect_rc  "a named project launches" 0
wait_for "$PL_CALLS/kitty" " [claude]"
claude_call="$(grep -F ' [claude]' "$PL_CALLS/kitty" 2>/dev/null)"
expect_has "kitty starts claude in the project under the root" "[--directory] [$PLROOT/ActiveProjects/OWN/alpha]" "$claude_call"
expect_has "... with the OWN Claude config" "[CLAUDE_CONFIG_DIR=$PLHOME/.claude-own]" "$claude_call"
expect_has "... carrying the resolved, normalised PROJECTS_ROOT" "[PROJECTS_ROOT=$PLROOT]" "$claude_call"

rm -f "$PLDECL"
PROJECTS_ROOT="$PLROOT//" launch FNA/beta
wait_for "$PL_CALLS/kitty" " [claude]"
claude_call="$(grep -F ' [claude]' "$PL_CALLS/kitty" 2>/dev/null)"
expect_has "an exported root works with no declaration file" "[--directory] [$PLROOT/ActiveProjects/FNA/beta]" "$claude_call"
expect_has "... and claude gets it normalised" "[PROJECTS_ROOT=$PLROOT]" "$claude_call"

printf 'PROJECTS_ROOT=${HOME}/Projects\n' > "$PLDECL"
launch nope
expect_rc  "a missing project still exits 1" 1
expect_has "... telling notify-send where it looked" "[Project not found] [$PLROOT/ActiveProjects/nope]" "$(calls notify-send)"

echo "== shell: project-launch with no resolvable root reports it and stops =="
rm -f "$PLDECL"
launch
if (( RC != 0 )); then pass "no export and no file: exits non-zero"; else fail "no export and no file: exits non-zero"; show; fi
note="$(calls notify-send)"
expect_has   "notify-send receives the resolver message" "PROJECTS_ROOT is not set (neither exported nor declared)" "$note"
expect_has   "... naming the declaration file" "$PLDECL" "$note"
expect_has   "... with the neutral example line" 'PROJECTS_ROOT=${HOME}/path/to/projects' "$note"
expect_has   "the message also goes to stderr" "PROJECTS_ROOT is not set" "$ERR"
expect_true  "rofi is never shown"   test ! -e "$PL_CALLS/rofi"
expect_true  "kitty is never started" test ! -e "$PL_CALLS/kitty"
printf 'PROJECTS_ROOT=${HOME}/Missing\n' > "$PLDECL"
launch OWN/alpha
if (( RC != 0 )); then pass "a declared missing directory: exits non-zero"; else fail "a declared missing directory: exits non-zero"; show; fi
expect_has   "... notify-send names the value" "PROJECTS_ROOT='$PLHOME/Missing' (declared) is not an existing directory" "$(calls notify-send)"
expect_true  "... and kitty is never started" test ! -e "$PL_CALLS/kitty"

echo
echo "Passed: $PASSED, failed: $FAILED"
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
