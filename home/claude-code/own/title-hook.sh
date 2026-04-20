#!/bin/sh
# UserPromptSubmit hook: Haiku summarizes the current topic into a kitty
# window title and only updates the title when the topic actually shifts.
#
# Runs async (see settings.json) so the ~1s API call doesn't delay Claude's
# reply. Uses the Claude Code OAuth token already on disk — no separate key.
#
# Claude Code continuously rewrites the OSC title (spinner prefix + its own
# auto-topic), so a raw OSC escape gets overwritten within a frame. We use
# kitty's remote-control `set-window-title` instead, which locks the title
# against further app writes.

# Recursion guard (in case we ever invoke `claude` itself from here)
[ -n "$CLAUDE_TITLE_HOOK_ACTIVE" ] && exit 0

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -z "$PROMPT" ] && exit 0
[ -z "$SESSION" ] && exit 0

STATE="/tmp/claude-title-$SESSION"
PREV=""
[ -f "$STATE" ] && PREV=$(cat "$STATE")

TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" 2>/dev/null)
[ -z "$TOKEN" ] && exit 0

REQUEST=$(jq -n --arg prev "$PREV" --arg prompt "$PROMPT" '{
    model: "claude-haiku-4-5-20251001",
    max_tokens: 15,
    system: "You output terminal window titles. Rules:\n- Reply with ONLY 3-6 words, no quotes, no punctuation, no sentences, no explanation.\n- The title must describe the topic the user is working on.\n- If the existing title still fits, repeat it verbatim.\n- Never answer the user''s question. Just label it.",
    messages: [{
        role: "user",
        content: "Current title: \($prev | if . == "" then "(none — pick one)" else . end)\n\nUser message:\n\($prompt)"
    }]
}')

RESPONSE=$(curl -sf --max-time 5 https://api.anthropic.com/v1/messages \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    -d "$REQUEST" 2>/dev/null)

TITLE=$(printf '%s' "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null \
    | head -1 \
    | sed -E 's/^["'\'' ]+//; s/["'\'' .]+$//' \
    | cut -c1-60)

[ -z "$TITLE" ] && exit 0
[ "$TITLE" = "$PREV" ] && exit 0

printf '%s' "$TITLE" > "$STATE"

SHELL_PID=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')
if [ -n "$KITTY_PID" ] && [ -n "$SHELL_PID" ]; then
    kitty @ --to "unix:@kitty-$KITTY_PID" set-window-title \
        --match "pid:$SHELL_PID" "$TITLE" 2>/dev/null
else
    TT=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
    [ -n "$TT" ] && [ "$TT" != "?" ] && \
        printf '\033]2;%s\007' "$TITLE" > "/dev/$TT" 2>/dev/null
fi
exit 0
