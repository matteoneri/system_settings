# Projects root

Every project path in this repo comes from one per-machine variable,
`PROJECTS_ROOT`: the folder that holds `ActiveProjects/` and `system_settings/`.
The same repo then restores and syncs correctly on machines that keep their
projects in different places.

Plan: `docs/plans/2026-09-25-001-feat-projects-root-variable-plan.md` (plan key
`projects-root-variable`).

## Declaring it on a machine

Each machine declares its root once, in
`~/.config/environment.d/50-projects-root.conf`. The file is machine-local and
never synced.

| Machine | Line in the declaration file |
|---|---|
| Dell (EndeavourOS) | `PROJECTS_ROOT=${HOME}/Documents/Projects` |
| StarFighter (CachyOS) | `PROJECTS_ROOT=${HOME}/Projects` |

Use `${HOME}`, not `~`: the systemd user session reads this file and expands
`${HOME}` but not `~`. Open a new shell after creating it. A graphical session
started by systemd (niri on the laptop) picks it up at the next login.

An exported `PROJECTS_ROOT` takes precedence over the file.

## Who reads it

| Reader | How |
|---|---|
| systemd user session and what it launches | reads the file natively |
| zsh | `_projects_root_load` at the top of `home/.zshrc` |
| fish | `home/.config/fish/conf.d/projects-root.fish` |
| `sync.sh`, `restore.sh` | `projects_root_resolve` in `lib/projects-root.sh` |
| `project-launch` (i3) | resolves it itself, then passes it to the Claude session it starts |

Every reader follows the same rules: surrounding whitespace and one pair of
quotes are stripped, a leading `~`, `$HOME` or `${HOME}` expands, the path is
normalised, and a relative path, `/` or a missing directory is refused. The
shells and `project-launch` cannot source the repo library, because the repo's
own path comes from the root, so they carry a copy of these rules. Keep them in
step with `lib/projects-root.sh`: `tests/projects-root.sh` checks that the zsh
loader and `project-launch` agree with it, and `tests/fish-projects-root.sh`
covers the fish loader.

## When it is missing

A missing root is an error, never a guess.

- `sync.sh` and `restore.sh` stop before changing anything, naming
  `PROJECTS_ROOT` and the declaration file. They also stop unless the repo is
  `<root>/system_settings` (or a git worktree inside it) and the root is not
  `$HOME` itself, comparing real paths (`projects_root_check_repo`). Any other
  folder above the repo would make the swap turn every path under it into
  `@PROJECTS_ROOT@`, and with the root at `$HOME` the leak scan cannot tell it
  from ordinary home paths.
- An interactive zsh or fish prints one warning line and skips the steps that
  need the root (the weekly sync check and terminal titles in zsh). Nothing
  prints in non-interactive shells, which Claude Code creates for its tools.
- `project-launch` reports through `notify-send`.

## Files that cannot read variables

JSON, TOML and Markdown cannot expand `$PROJECTS_ROOT`, so the repo stores them
with the literal token `@PROJECTS_ROOT@` in place of the root:

- `home/claude-code/{own,fna}/settings.json` and `CLAUDE.md`
- `home/codex/{own,fna}/config.toml` and `AGENTS.md`
- `home/codex/shared/MEMORY.md`

`restore.sh` fills the token in with the machine's absolute root when it
installs them. `sync.sh` swaps the root back to the token before writing them
into the repo, recognising the absolute, `~/` and symlink-resolved spellings on
path boundaries only.

`sync.sh` stages everything it would write, then scans every staged file for
the machine's root in any spelling, including `$HOME/...` and `${HOME}/...`. A
hit stops the sync, names the file, and leaves the repo untouched. It also
refuses a live templated file that still holds `@PROJECTS_ROOT@`, because that
means `restore.sh` never filled it in on this machine.

Examples in synced files and messages use `${HOME}/path/to/projects`. Either
machine's real value in a synced file would trip that machine's leak scan.

## Adding a templated file

1. Add a copy step for it in `sync.sh` using `stage_templated`, and a fill step
   in the matching `restore.sh` component using `_fill`.
2. Replace the root in the repo copy with `@PROJECTS_ROOT@`, for example with
   `projects_root_swap` from `lib/projects-root.sh`.
3. Add it to the `TEMPLATED` list in `tests/projects-root.sh`, so the
   placeholder and parse checks cover it.
