---
title: "kitty --config replaces kitty.conf instead of adding to it, silently disabling remote control"
date: 2026-08-23
category: integration-issues
module: i3-scripts
problem_type: integration_issue
component: tooling
symptoms:
  - "kitty @ --to unix:@kitty-<pid> ls exits non-zero with no output for some terminals but works for others"
  - "Terminals launched by project-launch are invisible to any tooling that enumerates kitty windows"
  - "A per-window feature works on hand-opened terminals and silently does nothing on scripted ones"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [kitty, remote-control, i3, dotfiles, config-resolution, silent-failure]
---

# kitty --config replaces kitty.conf instead of adding to it, silently disabling remote control

## Problem

Passing `--config <file>` to kitty makes it skip `~/.config/kitty/kitty.conf`
entirely rather than layering the named file on top of it. Any setting that
lives only in the main config — here `allow_remote_control` and `listen_on` —
reverts to its built-in default. Those terminals then have no control socket,
so every tool that talks to kitty over remote control silently cannot see them.

The i3 session-restore feature hit this: `project-launch` opens each terminal
with `kitty --config "$kitty_theme"` to apply a per-account colour theme, and
those are exactly the multi-pane project windows with an agent running inside
that the feature exists to capture. They were invisible, and would have been
restored as bare shells with no working directory and no session.

## Symptoms

- `kitty @ --to "unix:@kitty-<pid>" ls` returns nothing and exits non-zero for
  scripted terminals, while hand-opened terminals on the same machine answer
  normally.
- A feature that enumerates kitty windows appears to work — it just quietly
  covers a subset, so the gap does not look like a failure.
- No error anywhere. The socket was never created, so there is nothing to log.

## What Didn't Work

- **Trusting a live enumeration as proof of coverage.** Enumerating kitty
  windows returned a plausible list, which read as full coverage. It was
  complete only because no `project-launch` terminal happened to be open at the
  time. An all-or-nothing guard ("no kitty answered — warn") never fires here,
  because the other terminals do answer.
- **Treating remote control as a stability assumption.** It was first written
  down as a dependency that might change in future, when it was already an
  active coverage gap.

## Solution

Pass the main config explicitly, before the override:

```bash
KITTY_CONF="$HOME/.config/kitty/kitty.conf"

# Before — theme applied, remote control silently lost:
kitty --config "$kitty_theme" --directory "$path" -e yazi &

# After — both files load, in order:
kitty --config "$KITTY_CONF" --config "$kitty_theme" --directory "$path" -e yazi &
```

`--config` accepts repetition and merges in order, so the theme still wins on
the keys it sets while everything else comes from the main config.

Verified on kitty 0.48.2: a terminal launched with only `--config <theme>` does
not answer on its socket; adding the main config first makes it answer while the
theme still applies.

## Why This Works

kitty's config resolution is replace-not-merge with respect to the user config.
From `/usr/lib/kitty/kitty/conf/utils.py:433`:

```python
def resolve_config(SYSTEM_CONF, defconf, config_files_on_cmd_line=()):
    if config_files_on_cmd_line:
        if 'NONE' not in config_files_on_cmd_line:
            yield SYSTEM_CONF
            yield from config_files_on_cmd_line
    else:
        yield SYSTEM_CONF
        yield defconf
```

`defconf` is `~/.config/kitty/kitty.conf`, and it is only reached in the `else`
branch. Any `--config` on the command line takes the first branch, so the user
config is never yielded. The only thing still loaded is `SYSTEM_CONF`
(`/etc/xdg/kitty/kitty.conf`), which does not exist on this machine — so the
effective config is the named file plus built-in defaults, and
`allow_remote_control` defaults to `no`.

This is why the failure is silent rather than loud: nothing is misconfigured,
a setting simply was never read.

## Prevention

- **Treat `--config` as "instead of", not "as well as".** Any script passing
  `--config` must also pass the main config first, or accept built-in defaults
  for everything the named file does not set.
- **`--class` and `--name` are safe.** They do not affect config resolution;
  only `--config` does. A restored terminal launched with `--name` keeps its
  control socket, which is what lets the next snapshot see it.
- **Test the capability on a window created the way the script creates it.** The
  check that matters is not "does remote control work here" but "does it work on
  a window launched by that script". A one-line probe is enough:

  ```bash
  kitty --config ~/.config/kitty/themes/Hachiko.conf --name probe -e sleep 5 &
  sleep 3; kitty @ --to "unix:@kitty-$(pgrep -nx kitty)" ls >/dev/null \
    && echo "socket answers" || echo "socket absent"
  ```

- **Prefer a per-item signal over an all-or-nothing guard** when coverage can be
  partial. A guard that only fires when *nothing* responds cannot detect a
  subset going missing; recording per-window whether the socket answered makes
  the gap visible.

## Related Issues

- `docs/plans/2026-08-23-001-feat-i3-session-restore-plan.md` — the feature this
  blocked; its Dependencies section now states the `--config` constraint rather
  than treating remote control as a stability assumption.
- `docs/i3-session-restore.md` — operator notes for the feature.
