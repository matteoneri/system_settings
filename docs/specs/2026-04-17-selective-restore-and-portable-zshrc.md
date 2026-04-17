# Selective restore + portable zshrc

**Date:** 2026-04-17
**Goal:** Make `system_settings` usable on non-Arch, non-desktop hosts (e.g. Raspberry Pi) by (a) letting `restore.sh` install a chosen subset of components and (b) shipping a portable `.zshrc` that works without Arch/i3/kitty dependencies.

## Motivation

Today `restore.sh --configs` is all-or-nothing and assumes Arch + i3 + kitty + the user's desktop layout. Deploying only a shell config to a headless Pi requires hand-editing the script. The first real test target is a Raspbian 11 Pi where `vim` and `git` exist but `zsh` does not.

## Scope

Two changes in the `system_settings` repo:

1. **`restore.sh`** — refactor into per-component functions and add a `--components` selector.
2. **`home/.zshrc.portable`** — new file, a minimal defensive zshrc that the `shell` component deploys.

The existing `home/.zshrc` (full desktop version) stays untouched. `--all` continues to deploy the full `.zshrc` as it does today.

## Design

### `restore.sh`

Each config block inside `restore_configs` becomes its own function:

| Component | What it does |
|---|---|
| `shell` | Portable variant. Cross-platform (apt/pacman detect). Installs `zsh`, `starship`, `zoxide`. Sets up oh-my-zsh. Copies `.zshrc.portable` → `~/.zshrc`. Runs `chsh -s "$(which zsh)"` if the current login shell isn't zsh. |
| `shell-desktop` | Full desktop variant. Arch-only. Copies `.zshrc` (full) and `_zkstack.zsh` completion. Assumes `dev-tools` ran or will run for pyenv/nvm/rust. Does not install oh-my-zsh (handled by `dev-tools`). |
| `vim` | Ensures `vim` is installed (apt/pacman detect). No config file today (none in repo). |
| `git` | Copies `.gitconfig`, prompts for `user.name` / `user.email` (current behavior). |
| `i3` | Arch/desktop-only. Copies i3 config + scripts. |
| `polybar`, `rofi`, `picom`, `kitty`, `dunst`, `newsboat`, `autostart`, `screenlayout` | Arch/desktop-only. One per current block. |
| `pacman`, `paru` | Arch-only. Copies pacman/paru configs. |
| `claude` | Merges Claude Code preferences into `~/.claude-{own,fna}/.claude.json`. |
| `dev-tools` | Installs pyenv, rust (rustup), nvm. |

**Flag surface:**

```
./restore.sh                              # same as --all (back-compat)
./restore.sh --all                        # packages + every component
./restore.sh --configs                    # every component, no packages
./restore.sh --configs --components shell,vim,git
./restore.sh --list-components
./restore.sh --packages                   # unchanged, Arch-only
```

`--packages` remains Arch-only and errors out clearly on non-Arch. Per-component installs inside `shell`/`vim` handle their own cross-platform dependency install so those two work on Debian out of the box.

**`--all` vs `--components`.** `--all` runs the full desktop set, including `shell-desktop` (full `.zshrc`) — **not** `shell`. The portable `shell` component is only invoked when explicitly requested via `--components`. This preserves today's behavior on the Arch workstation (`--all` still copies the full `.zshrc`) while making the portable variant available for minimal/server hosts. `--list-components` shows both and notes which are included in `--all`.

### `home/.zshrc.portable`

Minimal, defensive, one file, no host-specific assumptions. Keeps:

- Oh-my-zsh core with plugins: `git`, `node`, `python` (drop the desktop/AWS/Terraform/GPG plugins on Pi-class hosts).
- `EDITOR` / `VISUAL` set to `vim` (falls back gracefully — `nvim` is not installed on Pi). If `nvim` is present, prefer it.
- `starship` / `zoxide` init, each behind `command -v …` guards.
- Aliases with fallbacks: `ls`/`ll`/`la`/`tree` only aliased if `eza` is installed; `cat` only aliased if `bat` is installed.
- History configuration (size + dedup + shared).

Drops entirely: pyenv, direnv, rust, java, android, zkstack completion, kitty theme hook, `proj()`, claude account routing, `_auto_venv_check`, `_settings_sync_check`, `tzupdate`, `fastfetch`.

### On the Pi (end-to-end test)

```
ssh raspi
sudo apt install -y git zsh
git clone https://github.com/matteoneri/system_settings.git ~/system_settings
cd ~/system_settings
./restore.sh --configs --components shell,vim,git
exec zsh
```

Success criteria: zsh loads, prompt renders (starship if install succeeded, default otherwise), no error lines, `vim` and `git` available, `ls`/`cat` don't error (fall back to system ones when `eza`/`bat` absent).

## Non-goals

- Rewriting `restore.sh` for full cross-platform support (only `shell` and `vim` components are cross-platform).
- Unifying desktop and portable zshrc into one file.
- Adding a `.vimrc` to the repo.
- Any package-management beyond what components need for themselves.
