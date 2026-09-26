#!/usr/bin/env bash
# restore.sh — Restore configs on a fresh Arch/EndeavourOS install, or a
# selected subset of components on any Unix (Debian-based hosts supported
# for the cross-platform components: shell, vim, git).
#
# Usage:
#   ./restore.sh                                    # same as --all (back-compat)
#   ./restore.sh --all                              # Arch packages + all desktop configs
#   ./restore.sh --packages                         # Arch packages only
#   ./restore.sh --configs                          # all desktop config components
#   ./restore.sh --configs --components shell,vim,git
#   ./restore.sh --configs --components fish        # claude/codex wrappers + projects-root loader
#   ./restore.sh --list-components
#
# Every run except --help and --list-components needs the projects root: an
# exported PROJECTS_ROOT, or a PROJECTS_ROOT= line in
# ~/.config/environment.d/50-projects-root.conf, other than $HOME itself. This
# repo must be <root>/system_settings (or a git worktree inside it). Otherwise
# restore stops before installing or writing anything.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$REPO_DIR/home"
# shellcheck source=lib/projects-root.sh
source "$REPO_DIR/lib/projects-root.sh"
ROOT=""  # the projects root, resolved after argument parsing

# Components run by --all / --configs (the Arch desktop workstation set).
# `shell` (portable) is intentionally absent — use --components shell on minimal hosts.
ALL_CONFIG_COMPONENTS=(
    shell-desktop
    fish
    vim
    git
    x11
    i3
    polybar
    rofi
    picom
    dunst
    newsboat
    pacman-conf
    paru-conf
    autostart
    claude
    codex
    screenlayout
    dev-tools
)

# Every registered component. Used for --list-components and validation.
KNOWN_COMPONENTS=(
    shell          # portable .zshrc + starship + zoxide + oh-my-zsh; apt or pacman
    shell-desktop  # full .zshrc + zkstack completion + oh-my-zsh; Arch
    fish           # claude/codex wrappers + projects-root loader into ~/.config/fish
    vim            # ensure vim is installed; apt or pacman
    git            # .gitconfig + user.name/email
    x11            # .Xresources + xrdb merge
    i3
    polybar
    rofi
    picom
    dunst
    newsboat
    pacman-conf    # /etc/pacman.conf via ~/.config/pacman
    paru-conf
    autostart
    claude         # settings, CLAUDE.md, scripts, hooks into ~/.claude-{own,fna}; prefs once logged in
    codex          # config + AGENTS.md into ~/.codex-{own,fna} + shared memory, root filled in
    screenlayout
    dev-tools      # pyenv, rustup, nvm
)

# ── helpers ──────────────────────────────────────────────────────
_have() { command -v "$1" &>/dev/null; }

_detect_pm() {
    if _have apt-get; then PM=apt
    elif _have pacman; then PM=pacman
    else
        echo "    ERROR: no supported package manager (apt or pacman) found" >&2
        return 1
    fi
}

_install() {
    _detect_pm
    case "$PM" in
        apt)    sudo apt-get install -y "$@" ;;
        pacman) sudo pacman -S --needed --noconfirm "$@" ;;
    esac
}

_require_arch() {
    if ! _have pacman; then
        echo "    SKIP: component '$1' is Arch-only (pacman not found)." >&2
        return 1
    fi
}

_contains() {
    local needle="$1"; shift
    local item
    for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
    return 1
}

# _fill SRC DEST: install SRC with every @PROJECTS_ROOT@ replaced by the root.
# DEST is replaced only once complete; the library names the file on failure.
_fill() {
    projects_root_fill "$ROOT" "$1" "$2" || exit 1
}

# _copy_keep_exec SRC DEST: copy SRC, and make DEST executable when SRC is
# (cp alone keeps an existing DEST's mode).
_copy_keep_exec() {
    cp "$1" "$2"
    if [[ -x "$1" ]]; then chmod +x "$2"; fi
}

# ── package install (Arch only) ──────────────────────────────────
install_packages() {
    if ! _have pacman; then
        echo "ERROR: --packages is Arch-only. Use --configs --components ... on non-Arch hosts." >&2
        exit 1
    fi
    echo "==> Installing official packages..."
    sudo pacman -S --needed - < "$REPO_DIR/packages-official.txt"

    echo ""
    echo "==> Installing AUR packages (via paru)..."
    if ! _have paru; then
        echo "    paru not found, installing it first..."
        sudo pacman -S --needed base-devel git
        tmp=$(mktemp -d)
        git clone https://aur.archlinux.org/paru.git "$tmp/paru"
        cd "$tmp/paru" && makepkg -si --noconfirm
        cd "$REPO_DIR"
        rm -rf "$tmp"
    fi
    paru -S --needed - < "$REPO_DIR/packages-aur.txt"
}

# ── components ───────────────────────────────────────────────────
restore_shell() {
    echo "==> shell (portable)..."
    _install zsh

    if ! _have starship; then
        echo "    Installing starship..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
    if ! _have zoxide; then
        echo "    Installing zoxide..."
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo "    Installing oh-my-zsh..."
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    cp "$HOME_DIR/.zshrc.portable" "$HOME/.zshrc"
    mkdir -p "$HOME/.config"
    cp "$HOME_DIR/.config/starship.toml" "$HOME/.config/starship.toml"
    echo "    Wrote ~/.zshrc and ~/.config/starship.toml"

    local zsh_path
    zsh_path="$(command -v zsh)"
    if [[ "${SHELL:-}" != "$zsh_path" ]]; then
        echo "    Changing login shell to $zsh_path (may prompt for password)..."
        chsh -s "$zsh_path" || echo "    WARN: chsh failed; run manually: chsh -s $zsh_path"
    fi
}

restore_shell_desktop() {
    echo "==> shell-desktop (full)..."
    _require_arch shell-desktop || return 0
    mkdir -p "$HOME/.zsh/completion"
    cp "$HOME_DIR/.zshrc" "$HOME/.zshrc"
    cp "$HOME_DIR/.zsh/completion/_zkstack.zsh" "$HOME/.zsh/completion/_zkstack.zsh"

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo "    Installing oh-my-zsh..."
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
}

# Only the tracked fish files (KTD14), never the whole functions directory. A
# file this checkout lacks is reported and skipped.
restore_fish() {
    echo "==> fish..."
    local rel
    for rel in .config/fish/functions/claude.fish \
               .config/fish/functions/codex.fish \
               .config/fish/conf.d/projects-root.fish; do
        if [[ ! -f "$HOME_DIR/$rel" ]]; then
            echo "    skip (not in repo): home/$rel"
            continue
        fi
        mkdir -p "$HOME/$(dirname "$rel")"
        cp "$HOME_DIR/$rel" "$HOME/$rel"
        echo "    Wrote ~/$rel"
    done
}

restore_vim() {
    echo "==> vim..."
    if _have vim; then
        echo "    vim already installed"
    else
        _install vim
    fi
}

restore_git() {
    echo "==> git..."
    cp "$HOME_DIR/.gitconfig" "$HOME/.gitconfig"

    local cur_name cur_email
    cur_name=$(git config --global user.name 2>/dev/null || true)
    cur_email=$(git config --global user.email 2>/dev/null || true)

    if [[ -n "$cur_name" && "$cur_name" != "YOUR_NAME" && -n "$cur_email" && "$cur_email" != "YOUR_EMAIL" ]]; then
        echo "    Git identity kept: $cur_name <$cur_email>"
    else
        read -rp "    Git user.name: " git_name
        read -rp "    Git user.email: " git_email
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
    fi
}

restore_x11() {
    echo "==> x11..."
    _require_arch x11 || return 0
    cp "$HOME_DIR/.Xresources" "$HOME/.Xresources"
    xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
}

restore_i3() {
    echo "==> i3..."
    _require_arch i3 || return 0
    mkdir -p "$HOME/.config/i3/scripts"
    cp "$HOME_DIR/.config/i3/config" "$HOME/.config/i3/config"
    cp "$HOME_DIR/.config/i3/scripts/"* "$HOME/.config/i3/scripts/"
    chmod +x "$HOME/.config/i3/scripts/"*
}

restore_polybar() {
    echo "==> polybar..."
    _require_arch polybar || return 0
    mkdir -p "$HOME/.config/polybar"
    cp "$HOME_DIR/.config/polybar/config.ini" "$HOME/.config/polybar/config.ini"
    cp "$HOME_DIR/.config/polybar/launch.sh" "$HOME/.config/polybar/launch.sh"
    chmod +x "$HOME/.config/polybar/launch.sh"
}

restore_rofi() {
    echo "==> rofi..."
    _require_arch rofi || return 0
    mkdir -p "$HOME/.config/rofi"
    cp "$HOME_DIR/.config/rofi/"*.rasi "$HOME/.config/rofi/"
}

restore_picom() {
    echo "==> picom..."
    _require_arch picom || return 0
    mkdir -p "$HOME/.config/picom"
    cp "$HOME_DIR/.config/picom/picom.conf" "$HOME/.config/picom/picom.conf"
}

restore_dunst() {
    echo "==> dunst..."
    _require_arch dunst || return 0
    mkdir -p "$HOME/.config/dunst"
    cp "$HOME_DIR/.config/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"
}

restore_newsboat() {
    echo "==> newsboat..."
    _require_arch newsboat || return 0
    mkdir -p "$HOME/.config/newsboat"
    cp "$HOME_DIR/.config/newsboat/config" "$HOME/.config/newsboat/config"
    cp "$HOME_DIR/.config/newsboat/urls" "$HOME/.config/newsboat/urls"
    cp "$HOME_DIR/.config/newsboat/config.datasave" "$HOME/.config/newsboat/config.datasave"
}

restore_pacman_conf() {
    echo "==> pacman-conf..."
    _require_arch pacman-conf || return 0
    mkdir -p "$HOME/.config/pacman"
    sudo cp "$HOME_DIR/.config/pacman/pacman.conf" "$HOME/.config/pacman/pacman.conf"
}

restore_paru_conf() {
    echo "==> paru-conf..."
    _require_arch paru-conf || return 0
    mkdir -p "$HOME/.config/paru"
    cp "$HOME_DIR/.config/paru/paru.conf" "$HOME/.config/paru/paru.conf"
}

restore_autostart() {
    echo "==> autostart..."
    _require_arch autostart || return 0
    mkdir -p "$HOME/.config/autostart"
    cp "$HOME_DIR/.config/autostart/"*.desktop "$HOME/.config/autostart/" 2>/dev/null || true
}

# _install_whole SRC DEST: replace DEST with a copy of SRC, SRC's mode included,
# in one rename, so a reader opening DEST meanwhile gets the old file or the new
# one, never half of one.
_install_whole() {
    local tmp
    tmp="$(mktemp -- "$(dirname -- "$2")/.$(basename -- "$2").XXXXXX")" || exit 1
    if cp -- "$1" "$tmp" && chmod --reference="$1" -- "$tmp" && mv -fT -- "$tmp" "$2"; then
        return 0
    fi
    rm -f -- "$tmp"
    echo "ERROR: could not install $2 from $1; $2 is unchanged" >&2
    exit 1
}

# The credential hooks live once in the repo (KTD11): real files under
# ~/.claude-fna/hooks/, and each ~/.claude-own/hooks/ entry a link to its FNA
# counterpart. The hook finds protected-paths.txt beside the path it was run
# by, so the list is linked too. Claude Code runs a hook on every tool call and
# lets the call through when the hook fails, so each file lands whole; ln -sfn
# swaps each link in by rename too.
_install_claude_hooks() {
    local src name
    mkdir -p "$HOME/.claude-fna/hooks" "$HOME/.claude-own/hooks"
    for src in "$HOME_DIR/claude-code/hooks/"*; do
        name="${src##*/}"
        _install_whole "$src" "$HOME/.claude-fna/hooks/$name"
        ln -sfn "$HOME/.claude-fna/hooks/$name" "$HOME/.claude-own/hooks/$name"
    done
    echo "    Installed the credential hooks into ~/.claude-fna/hooks, linked from ~/.claude-own/hooks"
}

# Merge the tracked preferences into an account's .claude.json, which only
# exists once the account has logged in.
_merge_claude_prefs() {
    local acct="$1" target prefs
    target="$HOME/.claude-${acct}/.claude.json"
    prefs="$HOME_DIR/claude-code/${acct}/preferences.json"
    if [[ ! -f "$prefs" ]]; then
        echo "    No preferences.json for claude-${acct} in this checkout; nothing to merge"
    elif [[ -f "$target" ]]; then
        python3 - "$target" "$prefs" <<'EOF'
import json, sys
target, prefs = sys.argv[1], sys.argv[2]
with open(target) as f: data = json.load(f)
with open(prefs) as f: data.update(json.load(f))
with open(target, 'w') as f: json.dump(data, f, indent=2); f.write('\n')
EOF
        echo "    Merged preferences into $target"
    else
        echo "    Preferences not merged into claude-${acct} (log in first with: CLAUDE_CONFIG_DIR=~/.claude-${acct} claude, then run --components claude again)"
    fi
}

# Everything but the preferences installs whether or not the account has
# logged in (KTD10). The hooks go first: settings.json calls them on every
# tool call.
restore_claude() {
    echo "==> claude..."
    if ! _have jq; then
        echo "ERROR: the claude component needs jq: the credential hook its settings call parses every tool call with jq and blocks the call without it. Install jq (on Arch: sudo pacman -S jq), then run restore.sh again. Nothing was installed for claude." >&2
        exit 1
    fi
    _install_claude_hooks
    local acct dir
    for acct in own fna; do
        dir="$HOME/.claude-${acct}"
        mkdir -p "$dir"
        _copy_keep_exec "$HOME_DIR/claude-code/${acct}/statusline.sh" "$dir/statusline.sh"
        _copy_keep_exec "$HOME_DIR/claude-code/${acct}/title-hook.sh" "$dir/title-hook.sh"
        _fill "$HOME_DIR/claude-code/${acct}/CLAUDE.md" "$dir/CLAUDE.md"
        _fill "$HOME_DIR/claude-code/${acct}/settings.json" "$dir/settings.json"
        echo "    Wrote settings.json, CLAUDE.md, statusline.sh and title-hook.sh into ~/.claude-${acct}"
        _merge_claude_prefs "$acct"
    done
}

restore_codex() {
    echo "==> codex..."
    mkdir -p "$HOME/.codex-own" "$HOME/.codex-fna" "$HOME/.codex-shared/skills"
    local acct
    for acct in own fna; do
        _fill "$HOME_DIR/codex/${acct}/config.toml" "$HOME/.codex-${acct}/config.toml"
        _fill "$HOME_DIR/codex/${acct}/AGENTS.md" "$HOME/.codex-${acct}/AGENTS.md"
    done
    _fill "$HOME_DIR/codex/shared/MEMORY.md" "$HOME/.codex-shared/MEMORY.md"
    # The shell wrapper always sets CODEX_HOME; this symlink is what a codex started
    # outside it (an i3 restore, a script) falls back to.
    [ -e "$HOME/.codex" ] || ln -s .codex-own "$HOME/.codex"
    echo "    Authenticate each account: codex --own  /  codex --fna, then /login"
}

restore_screenlayout() {
    echo "==> screenlayout..."
    mkdir -p "$HOME/.screenlayout"
    if [ -f "$HOME_DIR/.screenlayout/monitor.sh" ]; then
        cp "$HOME_DIR/.screenlayout/monitor.sh" "$HOME/.screenlayout/monitor.sh"
        chmod +x "$HOME/.screenlayout/monitor.sh"
    fi
}

restore_dev_tools() {
    echo "==> dev-tools..."
    if [ ! -d "$HOME/.pyenv" ]; then
        echo "    Installing pyenv..."
        curl https://pyenv.run | bash
    else
        echo "    pyenv already installed"
    fi
    if ! _have rustup; then
        echo "    Installing rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    else
        echo "    rustup already installed"
    fi
    if [ ! -d "${NVM_DIR:-$HOME/.nvm}" ]; then
        echo "    Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    else
        echo "    nvm already installed"
    fi
}

# ── dispatch ─────────────────────────────────────────────────────
run_component() {
    local name="$1"
    # Map dashes to underscores for function names (shell-desktop → shell_desktop).
    local fn="restore_${name//-/_}"
    if ! declare -F "$fn" >/dev/null; then
        echo "ERROR: unknown component '$name'. Run --list-components to see options." >&2
        exit 1
    fi
    "$fn"
}

list_components() {
    echo "Known components:"
    local c
    for c in "${KNOWN_COMPONENTS[@]}"; do
        local in_all=""
        _contains "$c" "${ALL_CONFIG_COMPONENTS[@]}" && in_all=" (in --all)"
        printf "  %-14s%s\n" "$c" "$in_all"
    done
    echo ""
    echo "Cross-platform (apt or pacman): shell, vim, git"
    echo "All others are Arch-only and will skip on non-Arch hosts."
}

# ── arg parsing ──────────────────────────────────────────────────
do_packages=false
do_configs=false
components=""

# If no args, behave like --all (back-compat with old invocations).
if [[ $# -eq 0 ]]; then
    do_packages=true
    do_configs=true
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)               do_packages=true; do_configs=true; shift ;;
        --packages)          do_packages=true;  shift ;;
        --configs)           do_configs=true;   shift ;;
        --components)
            components="$2"
            do_configs=true
            shift 2
            ;;
        --list-components)   list_components; exit 0 ;;
        -h|--help)
            sed -n '2,19p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Run: $0 --help" >&2
            exit 1
            ;;
    esac
done

# ── projects root ────────────────────────────────────────────────
# Resolve before the package step and every component, so an unset or wrong
# root stops the run before anything is installed or written (R4). A root that
# does not hold this repo as its system_settings would fill the configs in with
# paths that lead nowhere (R3).
ROOT="$(projects_root_resolve)" || exit 1
if ! projects_root_check_repo "$ROOT" "$REPO_DIR"; then
    echo "Nothing was restored." >&2
    exit 1
fi
echo "==> Projects root: $ROOT"

# ── run ──────────────────────────────────────────────────────────
$do_packages && install_packages

if $do_configs; then
    if [[ -n "$components" ]]; then
        IFS=',' read -ra selected <<< "$components"
        for c in "${selected[@]}"; do
            c="${c// /}"  # strip whitespace
            [[ -z "$c" ]] && continue
            if ! _contains "$c" "${KNOWN_COMPONENTS[@]}"; then
                echo "ERROR: unknown component '$c'. Run --list-components." >&2
                exit 1
            fi
            run_component "$c"
        done
    else
        for c in "${ALL_CONFIG_COMPONENTS[@]}"; do
            run_component "$c"
        done
    fi
fi

echo ""
echo "==> Post-install reminders:"
if $do_configs; then
    if [[ -z "$components" ]] || [[ ",$components," == *,shell-desktop,* ]] || [[ ",$components," == *,shell,* ]]; then
        echo "    - Log out and back in (or 'exec zsh') to pick up the new shell"
    fi
    if [[ -z "$components" ]]; then
        echo "    - Configure monitors with arandr and save to ~/.screenlayout/monitor.sh"
        echo "    - Enable services: systemctl enable --now NetworkManager bluetooth docker tailscaled nordvpnd"
        echo "    - Set up Claude Code accounts: run 'claude' and authenticate"
    fi
fi
echo ""
echo "All done!"
