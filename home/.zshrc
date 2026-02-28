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

# System info on terminal open
archey4
