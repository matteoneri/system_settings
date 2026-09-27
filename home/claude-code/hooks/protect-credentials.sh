#!/usr/bin/env bash
# protect-credentials.sh — Claude Code PreToolUse hook. Denies reads of
# credential and secret locations.
#
# WHY IT EXISTS. This enforcement used to be `Read(...)` entries in
# permissions.deny. Those had to be removed: the mere PRESENCE of any Read()
# deny rule arms two Claude Code checks on any compound command containing a
# `cd` (claude 2.1.259) — `cd-compound-read`, and a `deniedPathInsideDirectory`
# safetyCheck flagged bypassImmune, which no permission mode and no hook allow
# can clear. Between them they prompted on ordinary read-only commands, in
# shapes that could not be enumerated ahead of time (a flag after a search
# pattern, a search with no path, a git ref, a backslash inside double quotes).
# A hook `deny` is checked before every permission mode, including
# --dangerously-skip-permissions, so the protection is equivalent while the
# prompts are gone.
#
# WHAT IT DOES.
#   * File tools (Read/Grep/Glob/Edit/Write/NotebookEdit/MultiEdit): resolves
#     the path input, follows symlinks, and denies if it lands on a listed
#     glob. Grep and Glob recurse, so they are ALSO denied when their search
#     root (the path input, or the session cwd when there is none) is an
#     ancestor of a listed glob: `Grep path=~` would otherwise read ~/.ssh.
#   * Bash and Monitor (both run .tool_input.command in a shell): denies when
#     the command text names a protected location, both as written and with
#     quotes and backslashes stripped, since the shell turns `~/.a''ws` and
#     `~/.a\ws` into ~/.aws. Glob words rooted at ~, $HOME or / are expanded
#     (compgen -G: expansion only, nothing runs) and denied when a result is a
#     protected path, which catches `cat ~/.a?s/credentials`. This is a text
#     test, not a path resolver, because the shell shapes that reach here
#     (heredocs, substitutions, quoting) cannot all be parsed safely — so it
#     fails closed. It is deliberately stricter than the old rule in one way:
#     naming a protected path in a search pattern is refused too.
#
# The list lives in protected-paths.txt beside this script (one glob per line).
# Add a path there; do not add a Read() rule to permissions.deny, or the
# prompts come back.
#
# Tests: protect-credentials.test.sh (same directory).

set -u
# One jq call, because this hook runs on EVERY tool call: the fields joined by
# US, then RS, then the command last, so an embedded newline cannot confuse the
# split. Note the parentheses: piping here would rebind `.` and lose
# .tool_input (that bug made the guard allow everything, and the suite caught
# it immediately). A jq failure exits 2 — a guard must never fail open.
raw=$(jq -r '([(.tool_name // ""), (.cwd // ""),
               ([.tool_input.file_path?, .tool_input.path?, .tool_input.notebook_path?,
                 (.tool_input.edits[]?.file_path?)] | map(select(type == "string")) | join("\u001f"))]
              | join("\u001f")) + "\u001e" + (.tool_input.command // "")' 2>/dev/null) || {
    echo "protect-credentials: could not parse the hook payload; refusing" >&2; exit 2; }
fields=${raw%%$'\x1e'*}
cmd=${raw#*$'\x1e'}
IFS=$'\x1f' read -r tool cwd paths_joined <<<"$fields"
[ -n "${tool:-}" ] || exit 0

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
list=${FNET_PROTECTED_PATHS:-$here/protected-paths.txt}
[ -r "$list" ] || { echo "protect-credentials: cannot read $list" >&2; exit 2; }
home=${HOME:?}

deny() {   # deny REASON
    jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
}

# ---- the list ---------------------------------------------------------------
# Blanks around a line are trimmed (read's default IFS does it; the CR case is
# the only one left over): an indented `# note` is a comment, and a stray
# trailing space must not turn `~/.ssh/**` into a pattern that matches nothing.
# `|| [ -n "$line" ]` keeps a last line that has no newline.
declare -a globs=()
while read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case $line in *[[:space:]]) line=${line%"${line##*[![:space:]]}"};; esac
    case $line in ''|'#'*) continue;; esac
    globs+=("${line/#\~/$home}")
done < "$list"
[ ${#globs[@]} -gt 0 ] || { echo "protect-credentials: $list has no patterns" >&2; exit 2; }

# ---- matching ---------------------------------------------------------------
# Each glob becomes a bash pattern, built on first use (a Bash call with no
# glob in it never needs them). Claude Code's `**` spans ZERO or more
# directories, while a bash `*` sits between two literal slashes. Translate
# `/**/` to `/@(*/|)` so the zero-directory case matches too
# (~/Library/Application Support/**/electrum*/** must cover
# .../Application Support/electrum/wallets/x). A glob with any `/**` covers
# the whole subtree below its pattern; one without matches exactly.
shopt -s extglob
declare -a pats=() subtree=()
build_pats() {
    local g b
    for g in "${globs[@]}"; do
        b=${g%/\*\*}
        b=${b//\/\*\*\//\/@(*\/|)}
        pats+=("$b")
        if [ "$b" != "$g" ]; then subtree+=(1); else subtree+=(0); fi
    done
}

hit=
path_denied() {   # path_denied ABSOLUTE_PATH -> true, with $hit set to the glob, if it is protected
    local p=$1 i
    [ ${#pats[@]} -gt 0 ] || build_pats
    for i in "${!pats[@]}"; do
        if [[ $p == ${pats[i]} ]] || { (( subtree[i] )) && [[ $p == ${pats[i]}/* ]]; }; then
            hit=${globs[i]}; return 0
        fi
    done
    return 1
}

search_reaches() {   # search_reaches ABSOLUTE_DIR -> true, with $hit set, if a glob lies at or below it
    local r=${1%/} g lit prefix rest
    for g in "${globs[@]}"; do
        lit=${g%%[*?[]*}   # the literal part, up to the first wildcard
        # The literal part lies at or below the root: `/`, `~`, `~/.config`.
        if [[ $lit == "$r" || $lit == "$r"/* ]]; then hit=$g; return 0; fi
        # The root lies inside the wildcard part (~/Library/Application Support/
        # Google under .../**/metamask*/**): walk the glob one component at a time; a
        # root matching any leading part can reach what the rest names. `**` is
        # a bash `*` here and spans slashes, so it matches at any depth.
        [[ $lit != "$g" && $r == "$lit"* ]] || continue
        prefix= rest=${g#/}
        while [ -n "$rest" ]; do
            prefix+=/${rest%%/*}
            case $rest in */*) rest=${rest#*/};; *) rest=;; esac
            [[ $r == $prefix ]] && { hit=$g; return 0; }
        done
    done
    return 1
}

resolve() {   # resolve RAW_PATH -> sets $p to the absolute path, symlinks followed
    p=$1
    p=${p/#\~/$home}
    p=${p//\$HOME/$home}
    p=${p//\$\{HOME\}/$home}
    [ "${p:0:1}" = / ] || p=${cwd:-$PWD}/$p
    p=$(realpath -m -- "$p" 2>/dev/null) || p=$1
}

# ---- file tools: resolve the path and match ---------------------------------
if [ "$tool" != Bash ] && [ "$tool" != Monitor ]; then
    declare -a targets=() checked=()
    [ -n "${paths_joined:-}" ] && IFS=$'\x1f' read -ra targets <<<"$paths_joined"
    for raw in ${targets[@]+"${targets[@]}"}; do
        [ -n "$raw" ] && checked+=("$raw")
    done
    searching=
    case $tool in Grep|Glob) searching=1;; esac
    if [ -n "$searching" ] && [ ${#checked[@]} -eq 0 ]; then   # no path: it searches the cwd
        checked=("${cwd:-$PWD}")
        root_note=" (the session cwd; no path was given)"
    fi
    for raw in ${checked[@]+"${checked[@]}"}; do
        resolve "$raw"
        if path_denied "$p"; then
            deny "protect-credentials: $tool targets '$raw', which the protected-paths rule $hit covers. Add the path to $list only if it should be readable."
        fi
        if [ -n "$searching" ] && search_reaches "$p"; then
            deny "protect-credentials: $tool's search root '$raw'${root_note:-} contains protected credential locations (rule $hit), so a recursive search there would read them. Narrow the path to the directory you mean, such as the project directory."
        fi
    done
    exit 0
fi

# ---- Bash and Monitor: fail closed on any mention of a protected location ---
[ -n "${cmd:-}" ] || exit 0

# Each entry is an extended regex requiring path context, so naming a protected
# DIRECTORY without a trailing slash (`ls ~/.ssh`) still matches, while an
# unrelated word (`phantom gates`, `rg exodus docs/`) does not.
sep='(^|[^[:alnum:]_.-])'
prefix='(~|\$HOME|\$\{HOME\}|\.)?'
declare -a eres=(
  "${sep}${prefix}/?\.ssh(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.gnupg(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.aws(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.azure(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.config/gh(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.git-credentials"
  "${sep}${prefix}/?\.docker/config\.json"
  "${sep}${prefix}/?\.kube(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.npmrc"
  "${sep}${prefix}/?\.npm/"
  "${sep}${prefix}/?\.pypirc"
  "${sep}${prefix}/?\.gem/credentials"
  "${sep}${prefix}/?\.electrum(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.config/Exodus(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.config/BraveSoftware(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.config/google-chrome(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.config/chromium(/|\$|[^[:alnum:]_-])"
  "${sep}${prefix}/?\.mozilla/firefox(/|\$|[^[:alnum:]_-])"
  "/Library/Keychains(/|\$|[^[:alnum:]_-])"
  "/(metamask|electrum|exodus|phantom|solflare)[^/[:space:]]*/"
  "${sep}id_(rsa|dsa|ecdsa|ed25519)(\$|[^[:alnum:]_-])"
)

# The shell drops quotes and backslashes before it opens a path, so `~/.a''ws`,
# `~/.a"w"s`, `~/.a\ws` and a line continuation inside the name all reach it
# as ~/.aws. Test a stripped copy as well: grep matches line by line, so one
# pass over both copies joined by a newline equals two passes.
norm=${cmd//\\$'\n'/}
norm=${norm//[\'\"\\]/}
text=$cmd
[ "$norm" = "$cmd" ] || text+=$'\n'$norm

# One combined pass first: 21 separate greps cost ~50ms on every Bash call,
# and the overwhelmingly common answer is "no match". Only when the combined
# pattern hits do we loop to name the specific rule for the message.
combined=$(IFS='|'; printf '%s' "${eres[*]}")
if printf '%s' "$text" | grep -Eqi -- "$combined"; then
    for ere in "${eres[@]}"; do
        if printf '%s' "$text" | grep -Eqi -- "$ere"; then
            deny "protect-credentials: the command names a protected credential location (pattern /$ere/). Reading secrets is blocked in every permission mode; the list is $list."
        fi
    done
    # the combined pattern matched but no single one did: alternation cannot
    # lose a match, so this is unreachable — refuse rather than guess.
    deny "protect-credentials: the command matches the protected-location pattern set. Reading secrets is blocked in every permission mode; the list is $list."
fi

glob_denied() {   # glob_denied TEXT -> denies when a glob word rooted at ~, $HOME or / expands onto a protected path
    local w
    local -a words=() roots=() found=() lit_args=()
    read -ra words <<<"${1//[$'\n\t;|&<>()`=']/ }"
    for w in ${words[@]+"${words[@]}"}; do
        case $w in *[?*[]*) ;; *) continue;; esac
        case $w in
            '~/'*)       roots+=("$home${w:1}");;
            '$HOME/'*)   roots+=("$home${w:5}");;
            '${HOME}/'*) roots+=("$home${w:7}");;
            /*)          roots+=("$w");;
        esac
    done
    [ ${#roots[@]} -gt 0 ] || return 0
    # compgen -G only expands the pattern against the filesystem; nothing runs.
    mapfile -t found < <(for w in "${roots[@]}"; do compgen -G "$w"; done)
    [ ${#found[@]} -gt 0 ] || return 0
    # Check each result as written and with `..` and symlinks resolved (as the
    # file tools see paths). A glob can match thousands of files, and
    # path_denied costs ~0.4ms a path in bash, so grep -F first keeps only the
    # results containing some glob's literal part: one pass in C. xargs feeds
    # realpath in batches, so a huge expansion cannot exceed the exec argument
    # limit and silently skip the resolved check.
    for w in "${globs[@]}"; do w=${w%%[*?[]*}; lit_args+=(-e "${w%/}"); done
    mapfile -t found < <({ printf '%s\n' "${found[@]}"
                           printf '%s\0' "${found[@]}" | xargs -0 realpath -m -- 2>/dev/null; } \
                         | grep -F "${lit_args[@]}")
    for w in ${found[@]+"${found[@]}"}; do
        path_denied "$w" && deny_glob "$w"
    done
    return 0
}
deny_glob() {   # deny_glob EXPANDED_PATH
    deny "protect-credentials: a glob in the command expands to '$1', which the protected-paths rule $hit covers. Reading secrets is blocked in every permission mode; the list is $list."
}

# Globs name no protected path as text (`cat ~/.a?s/credentials`); expanding
# them is only worth its cost when the command has a glob character at all.
case $norm in *[?*[]*) glob_denied "$norm";; esac
exit 0
