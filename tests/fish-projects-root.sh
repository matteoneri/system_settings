#!/bin/bash
# Tests for the fish projects-root loader (home/.config/fish/conf.d/projects-root.fish),
# the fish port of _projects_root_load in home/.zshrc. It must resolve
# PROJECTS_ROOT by the rules of projects_root_resolve in lib/projects-root.sh:
# a non-empty exported value wins, else the last PROJECTS_ROOT= line of
# ~/.config/environment.d/50-projects-root.conf; surrounding whitespace and one
# pair of quotes are stripped; a leading ~, $HOME or ${HOME} expands; the result
# is normalised; a relative path, / or a missing directory is refused.
# Unresolved, PROJECTS_ROOT is erased, and only an interactive fish warns.
#
# HOME and the XDG directories point into a mktemp scratch. Every fish runs
# with --no-config and sources the tracked loader explicitly, except the conf.d
# cases, whose config directory is the scratch one, so the machine's own fish
# config and any installed copy of the loader stay out of the run.
#
# Needs fish and script (util-linux). Run: bash tests/fish-projects-root.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$REPO_ROOT/home/.config/fish/conf.d/projects-root.fish"
FAILED=0

for tool in fish script; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "cannot run: $tool is not installed on this machine (install it, or run this on the CachyOS laptop)" >&2
        exit 1
    fi
done

fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }
pass() { echo "  ok: $*"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
export HOME="$SCRATCH/home"
export XDG_CONFIG_HOME="$SCRATCH/xdg/config" XDG_DATA_HOME="$SCRATCH/xdg/data" XDG_CACHE_HOME="$SCRATCH/xdg/cache"
unset PROJECTS_ROOT
DECL="$HOME/.config/environment.d/50-projects-root.conf"
mkdir -p "$HOME/Projects" "$HOME/Other" "$SCRATCH/sx/Work" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
ln -s "$SCRATCH/sx" "$SCRATCH/sxlink"
touch "$SCRATCH/plainfile"

decl() { mkdir -p "${DECL%/*}"; printf '%s' "$1" > "$DECL"; }
nodecl() { rm -f "$DECL"; }

show() {
    echo "      status: $RC"
    [[ -n "$OUT" ]] && sed 's/^/      out | /' <<<"$OUT"
    [[ -n "$ERR" ]] && sed 's/^/      err | /' <<<"$ERR"
    return 0
}
expect_rc()    { if (( RC == $2 )); then pass "$1"; else fail "$1 (status $RC, want $2)"; show; fi; }
expect_out()   { if [[ "$OUT" == "$2" ]]; then pass "$1"; else fail "$1"; printf '      want: %q\n' "$2"; show; fi; }
expect_has()   { if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1 (missing: $2)"; sed 's/^/      | /' <<<"$3"; fi; }
expect_lacks() { if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1 (unexpected: $2)"; sed 's/^/      | /' <<<"$3"; fi; }

# load <fish code> -- source the tracked loader in a non-interactive fish with
# no config, then run the code; sets OUT, ERR and RC (124 when it hangs).
load() {
    OUT="$(timeout 20 fish --no-config -c 'source $argv[1]; or exit 99; '"$1" -- "$LOADER" 2>"$SCRATCH/stderr")"
    RC=$?
    ERR="$(<"$SCRATCH/stderr")"
}
# root_case <desc> <expected root, or <unset>> -- what the loader makes of the
# current declaration file and PROJECTS_ROOT.
root_case() {
    load 'if set -q PROJECTS_ROOT; printf "%s\n" $PROJECTS_ROOT; else; echo "<unset>"; end'
    expect_out "$1" "$2"
}
# pty <fish code> -- source the loader in an interactive fish under a
# pseudo-terminal, then run the code; prints the transcript, CRs dropped.
pty() {
    printf 'source %q\n%s\n' "$LOADER" "$1" > "$SCRATCH/drive.fish"
    timeout 20 script -qec "fish --no-config -i -c 'source $SCRATCH/drive.fish'" /dev/null </dev/null 2>/dev/null | tr -d '\r'
}

echo "== the loader parses =="
if fish --no-execute "$LOADER" 2>"$SCRATCH/stderr"; then pass "fish -n accepts the loader"; else fail "fish -n accepts the loader"; cat "$SCRATCH/stderr"; fi

echo "== a declared root is exported =="
decl $'PROJECTS_ROOT=${HOME}/Projects\n'
load 'echo $PROJECTS_ROOT'
expect_rc  "fish -c exits 0" 0
expect_out "fish -c 'echo \$PROJECTS_ROOT' prints the root" "$HOME/Projects"
load 'command printenv PROJECTS_ROOT'
expect_out "child processes see it: it is exported" "$HOME/Projects"
if [[ -z "$ERR" ]]; then pass "nothing goes to stderr"; else fail "nothing goes to stderr"; show; fi

echo "== the declaration file is read as the library reads it =="
decl $'PROJECTS_ROOT=$HOME/Projects\n';                  root_case "\$HOME expands"                              "$HOME/Projects"
decl $'PROJECTS_ROOT=~/Projects\n';                      root_case "a leading ~ expands"                         "$HOME/Projects"
decl $'PROJECTS_ROOT=~\n';                               root_case "a bare ~ is HOME"                            "$HOME"
decl $'PROJECTS_ROOT=${HOME}/./Projects//\n';            root_case "dot segments and trailing slashes go"        "$HOME/Projects"
decl $'PROJECTS_ROOT=${HOME}/Projects\n# PROJECTS_ROOT=${HOME}/Other\n;PROJECTS_ROOT=${HOME}/Other\n   # PROJECTS_ROOT=/nowhere\n'
root_case "commented-out lines are ignored" "$HOME/Projects"
decl $'PROJECTS_ROOT=${HOME}/Other\nPROJECTS_ROOT=${HOME}/Projects\n'; root_case "the last PROJECTS_ROOT= line wins" "$HOME/Projects"
decl $'  PROJECTS_ROOT = "${HOME}/Projects"  \r\n';         root_case "whitespace, double quotes and CRLF are stripped" "$HOME/Projects"
decl "PROJECTS_ROOT='\${HOME}/Projects'";                   root_case "single quotes and no final newline"          "$HOME/Projects"
decl $'OTHER=1\nPROJECTS_ROOT=${HOME}/Projects\nMORE=2\n';  root_case "other assignments are skipped"               "$HOME/Projects"
decl $'PROJECTS_ROOT="${HOME}/Projects\n';                  root_case "an unbalanced quote stays, so it is relative" "<unset>"
decl $'PROJECTS_ROOT=""\n';                                 root_case "an empty quoted value fails"                 "<unset>"
decl $'PROJECTS_ROOT=\n';                                   root_case "an empty value fails"                        "<unset>"
decl $'PROJECTS_ROOT=Projects\n';                           root_case "a relative value fails"                      "<unset>"
decl $'PROJECTS_ROOT=~other/Projects\n';                    root_case "~user is not expanded"                       "<unset>"
decl $'PROJECTS_ROOT=$HOMEDIR/Projects\n';                  root_case "\$HOMEDIR is not \$HOME"                      "<unset>"
decl $'PROJECTS_ROOT=${HOME}/Missing\n';                    root_case "a missing directory fails"                   "<unset>"
decl $'PROJECTS_ROOT=///\n';                                root_case "the filesystem root is refused"              "<unset>"
decl $'NOT_PROJECTS_ROOT=${HOME}/Projects\n# PROJECTS_ROOT=${HOME}/Projects\n'; root_case "no live PROJECTS_ROOT= line fails" "<unset>"
nodecl;                                                     root_case "no export and no file fails"                 "<unset>"

echo "== an exported value wins, normalised =="
export PROJECTS_ROOT="$SCRATCH/sx/./Work//../Work/";        root_case "an exported value is normalised"             "$SCRATCH/sx/Work"
export PROJECTS_ROOT="$SCRATCH/sxlink/Work";                root_case "a symlinked root keeps its spelling"         "$SCRATCH/sxlink/Work"
export PROJECTS_ROOT='${HOME}/Projects';                    root_case "a literal \${HOME} in an export expands"      "$HOME/Projects"
export PROJECTS_ROOT='~/Projects';                          root_case "a literal ~ in an export expands"            "$HOME/Projects"
export PROJECTS_ROOT="$SCRATCH/plainfile";                  root_case "an exported file, not a directory, fails"    "<unset>"
export PROJECTS_ROOT=/;                                     root_case "an exported / fails"                         "<unset>"
decl $'PROJECTS_ROOT=${HOME}/Projects\n'
export PROJECTS_ROOT="$HOME/Other"
load 'echo $PROJECTS_ROOT'
expect_out "an export wins over the declaration file" "$HOME/Other"
export PROJECTS_ROOT=Projects;                              root_case "a bad export fails, never falling back to the file" "<unset>"
export PROJECTS_ROOT=;                                      root_case "an empty export falls back to the file"      "$HOME/Projects"
unset PROJECTS_ROOT

echo "== unresolved, a non-interactive fish prints nothing =="
nodecl
load 'true'
expect_rc  "no file: fish -c exits 0 promptly" 0
expect_out "... printing nothing on stdout" ""
if [[ -z "$ERR" ]]; then pass "... and nothing on stderr"; else fail "... and nothing on stderr"; show; fi
export PROJECTS_ROOT=Projects
load 'true'
expect_out "a bad export: nothing on stdout" ""
if [[ -z "$ERR" ]]; then pass "... and nothing on stderr"; else fail "... and nothing on stderr"; show; fi
unset PROJECTS_ROOT

echo "== installed in conf.d, it loads on its own =="
mkdir -p "$XDG_CONFIG_HOME/fish/conf.d"
cp "$LOADER" "$XDG_CONFIG_HOME/fish/conf.d/projects-root.fish"
decl $'PROJECTS_ROOT=${HOME}/Projects\n'
OUT="$(timeout 20 fish -c 'echo $PROJECTS_ROOT' 2>&1)"; RC=$?; ERR=""
expect_out "fish -c 'echo \$PROJECTS_ROOT' prints the declared root" "$HOME/Projects"
nodecl
OUT="$(timeout 20 fish -c true 2>&1)"; RC=$?
expect_rc  "no file: fish -c true exits 0" 0
expect_out "... and prints nothing at all" ""
rm -r "$XDG_CONFIG_HOME/fish"

echo "== unresolved, an interactive fish warns exactly once =="
nodecl
T="$(pty 'echo SENTINEL (set -q PROJECTS_ROOT; and echo set; or echo unset)')"
count="$(grep -c 'PROJECTS_ROOT' <<<"$T")"
if [[ "$count" == 1 ]]; then pass "no file: one warning line"; else fail "no file: one warning line (got $count)"; sed 's/^/      | /' <<<"$T"; fi
expect_has   "... and the session goes on, with PROJECTS_ROOT unset" "SENTINEL unset" "$T"
warning="$(grep 'PROJECTS_ROOT' <<<"$T")"
expect_has   "... the warning names PROJECTS_ROOT" "PROJECTS_ROOT is not set" "$warning"
expect_has   "... the warning names the declaration file" "$DECL" "$warning"
expect_has   "... the warning shows the neutral example line" 'PROJECTS_ROOT=${HOME}/path/to/projects' "$warning"
expect_lacks "... the example is not the Dell root" "Documents/Projects" "$warning"
expect_lacks "... the example is not the laptop root (~)" "~/Projects" "$warning"
expect_lacks "... the example is not the laptop root (\${HOME})" '{HOME}/Projects' "$warning"
expect_lacks "... the example is not the laptop root (\$HOME)" '$HOME/Projects' "$warning"
decl $'PROJECTS_ROOT=${HOME}/Missing\n'
T="$(pty 'echo SENTINEL')"
expect_has   "a declared missing directory warns, naming the value" "PROJECTS_ROOT='$HOME/Missing' (declared) is not an existing directory" "$T"
decl $'PROJECTS_ROOT=${HOME}/Projects\n'
T="$(pty 'echo SENTINEL $PROJECTS_ROOT')"
expect_has   "a declared root on a terminal: exported" "SENTINEL $HOME/Projects" "$T"
expect_lacks "... with no warning" "[projects-root]" "$T"
nodecl

echo
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
