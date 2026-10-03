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
#     glob.
#   * Bash: denies when the command text names a protected location. This is a
#     text test, not a path resolver, because the shell shapes that reach here
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
declare -a globs=()
while IFS= read -r line; do
    line=${line%%$'\r'}
    case $line in ''|'#'*) continue;; esac
    globs+=("${line/#\~/$home}")
done < "$list"
[ ${#globs[@]} -gt 0 ] || { echo "protect-credentials: $list has no patterns" >&2; exit 2; }

# ---- file tools: resolve the path and match ---------------------------------
shopt -s extglob
path_denied() {   # path_denied ABSOLUTE_PATH -> prints the matching glob
    local p=$1 g base
    for g in "${globs[@]}"; do
        base=${g%/\*\*}
        # Claude Code's `**` spans ZERO or more directories, while a bash `*`
        # sits between two literal slashes. Translate `/**/` to `/@(*/|)` so the
        # zero-directory case matches too (~/Library/Application Support/**/
        # electrum*/** must cover .../Application Support/electrum/wallets/x).
        base=${base//\/\*\*\//\/@(*\/|)}
        if [ "$base" != "${g%/\*\*}" ] || [ "$base" != "$g" ]; then
            [[ $p == $base || $p == $base/* ]] && { printf '%s' "$g"; return 0; }
        else
            [[ $p == $base ]] && { printf '%s' "$g"; return 0; }
        fi
    done
    return 1
}

if [ "$tool" != Bash ]; then
    declare -a targets=()
    [ -n "${paths_joined:-}" ] && IFS=$'\x1f' read -ra targets <<<"$paths_joined"
    for raw in ${targets[@]+"${targets[@]}"}; do
        [ -n "$raw" ] || continue
        p=$raw
        p=${p/#\~/$home}
        p=${p//\$HOME/$home}
        p=${p//\$\{HOME\}/$home}
        [ "${p:0:1}" = / ] || p=${cwd:-$PWD}/$p
        p=$(realpath -m -- "$p" 2>/dev/null) || p=$raw
        if hit=$(path_denied "$p"); then
            deny "protect-credentials: $tool targets '$raw', which the protected-paths rule $hit covers. Add the path to $list only if it should be readable."
        fi
    done
    exit 0
fi

# ---- Bash: fail closed on any mention of a protected location ---------------
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
# One combined pass first: 21 separate greps cost ~50ms on every Bash call,
# and the overwhelmingly common answer is "no match". Only when the combined
# pattern hits do we loop to name the specific rule for the message.
combined=$(IFS='|'; printf '%s' "${eres[*]}")
printf '%s' "$cmd" | grep -Eqi -- "$combined" || exit 0
for ere in "${eres[@]}"; do
    if printf '%s' "$cmd" | grep -Eqi -- "$ere"; then
        deny "protect-credentials: the command names a protected credential location (pattern /$ere/). Reading secrets is blocked in every permission mode; the list is $list."
    fi
done
# the combined pattern matched but no single one did: alternation cannot lose a
# match, so this is unreachable — refuse rather than guess.
deny "protect-credentials: the command matches the protected-location pattern set. Reading secrets is blocked in every permission mode; the list is $list."
