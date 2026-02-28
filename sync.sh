#!/usr/bin/env bash
# sync.sh - Pull latest config files from system into this repo
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$REPO_DIR/home"

echo "Syncing system configs to $REPO_DIR ..."

# Shell
cp ~/.zshrc "$HOME_DIR/.zshrc"
cp ~/.zsh/completion/_zkstack.zsh "$HOME_DIR/.zsh/completion/_zkstack.zsh"

# X11
cp ~/.Xresources "$HOME_DIR/.Xresources"

# Git (strip personal identity)
cp ~/.gitconfig "$HOME_DIR/.gitconfig"
sed -i 's/^\(\s*email\s*=\s*\).*/\1YOUR_EMAIL/' "$HOME_DIR/.gitconfig"
sed -i 's/^\(\s*name\s*=\s*\).*/\1YOUR_NAME/' "$HOME_DIR/.gitconfig"

# i3
cp ~/.config/i3/config "$HOME_DIR/.config/i3/config"
cp ~/.config/i3/scripts/* "$HOME_DIR/.config/i3/scripts/"

# Polybar
cp ~/.config/polybar/config.ini "$HOME_DIR/.config/polybar/config.ini"
cp ~/.config/polybar/launch.sh "$HOME_DIR/.config/polybar/launch.sh"

# Rofi
cp ~/.config/rofi/*.rasi "$HOME_DIR/.config/rofi/"

# Picom
cp ~/.config/picom/picom.conf "$HOME_DIR/.config/picom/picom.conf"

# Dunst
cp ~/.config/dunst/dunstrc "$HOME_DIR/.config/dunst/dunstrc"

# Newsboat
cp ~/.config/newsboat/config "$HOME_DIR/.config/newsboat/config"
cp ~/.config/newsboat/urls "$HOME_DIR/.config/newsboat/urls"

# Pacman & Paru
cp ~/.config/pacman/pacman.conf "$HOME_DIR/.config/pacman/pacman.conf"
cp ~/.config/paru/paru.conf "$HOME_DIR/.config/paru/paru.conf"

# Autostart
cp ~/.config/autostart/*.desktop "$HOME_DIR/.config/autostart/" 2>/dev/null || true

# Claude Code configs (no credentials)
cp ~/.claude-own/settings.json "$HOME_DIR/claude-code/own/settings.json"
cp ~/.claude-fna/settings.json "$HOME_DIR/claude-code/fna/settings.json"

# Screenlayout (optional)
cp ~/.screenlayout/monitor.sh "$HOME_DIR/.screenlayout/monitor.sh" 2>/dev/null || true

# Package lists
pacman -Qe --quiet | sort > "$REPO_DIR/packages-explicit.txt"
pacman -Qm --quiet | sort > "$REPO_DIR/packages-aur.txt"
comm -23 "$REPO_DIR/packages-explicit.txt" "$REPO_DIR/packages-aur.txt" > "$REPO_DIR/packages-official.txt"

echo "Done. Changes:"
cd "$REPO_DIR"
git diff --stat
git status --short
