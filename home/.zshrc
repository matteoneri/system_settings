# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="amuse"

plugins=(git node postgres python aws terraform gpg-agent nvm)

# Lazy-load nvm via plugin
zstyle ':omz:plugins:nvm' lazy yes

source $ZSH/oh-my-zsh.sh

# Editor
export EDITOR='vim'

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
export PATH="$PATH:$ANDROID_HOME/tools"
export PATH="$PATH:$ANDROID_HOME/tools/bin"

# zkstack completion
source "$HOME/.zsh/completion/_zkstack.zsh"

# Claude CLI account auto-switch based on project directory
claude() {
    local dir="$PWD"
    if [[ "$dir" == */Projects/ActiveProjects/OWN/* || "$dir" == */Projects/ActiveProjects/OWN ]]; then
        echo "Claude: using OWN account"
        CLAUDE_CONFIG_DIR="$HOME/.claude-own" command claude "$@"
    elif [[ "$dir" == */Projects/ActiveProjects/FNA/* || "$dir" == */Projects/ActiveProjects/FNA ]]; then
        echo "Claude: using FNA account"
        CLAUDE_CONFIG_DIR="$HOME/.claude-fna" command claude "$@"
    else
        echo "Account: [1] FNA (default)  [2] OWN"
        read -r -k 1 "choice?"
        [[ "$choice" != $'\n' ]] && echo
        if [[ "$choice" == "2" ]]; then
            CLAUDE_CONFIG_DIR="$HOME/.claude-own" command claude "$@"
        else
            CLAUDE_CONFIG_DIR="$HOME/.claude-fna" command claude "$@"
        fi
    fi
}

# Project launcher
proj() { ~/.config/i3/scripts/project-launch "$@"; }

# Kitty background color based on project directory
_kitty_bg_for_dir() {
    [[ "$TERM" != "xterm-kitty" ]] && return
    local dir="$PWD"
    local bg
    if [[ "$dir" == */Projects/ActiveProjects/OWN/* || "$dir" == */Projects/ActiveProjects/OWN ]]; then
        bg="#0a0a1a"  # very dark blue for OWN
    elif [[ "$dir" == */Projects/ActiveProjects/FNA/* || "$dir" == */Projects/ActiveProjects/FNA ]]; then
        bg="#1a0a0a"  # very dark red for FNA
    else
        bg="#000000"  # black default
    fi
    kitty @ --to "unix:@kitty-$KITTY_PID" set-colors -a background="$bg" 2>/dev/null
}
autoload -U add-zsh-hook
add-zsh-hook chpwd _kitty_bg_for_dir
_kitty_bg_for_dir  # apply on shell start too

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
            echo "$now" > "$stamp"
            # Check if there are changes to commit
            if [[ -n "$(git -C "$sync_dir" status --porcelain)" ]]; then
                echo ""
                echo -n "Changes detected. Commit and push? [y/N] "
                read -r -k 1 answer2
                [[ "$answer2" != $'\n' ]] && echo
                if [[ "$answer2" =~ [yY] ]]; then
                    git -C "$sync_dir" add -A
                    git -C "$sync_dir" commit -m "Auto-sync $(date +%Y-%m-%d)"
                    git -C "$sync_dir" push 2>/dev/null || echo "No remote configured, skipping push."
                fi
            else
                echo "No changes detected."
            fi
        fi
    fi
}
_settings_sync_check

# System info on terminal open
archey4
