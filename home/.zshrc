# Projects root: PROJECTS_ROOT is this machine's projects folder, the one that
# holds ActiveProjects/ and system_settings/. An exported value wins; otherwise
# the last PROJECTS_ROOT= line of ~/.config/environment.d/50-projects-root.conf,
# the file the systemd user session reads too. These are the rules of
# projects_root_resolve in system_settings' lib/projects-root.sh, which this
# file cannot source (the repo's own path comes from the root), so keep the two
# in step: surrounding whitespace and one pair of quotes are stripped as systemd
# does, a leading ~, $HOME or ${HOME} expands, the path is normalised, and a
# relative path, / or a missing directory is refused. Unresolved, PROJECTS_ROOT
# is unset so the steps below that need it skip, and an interactive terminal
# gets one warning line. Nothing prints anywhere else: Claude Code snapshots
# these functions into non-interactive tool shells.

# Set REPLY to the value of FILE's last PROJECTS_ROOT= line; 1 when it has none.
_projects_root_declared() {
    emulate -L zsh
    setopt extendedglob
    local line found=1
    [[ -r $1 ]] || return 1
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line == [[:space:]]#PROJECTS_ROOT[[:space:]]#=* ]]; then
            REPLY=${line#*=}
            found=0
        fi
    done < $1
    (( found == 0 )) || return 1
    REPLY=${${REPLY##[[:space:]]##}%%[[:space:]]##}
    [[ $REPLY == (\"*\"|\'*\') ]] && REPLY=${REPLY[2,-2]}
    return 0
}

# Set REPLY to VALUE expanded and normalised, or to why it is refused and
# return 1. ORIGIN (exported or declared) goes into that message.
_projects_root_normalise() {
    emulate -L zsh
    local value=$1 origin=$2 root
    case $value in
        ('~'|'~/'*)             value=$HOME${value:1} ;;
        ('$HOME'|'$HOME/'*)     value=$HOME${value:5} ;;
        ('${HOME}'|'${HOME}/'*) value=$HOME${value:7} ;;
    esac
    if [[ $value != /* ]]; then
        REPLY="PROJECTS_ROOT='$value' ($origin) is not an absolute path"
        return 1
    fi
    root=$(command realpath -s -m -- $value 2>/dev/null)
    if [[ -z $root || $root == / ]]; then
        REPLY="PROJECTS_ROOT='$value' ($origin) does not name a projects folder"
        return 1
    fi
    if [[ ! -d $root ]]; then
        REPLY="PROJECTS_ROOT='$root' ($origin) is not an existing directory"
        return 1
    fi
    REPLY=$root
}

_projects_root_load() {
    emulate -L zsh
    local file=$HOME/.config/environment.d/50-projects-root.conf REPLY origin
    if [[ -n $PROJECTS_ROOT ]]; then
        REPLY=$PROJECTS_ROOT origin=exported
    elif _projects_root_declared $file; then
        origin=declared
    else
        REPLY='PROJECTS_ROOT is not set (neither exported nor declared)'
    fi
    if [[ -n $origin ]] && _projects_root_normalise $REPLY $origin; then
        export PROJECTS_ROOT=$REPLY
        return 0
    fi
    unset PROJECTS_ROOT
    [[ -o interactive && -t 0 ]] || return 0
    print -ru2 -- $'\e[1;33m[projects-root]\e[0m '"$REPLY; skipping the system_settings sync check and terminal titles. Declare it in $file with a line like PROJECTS_ROOT=\${HOME}/path/to/projects (an exported PROJECTS_ROOT takes precedence over the file)."
}
_projects_root_load

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

plugins=(git node postgres python aws terraform gpg-agent nvm)

# Lazy-load nvm via plugin
zstyle ':omz:plugins:nvm' lazy yes

source "$ZSH/oh-my-zsh.sh"

# Editor
export EDITOR='nvim'
export VISUAL='nvim'
alias vim='nvim'

# Pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Force AUR builds to use system Python (avoids pyenv shims breaking
# g-ir-scanner et al.). See memory: pyenv-aur-shadowing.md.
alias paru='PYENV_VERSION=system paru'
alias makepkg='PYENV_VERSION=system makepkg'

# Direnv
eval "$(direnv hook zsh)"

# Rust
export PATH="$HOME/.cargo/bin:$PATH"
export SCCACHE_CACHE_SIZE="40G"

# Android SDK
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/emulator"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"

# zkstack completion
[[ -f "$HOME/.zsh/completion/_zkstack.zsh" ]] && source "$HOME/.zsh/completion/_zkstack.zsh"

# Claude Code: shared ephemeral scratch dir. Avoids the startup error when the
# intel-hub containers pre-create /tmp/claude-1000 as root. Shared by FNA and
# OWN accounts — safe, because this holds only per-session scratch; conversation
# history lives in $CLAUDE_CONFIG_DIR (~/.claude-fna vs ~/.claude-own), not here.
export CLAUDE_CODE_TMPDIR="$HOME/.cache/claude-tmp"
[[ -d "$CLAUDE_CODE_TMPDIR" ]] || mkdir -p "$CLAUDE_CODE_TMPDIR"

# Claude CLI account auto-switch based on project directory
claude() {
    local account=""
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --own) account="own" ;;
            --fna) account="fna" ;;
            *) args+=("$arg") ;;
        esac
    done

    if [[ -z "$account" ]]; then
        local dir="$PWD"
        if [[ "$dir" == */Projects/ActiveProjects/OWN/* || "$dir" == */Projects/ActiveProjects/OWN ]]; then
            account="own"
        elif [[ "$dir" == */Projects/ActiveProjects/FNA/* || "$dir" == */Projects/ActiveProjects/FNA ]]; then
            account="fna"
        fi
    fi

    if [[ "$account" == "own" ]]; then
        echo "Claude: using OWN account"
        CLAUDE_CONFIG_DIR="$HOME/.claude-own" command claude --dangerously-skip-permissions "${args[@]}"
    elif [[ "$account" == "fna" ]]; then
        echo "Claude: using FNA account"
        CLAUDE_CONFIG_DIR="$HOME/.claude-fna" command claude --dangerously-skip-permissions "${args[@]}"
    else
        echo "Account: [1] FNA (default)  [2] OWN"
        read -r -k 1 "choice?"
        [[ "$choice" != $'\n' ]] && echo
        if [[ "$choice" == "2" ]]; then
            CLAUDE_CONFIG_DIR="$HOME/.claude-own" command claude --dangerously-skip-permissions "${args[@]}"
        else
            CLAUDE_CONFIG_DIR="$HOME/.claude-fna" command claude --dangerously-skip-permissions "${args[@]}"
        fi
    fi
}

# Codex CLI account auto-switch based on project directory. Mirrors claude() above:
# codex keeps account, history, config and sessions under $CODEX_HOME
# (~/.codex-own vs ~/.codex-fna). ~/.codex is a symlink to the OWN home, so a
# codex started outside this function — an i3 restore, a script — still lands
# somewhere real instead of creating an empty home.
codex() {
    local account=""
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --own) account="own" ;;
            --fna) account="fna" ;;
            *) args+=("$arg") ;;
        esac
    done

    if [[ -z "$account" ]]; then
        local dir="$PWD"
        if [[ "$dir" == */Projects/ActiveProjects/OWN/* || "$dir" == */Projects/ActiveProjects/OWN ]]; then
            account="own"
        elif [[ "$dir" == */Projects/ActiveProjects/FNA/* || "$dir" == */Projects/ActiveProjects/FNA ]]; then
            account="fna"
        fi
    fi

    if [[ -n "$account" ]]; then
        echo "Codex: using ${account:u} account"
    else
        echo "Account: [1] FNA (default)  [2] OWN"
        read -r -k 1 "choice?"
        [[ "$choice" != $'\n' ]] && echo
        if [[ "$choice" == "2" ]]; then account="own"; else account="fna"; fi
    fi

    CODEX_HOME="$HOME/.codex-$account" command codex "${args[@]}"
}

# Project launcher
proj() { ~/.config/i3/scripts/project-launch "$@"; }

# Kitty theme based on project directory
_kitty_theme_for_dir() {
    [[ "$TERM" != "xterm-kitty" ]] && return
    local dir="$PWD"
    local theme
    if [[ "$dir" == */Projects/ActiveProjects/OWN/* || "$dir" == */Projects/ActiveProjects/OWN ]]; then
        theme="$HOME/.config/kitty/themes/Dayfox.conf"
    elif [[ "$dir" == */Projects/ActiveProjects/FNA/* || "$dir" == */Projects/ActiveProjects/FNA ]]; then
        theme="$HOME/.config/kitty/themes/Hachiko.conf"
    else
        theme="$HOME/.config/kitty/themes/GithubDark.conf"
    fi
    kitty @ --to "unix:@kitty-$KITTY_PID" set-colors -a "$theme" 2>/dev/null
}

# Default browser based on project directory
_browser_for_dir() {
    local dir="$PWD"
    if [[ "$dir" == */Projects/ActiveProjects/FNA/* || "$dir" == */Projects/ActiveProjects/FNA ]]; then
        export BROWSER="firefox"
    else
        export BROWSER="brave"
    fi
}

# Auto-detect venv on cd (skip if direnv handles it)
_auto_venv_check() {
    [[ -f .envrc ]] && return
    [[ -n "$VIRTUAL_ENV" ]] && return

    local venv_dir=""
    for dir in .venv venv env .env; do
        if [[ -f "$dir/bin/activate" ]]; then
            venv_dir="$dir"
            break
        fi
    done
    [[ -z "$venv_dir" ]] && return

    read -q "reply?Virtual env found ($venv_dir). Activate? [y/N] "
    echo
    [[ "$reply" == "y" ]] && source "$venv_dir/bin/activate"
}

autoload -U add-zsh-hook
add-zsh-hook chpwd _kitty_theme_for_dir
add-zsh-hook chpwd _browser_for_dir
add-zsh-hook chpwd _auto_venv_check
_kitty_theme_for_dir  # apply on shell start too
_browser_for_dir
_auto_venv_check

# _ask_yn "<prompt>"  ->  0 on y/Y, 1 on anything else. One keystroke, read only
# after discarding whatever was typed while the terminal was starting up, so a
# command that happens to begin with y is not taken as the answer. Every
# startup prompt in this file asks through here.
_ask_yn() {
    local answer discard
    while read -t -k 1 -s discard; do :; done
    echo -n "$1"
    read -r -k 1 answer
    [[ "$answer" != $'\n' ]] && echo
    [[ "$answer" =~ [yY] ]]
}

# Weekly system settings sync check. Interactive terminals only, and Ctrl-C
# returns from the function rather than aborting the rest of this file -- the
# same two guards the mirror prompt below carries, for the same reasons.
# Skipped when PROJECTS_ROOT is unset; the loader at the top has warned.
_settings_sync_check() {
    [[ -o interactive && -t 0 ]] || return 0
    [[ -n "$PROJECTS_ROOT" ]] || return 0
    setopt localtraps
    trap 'return 1' INT
    local sync_dir="$PROJECTS_ROOT/system_settings"
    local stamp="$sync_dir/.last_sync"
    local now=$(date +%s)
    local week=$((7 * 24 * 60 * 60))

    if [[ ! -f "$stamp" ]] || (( now - $(cat "$stamp") > week )); then
        echo "\n\033[1;33m[system_settings]\033[0m Last sync was over a week ago."
        if _ask_yn "Run sync now? [y/N] "; then
            # A sync that stops has written nothing: offer no commit and keep
            # the old stamp, so the next terminal asks again.
            if ! "$sync_dir/sync.sh"; then
                echo "sync.sh stopped; nothing to commit. The next terminal will ask again."
                return 1
            fi
            # Check if there are changes to commit
            if [[ -n "$(git -C "$sync_dir" status --porcelain)" ]]; then
                echo ""
                if _ask_yn "Changes detected. Commit and push? [y/N] "; then
                    git -C "$sync_dir" add -A
                    git -C "$sync_dir" commit -m "Auto-sync $(date +%Y-%m-%d)"
                    git -C "$sync_dir" push
                    echo "$now" > "$stamp"
                fi
            else
                echo "No changes detected."
                echo "$now" > "$stamp"
            fi
        fi
    fi
}
_settings_sync_check

# Mirror re-rank prompt. Asks at every new terminal until a re-rank succeeds:
# it arms when the timezone changed or the ranking is over 30 days old. The
# script owns that logic and the state; this only asks and relays. Interactive
# terminals only -- Claude Code snapshots zshrc functions into non-interactive
# tool shells, and a blocking read there would hang them. See
# docs/plans/2026-09-18-001-feat-mirror-rerank-prompt-plan.md in system_settings.
_mirror_rerank_check() {
    [[ -o interactive && -t 0 ]] || return 0
    # Ctrl-C at the prompt, or during the run, must return from this function,
    # not abort the rest of .zshrc: the aliases, zoxide, starship and fastfetch
    # below this call would otherwise be skipped for that shell.
    setopt localtraps
    trap 'return 1' INT
    local bin="${MIRROR_RERANK_BIN:-$HOME/.config/i3/scripts/mirror-rerank}"
    local reasons rc
    reasons="$("$bin" status 2>/dev/null)"
    rc=$?
    case $rc in
        0) ;;
        1) return 0 ;;
        *)
            echo "\n\033[1;33m[mirrors]\033[0m mirror-rerank is missing or broken (exit $rc); mirrors are not being checked."
            return 0
            ;;
    esac
    echo "\n\033[1;33m[mirrors]\033[0m A mirror re-rank is due:"
    print -r -- "$reasons"
    if _ask_yn "Update mirrors now? [y/N] "; then
        "$bin" run
    fi
}
_mirror_rerank_check

# Modern CLI aliases
# `ls` is deliberately NOT aliased to eza: eza's -t is --time FIELD, not sort-by-mtime,
# so `ls -t` silently fails and scripts/agents parsing it get an empty result.
alias ll='eza -l --git'
alias la='eza -la --git'
alias tree='eza --tree'
alias cat='bat --paging=never --style=plain'
alias catp='bat'

# Zoxide (smart cd)
eval "$(zoxide init zsh)"

# Starship prompt
eval "$(starship init zsh)"

# Claude Code terminal titles: keep the task title Claude sets, instead of letting
# oh-my-zsh re-title on every prompt. Sourced last so its precmd hook runs after
# starship's and wins. The hook ships with the claude-code-terminal-title project
# in $PROJECTS_ROOT/ActiveProjects/OWN; skipped when PROJECTS_ROOT is unset or the
# project is not checked out.
[[ -n "$PROJECTS_ROOT" && -f "$PROJECTS_ROOT/ActiveProjects/OWN/claude-code-terminal-title/shell/terminal-title.zsh" ]] \
    && source "$PROJECTS_ROOT/ActiveProjects/OWN/claude-code-terminal-title/shell/terminal-title.zsh"

# CBUAE Windows VM control: cbuae up|down|console|status|restart|kill|shot
source "$HOME/VMs/cbuae-vm.zsh"

# System info on terminal open
fastfetch

# Machine-local secrets and overrides (API keys etc.) — not synced to system_settings
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
