#!/usr/bin/env bash
# sync.sh - Pull latest config files from system into this repo
#
# Every output first lands in a staging mirror of the repo. The transforms run
# there, the projects root is swapped back to @PROJECTS_ROOT@ in the templated
# files, and every staged file is scanned for the root. The mirror is copied
# into the repo only when every check passes, so a stop at any check leaves the
# repo as it was. That final copy is the one write into the repo: if it fails
# partway (disk full, permission denied), the repo may hold a mix of old and
# new files, and sync says so and how to recover. A live source this machine
# lacks is skipped, and its repo copy kept.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/projects-root.sh
source "$REPO_DIR/lib/projects-root.sh"

STAGE=""
TEMPLATED=()           # staged paths the repo stores with the placeholder
UNFILLED=()            # live templated files restore never filled in
LEAKS=""               # report of staged files still holding the root
declare -A SOURCE_OF=()  # staged path -> the live source it came from

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Print a path under $HOME in its ~/ form, for messages.
tildify() {
    if [[ "$1" == "$HOME"/* ]]; then
        printf '~/%s' "${1#"$HOME"/}"
    else
        printf '%s' "$1"
    fi
}

# present SRC: succeed when the live source exists; else report the skip, and
# its repo copy stays as it is.
present() {
    [[ -e "$1" ]] && return 0
    echo "  skip (absent): $(tildify "$1")"
    return 1
}

# stage_file SRC REL: copy the live file SRC to REL in the staging mirror.
stage_file() {
    present "$1" || return 0
    mkdir -p "$STAGE/$(dirname "$2")"
    cp "$1" "$STAGE/$2"
    SOURCE_OF["$2"]="$1"
}

# stage_glob DIR PATTERN RELDIR: stage each file in DIR matching PATTERN.
stage_glob() {
    local dir="$1" pattern="$2" reldir="$3" f matches
    shopt -s nullglob
    # shellcheck disable=SC2206  # PATTERN is meant to glob
    matches=("$dir"/$pattern)
    shopt -u nullglob
    if (( ${#matches[@]} == 0 )); then
        echo "  skip (absent): $(tildify "$dir")/$pattern"
        return 0
    fi
    for f in "${matches[@]}"; do
        stage_file "$f" "$reldir/${f##*/}"
    done
}

# stage_templated SRC REL: stage a file the repo stores with the placeholder.
# A live copy still holding the placeholder was never filled in by restore, and
# syncing it back would hide that, so it is refused instead.
stage_templated() {
    local rc=0
    stage_file "$1" "$2"
    [[ -f "$STAGE/$2" ]] || return 0
    projects_root_scan_placeholder "$STAGE/$2" >/dev/null || rc=$?
    case "$rc" in
        0) TEMPLATED+=("$2") ;;
        1) UNFILLED+=("$1") ;;
        *) exit 1 ;;  # unreadable; the library named the file
    esac
}

# filter_settings REL: drop the Read(~/...) deny rules from a staged Claude
# settings.json. A jq failure stops the sync rather than stage a broken file.
filter_settings() {
    local file="$STAGE/$1"
    [[ -f "$file" ]] || return 0
    jq 'del(.permissions.deny[]? | select(startswith("Read(~/")))' "$file" > "$file.filtered" \
        || die "jq could not filter $(tildify "${SOURCE_OF[$1]}"); fix its JSON and run sync.sh again. The repo is unchanged."
    mv -- "$file.filtered" "$file"
}

# Stop when a live templated file was never filled in.
refuse_unfilled() {
    local f
    (( ${#UNFILLED[@]} == 0 )) && return 0
    {
        echo "ERROR: these live files still hold $PROJECTS_ROOT_PLACEHOLDER, so restore.sh never filled them in on this machine:"
        for f in "${UNFILLED[@]}"; do echo "  $(tildify "$f")"; done
        echo "Run restore.sh to fill them in, then run sync.sh again. The repo is unchanged."
    } >&2
    exit 1
}

# Collect in LEAKS every staged file that holds the root in any spelling.
scan_staged() {
    local file rel hits rc
    while IFS= read -r -d '' file; do
        rel="${file#"$STAGE"/}"
        rc=0
        hits="$(projects_root_scan "$ROOT" "$file")" || rc=$?
        (( rc < 2 )) || die "could not scan $rel for the projects root. The repo is unchanged."
        (( rc == 0 )) && continue
        LEAKS+="  $(tildify "${SOURCE_OF[$rel]:-$rel}") (repo: $rel)"$'\n'
        LEAKS+="$(sed 's/^/      line /' <<<"$hits")"$'\n'
    done < <(find "$STAGE" -type f -print0 | sort -z)
}

# Copy the checked mirror into the repo: the one write sync makes there. A
# failure partway has replaced some files and not others, so say that and how
# to recover instead of stopping on cp's error alone.
copy_stage_into_repo() {
    local repo_q
    cp -R "$STAGE/." "$REPO_DIR/" && return 0
    repo_q="$(printf '%q' "$REPO_DIR")"
    {
        echo "ERROR: copying the staged files into the repo ($REPO_DIR) failed partway, so the repo may now hold a mix of old and new files."
        echo "See what changed with: git -C $repo_q status; git -C $repo_q diff"
        echo "Discard the partial copy with: git -C $repo_q checkout -- .   (this also drops any uncommitted edits you had in the repo)"
        echo "Then fix the cause cp reported above and run sync.sh again."
    } >&2
    exit 1
}

ROOT="$(projects_root_resolve)" || exit 1
if ! projects_root_check_repo "$ROOT" "$REPO_DIR"; then
    echo "Nothing was synced." >&2
    exit 1
fi

echo "Syncing system configs to $REPO_DIR ..."

STAGE="$(mktemp -d --tmpdir sync-stage.XXXXXX)"
trap 'rm -rf -- "$STAGE"' EXIT

# Shell
stage_file "$HOME/.zshrc" home/.zshrc
stage_file "$HOME/.zsh/completion/_zkstack.zsh" home/.zsh/completion/_zkstack.zsh

# Fish: only the tracked files, never the whole functions directory, so
# functions local to one machine stay out of the repo.
for rel in .config/fish/functions/claude.fish \
           .config/fish/functions/codex.fish \
           .config/fish/conf.d/projects-root.fish; do
    stage_file "$HOME/$rel" "home/$rel"
done

# Cargo (sccache wrapper + cargo-nextest/hack/machete aliases)
stage_file "$HOME/.cargo/config.toml" home/.cargo/config.toml

# X11
stage_file "$HOME/.Xresources" home/.Xresources

# Git (strip personal identity)
stage_file "$HOME/.gitconfig" home/.gitconfig
if [[ -f "$STAGE/home/.gitconfig" ]]; then
    sed -i 's/^\(\s*email\s*=\s*\).*/\1YOUR_EMAIL/' "$STAGE/home/.gitconfig"
    sed -i 's/^\(\s*name\s*=\s*\).*/\1YOUR_NAME/' "$STAGE/home/.gitconfig"
fi

# i3
stage_file "$HOME/.config/i3/config" home/.config/i3/config
stage_glob "$HOME/.config/i3/scripts" '*' home/.config/i3/scripts

# Polybar
stage_file "$HOME/.config/polybar/config.ini" home/.config/polybar/config.ini
stage_file "$HOME/.config/polybar/launch.sh" home/.config/polybar/launch.sh

# Rofi
stage_glob "$HOME/.config/rofi" '*.rasi' home/.config/rofi

# Picom
stage_file "$HOME/.config/picom/picom.conf" home/.config/picom/picom.conf

# Dunst
stage_file "$HOME/.config/dunst/dunstrc" home/.config/dunst/dunstrc

# Newsboat
stage_file "$HOME/.config/newsboat/config" home/.config/newsboat/config
stage_file "$HOME/.config/newsboat/urls" home/.config/newsboat/urls
stage_file "$HOME/.config/newsboat/config.datasave" home/.config/newsboat/config.datasave

# Pacman & Paru
stage_file "$HOME/.config/pacman/pacman.conf" home/.config/pacman/pacman.conf
stage_file "$HOME/.config/paru/paru.conf" home/.config/paru/paru.conf

# Autostart
stage_glob "$HOME/.config/autostart" '*.desktop' home/.config/autostart

# Claude Code preferences (extract safe keys only, no credentials). The live
# file holds credentials, so it is read in place and never staged.
for acct in own fna; do
    src="$HOME/.claude-${acct}/.claude.json"
    rel="home/claude-code/${acct}/preferences.json"
    present "$src" || continue
    mkdir -p "$STAGE/home/claude-code/${acct}"
    python3 - "$src" "$STAGE/$rel" <<'PY'
import json
import sys
src, dest = sys.argv[1:]
with open(src) as f:
    data = json.load(f)
safe_keys = ['theme', 'autoUpdates', 'installMethod', 'showSpinnerTree', 'effortCalloutDismissed']
safe = {k: data[k] for k in safe_keys if k in data}
with open(dest, 'w') as f:
    json.dump(safe, f, indent=2)
    f.write('\n')
PY
    SOURCE_OF["$rel"]="$src"
done

# Claude Code global instructions (CLAUDE.md), statusline, title-hook, settings
for acct in own fna; do
    stage_templated "$HOME/.claude-${acct}/CLAUDE.md" "home/claude-code/${acct}/CLAUDE.md"
    stage_file "$HOME/.claude-${acct}/statusline.sh" "home/claude-code/${acct}/statusline.sh"
    stage_file "$HOME/.claude-${acct}/title-hook.sh" "home/claude-code/${acct}/title-hook.sh"
    # settings.json (strip credentials/tokens, keep structure)
    stage_templated "$HOME/.claude-${acct}/settings.json" "home/claude-code/${acct}/settings.json"
    filter_settings "home/claude-code/${acct}/settings.json"
done

# Claude Code credential hooks: the FNA directory holds the files and the own/
# entries link to them, so only the FNA copies are staged.
stage_glob "$HOME/.claude-fna/hooks" '*' home/claude-code/hooks

# Codex: per-account config and global instructions, plus the shared memory both
# homes read. Credentials live in auth.json and are never copied.
for acct in own fna; do
    stage_templated "$HOME/.codex-${acct}/config.toml" "home/codex/${acct}/config.toml"
    stage_templated "$HOME/.codex-${acct}/AGENTS.md" "home/codex/${acct}/AGENTS.md"
done
stage_templated "$HOME/.codex-shared/MEMORY.md" home/codex/shared/MEMORY.md

# Neovim
stage_file "$HOME/.config/nvim/init.lua" home/.config/nvim/init.lua
stage_glob "$HOME/.config/nvim/lua/plugins" '*.lua' home/.config/nvim/lua/plugins

# Kitty
stage_file "$HOME/.config/kitty/kitty.conf" home/.config/kitty/kitty.conf
stage_glob "$HOME/.config/kitty/themes" '*.conf' home/.config/kitty/themes

# Starship
stage_file "$HOME/.config/starship.toml" home/.config/starship.toml

# Screenlayout (optional)
stage_file "$HOME/.screenlayout/monitor.sh" home/.screenlayout/monitor.sh

# Power / sleep (pCloud FUSE teardown around suspend + lid behaviour)
# Backup only — restore.sh does not replay etc/, same as the pacman hook.
# 20-fix-freeze-sessions.conf is load-bearing and owned by no package: nvidia-utils
# ships a drop-in disabling the user.slice freeze, and that file reverses it. Without
# it a restored machine silently stops freezing user sessions on suspend.
for f in /etc/systemd/system/pcloud-suspend.service \
         /etc/systemd/system/pcloud-resume.service \
         /etc/systemd/system/pcloud-shutdown.service \
         /etc/systemd/system/pcloud-sleep-failed@.service \
         /etc/systemd/system/systemd-suspend.service.d/20-fix-freeze-sessions.conf \
         /etc/systemd/logind.conf.d/10-lid.conf \
         /etc/systemd/system/pcloud-datasave.service \
         /etc/polkit-1/rules.d/49-datasave-units.rules \
         /etc/NetworkManager/dispatcher.d/90-datasave-metered \
         /usr/local/bin/pcloud-teardown; do
    if [ -f "$f" ]; then
        stage_file "$f" "${f#/}"
    elif [ -d "$(dirname "$f")" ] && [ ! -r "$(dirname "$f")" ]; then
        # /etc/polkit-1/rules.d is drwxr-x--- root:polkitd, so `[ -f ]` is false
        # for a file that is installed and correct. Reporting that as "absent"
        # would claim the polkit rule is missing when it is not.
        echo "  skip (unreadable, needs root): $f"
    else
        echo "  skip (absent): $f"
    fi
done
stage_file "$HOME/.config/systemd/user/pcloud.service" home/.config/systemd/user/pcloud.service

# Package lists
pacman -Qe --quiet | sort > "$STAGE/packages-explicit.txt"
pacman -Qm --quiet | sort > "$STAGE/packages-aur.txt"
comm -23 "$STAGE/packages-explicit.txt" "$STAGE/packages-aur.txt" > "$STAGE/packages-official.txt"
SOURCE_OF[packages-explicit.txt]="pacman -Qe"
SOURCE_OF[packages-aur.txt]="pacman -Qm"
SOURCE_OF[packages-official.txt]="pacman -Qe minus pacman -Qm"

# Neutralise and check the staging mirror before anything reaches the repo.
refuse_unfilled
for rel in "${TEMPLATED[@]}"; do
    projects_root_swap "$ROOT" "$STAGE/$rel" "$STAGE/$rel" || exit 1
done
scan_staged
if [[ -n "$LEAKS" ]]; then
    {
        echo "ERROR: these files would write this machine's projects root ($ROOT) into the repo:"
        printf '%s' "$LEAKS"
        echo "Replace the literal path in those live files, then run sync.sh again: a shell file can read \$PROJECTS_ROOT,"
        echo "an example can say \${HOME}/path/to/projects, and the templated Claude and Codex files take the root as an"
        echo "absolute or ~/ path, which sync swaps back. The repo is unchanged."
    } >&2
    exit 1
fi

copy_stage_into_repo

echo "Done. Changes:"
cd "$REPO_DIR"
git diff --stat
git status --short
