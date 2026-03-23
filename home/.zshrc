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

# Direnv
eval "$(direnv hook zsh)"

# Rust
export PATH="$HOME/.cargo/bin:$PATH"

# Java
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk

# Android SDK
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/emulator"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"

# zkstack completion
[[ -f "$HOME/.zsh/completion/_zkstack.zsh" ]] && source "$HOME/.zsh/completion/_zkstack.zsh"

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
        CLAUDE_CONFIG_DIR="$HOME/.claude-own" command claude "${args[@]}"
    elif [[ "$account" == "fna" ]]; then
        echo "Claude: using FNA account"
        CLAUDE_CONFIG_DIR="$HOME/.claude-fna" command claude "${args[@]}"
    else
        echo "Account: [1] FNA (default)  [2] OWN"
        read -r -k 1 "choice?"
        [[ "$choice" != $'\n' ]] && echo
        if [[ "$choice" == "2" ]]; then
            CLAUDE_CONFIG_DIR="$HOME/.claude-own" command claude "${args[@]}"
        else
            CLAUDE_CONFIG_DIR="$HOME/.claude-fna" command claude "${args[@]}"
        fi
    fi
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

# Weekly system settings sync check
_settings_sync_check() {
    local sync_dir="$HOME/Documents/Projects/system_settings"
    local stamp="$sync_dir/.last_sync"
    local now=$(date +%s)
    local week=$((7 * 24 * 60 * 60))

    if [[ ! -f "$stamp" ]] || (( now - $(cat "$stamp") > week )); then
        echo "\n\033[1;33m[system_settings]\033[0m Last sync was over a week ago."
        echo -n "Run sync now? [y/N] "
        read -r -k 1 answer
        [[ "$answer" != $'\n' ]] && echo
        if [[ "$answer" =~ [yY] ]]; then
            "$sync_dir/sync.sh"
            # Check if there are changes to commit
            if [[ -n "$(git -C "$sync_dir" status --porcelain)" ]]; then
                echo ""
                echo -n "Changes detected. Commit and push? [y/N] "
                read -r -k 1 answer2
                [[ "$answer2" != $'\n' ]] && echo
                if [[ "$answer2" =~ [yY] ]]; then
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

# Modern CLI aliases
alias ls='eza'
alias ll='eza -l --git'
alias la='eza -la --git'
alias tree='eza --tree'
alias cat='bat --paging=never --style=plain'
alias catp='bat'

# Timezone update + optional mirror sort
tzupdate() {
    command tzupdate "$@"
    echo -n "Sort Arch + EndeavourOS mirrors? [y/N] "
    read -r -k 1 answer
    [[ "$answer" != $'\n' ]] && echo
    if [[ "$answer" =~ [yY] ]]; then
        echo "Sorting Arch mirrors..."
        sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
        echo "Sorting EndeavourOS mirrors..."
        sudo eos-rankmirrors
    fi
}

# Zoxide (smart cd)
eval "$(zoxide init zsh)"

# Starship prompt
eval "$(starship init zsh)"

# System info on terminal open
fastfetch
