#!/usr/bin/env bash
# restore.sh - Restore all configs on a fresh Arch/EndeavourOS install
# Usage: ./restore.sh [--packages] [--configs] [--all]
#   --packages  Install all packages
#   --configs   Copy config files to their system locations
#   --all       Do both (default if no flag given)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$REPO_DIR/home"

do_packages=false
do_configs=false

case "${1:---all}" in
    --packages) do_packages=true ;;
    --configs)  do_configs=true ;;
    --all)      do_packages=true; do_configs=true ;;
    *)          echo "Usage: $0 [--packages|--configs|--all]"; exit 1 ;;
esac

# ── Install packages ──────────────────────────────────────────────
install_packages() {
    echo "==> Installing official packages..."
    sudo pacman -S --needed - < "$REPO_DIR/packages-official.txt"

    echo ""
    echo "==> Installing AUR packages (via paru)..."
    if ! command -v paru &>/dev/null; then
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

# ── Restore config files ─────────────────────────────────────────
restore_configs() {
    echo "==> Restoring config files..."

    # Create target directories
    mkdir -p \
        ~/.config/i3/scripts \
        ~/.config/polybar \
        ~/.config/rofi \
        ~/.config/picom \
        ~/.config/kitty \
        ~/.config/dunst \
        ~/.config/newsboat \
        ~/.config/pacman \
        ~/.config/paru \
        ~/.config/autostart \
        ~/.zsh/completion \
        ~/.screenlayout \
        ~/.claude-own \
        ~/.claude-fna

    # Shell
    cp "$HOME_DIR/.zshrc" ~/.zshrc
    cp "$HOME_DIR/.zsh/completion/_zkstack.zsh" ~/.zsh/completion/_zkstack.zsh

    # X11
    cp "$HOME_DIR/.Xresources" ~/.Xresources
    xrdb -merge ~/.Xresources 2>/dev/null || true

    # Git
    cp "$HOME_DIR/.gitconfig" ~/.gitconfig

    # i3
    cp "$HOME_DIR/.config/i3/config" ~/.config/i3/config
    cp "$HOME_DIR/.config/i3/scripts/"* ~/.config/i3/scripts/
    chmod +x ~/.config/i3/scripts/*

    # Polybar
    cp "$HOME_DIR/.config/polybar/config.ini" ~/.config/polybar/config.ini
    cp "$HOME_DIR/.config/polybar/launch.sh" ~/.config/polybar/launch.sh
    chmod +x ~/.config/polybar/launch.sh

    # Rofi
    cp "$HOME_DIR/.config/rofi/"*.rasi ~/.config/rofi/

    # Picom
    cp "$HOME_DIR/.config/picom/picom.conf" ~/.config/picom/picom.conf

    # Dunst
    cp "$HOME_DIR/.config/dunst/dunstrc" ~/.config/dunst/dunstrc

    # Newsboat
    cp "$HOME_DIR/.config/newsboat/config" ~/.config/newsboat/config
    cp "$HOME_DIR/.config/newsboat/urls" ~/.config/newsboat/urls

    # Pacman & Paru
    sudo cp "$HOME_DIR/.config/pacman/pacman.conf" ~/.config/pacman/pacman.conf
    cp "$HOME_DIR/.config/paru/paru.conf" ~/.config/paru/paru.conf

    # Autostart
    cp "$HOME_DIR/.config/autostart/"*.desktop ~/.config/autostart/ 2>/dev/null || true

    # Claude Code
    cp "$HOME_DIR/claude-code/own/settings.json" ~/.claude-own/settings.json
    cp "$HOME_DIR/claude-code/fna/settings.json" ~/.claude-fna/settings.json

    # Screenlayout
    if [ -f "$HOME_DIR/.screenlayout/monitor.sh" ]; then
        cp "$HOME_DIR/.screenlayout/monitor.sh" ~/.screenlayout/monitor.sh
        chmod +x ~/.screenlayout/monitor.sh
    fi

    echo ""
    echo "==> Setting up Oh My Zsh..."
    if [ ! -d ~/.oh-my-zsh ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        echo "    Oh My Zsh already installed, skipping."
    fi

    echo ""
    echo "==> Setting up pyenv..."
    if [ ! -d ~/.pyenv ]; then
        curl https://pyenv.run | bash
    else
        echo "    pyenv already installed, skipping."
    fi

    echo ""
    echo "==> Setting up Rust..."
    if ! command -v rustup &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    else
        echo "    Rust already installed, skipping."
    fi

    echo ""
    echo "==> Setting up NVM..."
    if [ ! -d "${NVM_DIR:-$HOME/.nvm}" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    else
        echo "    NVM already installed, skipping."
    fi

    echo ""
    echo "==> Post-install reminders:"
    echo "    - Set zsh as default shell:  chsh -s \$(which zsh)"
    echo "    - Log out and back in for i3 changes to take effect"
    echo "    - Run 'xrdb -merge ~/.Xresources' to apply X settings"
    echo "    - Configure monitors with arandr and save to ~/.screenlayout/monitor.sh"
    echo "    - Enable services: systemctl enable --now NetworkManager bluetooth docker tailscaled nordvpnd"
    echo "    - Set up Claude Code accounts: run 'claude' and authenticate"
}

# ── Run ───────────────────────────────────────────────────────────
$do_packages && install_packages
$do_configs && restore_configs

echo ""
echo "All done!"
