#!/bin/sh
# UserPromptSubmit hook: set the kitty window title to the latest prompt.
#
# Claude Code continuously rewrites the terminal title (spinner prefix + auto-
# generated topic), so a raw OSC 2 escape gets overwritten within a frame.
# Solution: use kitty's remote-control `set-window-title`, which locks the
# title against further OSC writes from the app.

TITLE=$(jq -r '.prompt // empty' | tr '\n\t' '  ' | cut -c1-60)
[ -z "$TITLE" ] && exit 0

# Claude is PPID; the kitty window's shell (zsh) is PPID of claude.
SHELL_PID=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')

if [ -n "$KITTY_PID" ] && [ -n "$SHELL_PID" ]; then
    kitty @ --to "unix:@kitty-$KITTY_PID" set-window-title \
        --match "pid:$SHELL_PID" "$TITLE" 2>/dev/null
    exit 0
fi

# Fallback for non-kitty terminals: raw OSC 2 to the ancestor pts.
TT=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
if [ -n "$TT" ] && [ "$TT" != "?" ]; then
    printf '\033]2;%s\007' "$TITLE" > "/dev/$TT" 2>/dev/null
fi
exit 0
