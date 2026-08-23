# i3 session restore

Brings back the i3 session after a reboot or a crash: the workspace container
tree, each terminal's working directory, and the Claude Code or codex session
that was running inside it. Also shows a session's own name in its kitty title
once you have renamed it.

Two scripts, both autostarted from `home/.config/i3/config` on a plain `exec`
line so neither re-runs on an i3 reload or a restart-in-place:

- `home/.config/i3/scripts/session-snapshot` — the watcher. Records state every
  30 seconds, so an unclean shutdown loses at most half a minute of layout
  change. Also applies the title override.
- `home/.config/i3/scripts/session-restore` — rebuilds the recorded session once
  per fresh i3 start.

## State

Everything lives in `~/.config/i3-session/`, created mode 0700 on first run:

| Path | What it is |
|---|---|
| `snapshot.json` | The current snapshot, replaced atomically. Mode 0600. |
| `snapshot.pid` | The watcher's pid, so a second one exits instead of stacking. |
| `restore.lock` | Held while a restore runs; the watcher skips ticks rather than overwriting the snapshot it is restoring. |
| `skip` | Present means the next restore does nothing. See below. |
| `layouts/` | Generated i3 layout files, one per restored workspace. |

None of this is synced into the repo. It holds absolute worktree paths and agent
session ids, and `sync.sh` copies `~/.config/i3/scripts/*` wholesale — which is
why the state directory sits outside that tree.

## Skipping one boot

To come up with an empty desktop without losing the snapshot:

```bash
touch ~/.config/i3-session/skip
```

The restore consumes the marker and exits, leaving the snapshot alone, so the
next boot restores normally. There is no keybinding for this yet.

## Session titles

A Claude Code session you have renamed with `/rename` shows that name as its
kitty window title, and keeps it for the life of the session. A session the CLI
named itself keeps its generated title.

This needs both halves to work: the watcher applies the name and locks the
title, and `title-hook.sh` in each account exits early once the watcher has
stamped the window, so it stops generating a competing title. The session record
is what distinguishes a chosen name from a generated one — it carries a
name-source field only when the name was generated.

A rename shows up within a few seconds. The watcher polls the session records
for a changed name on a short cycle and only then talks to kitty, so it reacts
to a rename without waiting for the next snapshot, and without doing kitty work
every few seconds for nothing. A title lost to some other writer is re-applied
on the slower snapshot cycle instead.

## Checking it by hand

```bash
# Take one snapshot now and print nothing else. Safe alongside the watcher.
~/.config/i3/scripts/session-snapshot --once

# Show the layout and terminal manifest a snapshot would produce for a workspace,
# without touching the desktop.
~/.config/i3/scripts/session-restore --plan ~/.config/i3-session/snapshot.json 2

# Run a real restore from a different snapshot file. This is NOT a dry run: it
# switches workspaces, spawns real kitty windows, resumes real agent sessions,
# and uses the live lock, marker and layout directory. Only the input file is
# substituted. Use --plan above if you want to look without touching anything.
I3_SESSION_SNAPSHOT=/path/to/other.json ~/.config/i3/scripts/session-restore

# Layout synthesis test, against hand-authored fixtures.
bash tests/session-layout-roundtrip.sh
```

## Permission posture of resumed sessions

The restore launches the agent binary directly with an explicit account, never
through the zsh `claude` wrapper — the wrapper adds `--dangerously-skip-permissions`
on every branch and would also stall on its interactive account prompt. So nothing
here adds a permission bypass.

What is *not* established: a session transcript records `permission-mode` events,
so a session that was running with permissions bypassed may come back that way on
`--resume` regardless of how it is launched. That was not verified, and it is the
CLI's behavior rather than something these scripts control. Since restored sessions
come up unattended at login, treat a session you deliberately put in a bypassed
mode as still bypassed after a restore until proven otherwise.

## What it does not do

Browsers, chat and music apps keep their existing declarative placement in the
i3 config and are not restored by these scripts; a slot held by one of them is
dropped and its siblings keep their proportions. A terminal that was running
something other than an agent comes back as a shell in the right directory, not
mid-command. Floating geometry, kitty's own tabs and splits, per-account kitty
themes, and multi-monitor arrangements are all out of scope.
