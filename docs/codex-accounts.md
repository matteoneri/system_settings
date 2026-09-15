# Codex: two accounts on one machine

Codex keeps credentials, config, history, sessions and skills in a single directory,
`$CODEX_HOME` (default `~/.codex`). Two accounts therefore means two homes, the same
way Claude Code uses `~/.claude-own` and `~/.claude-fna`.

| | OWN | FNA |
|---|---|---|
| home | `~/.codex-own` | `~/.codex-fna` |
| account | personal ChatGPT login | FNA work login |
| remotes | GitHub — CE PR skills work | Bitbucket — push and PR by hand |
| global instructions | `~/.codex-own/AGENTS.md` | `~/.codex-fna/AGENTS.md` |

`~/.codex` is a **symlink to `~/.codex-own`**. The shell wrapper always sets
`CODEX_HOME` explicitly, so the symlink only catches a codex started some other way —
a script, an i3 restore from an old snapshot, a tool that execs the binary directly.
Without it those would silently create an empty home and ask to log in.

## Choosing an account

`codex()` in `~/.zshrc`, mirroring `claude()`:

1. `--own` / `--fna` if given (the flag is stripped before codex sees the arguments)
2. otherwise the working directory: under `Projects/ActiveProjects/OWN` or `.../FNA`
3. otherwise an interactive prompt, defaulting to FNA

## What each home holds

Both homes carry the same `all-worktrees` permission profile and the same project
trust entries **on purpose**: an FNA session may need to read an OWN worktree and
vice versa. Only the account, history and sessions are account-specific.

`~/.codex-shared/MEMORY.md` is read by both homes — durable, cross-account facts
about this machine. Codex's own `memories_*.sqlite` cannot fill this role: it is a
per-home index derived from that home's threads, keyed by thread id, so it does not
span accounts. To share a skill, keep it in `~/.codex-shared/skills/<name>/` and
symlink it into each home as `$CODEX_HOME/skills/<name>` — codex discovers skills as
a flat `skills/<name>/SKILL.md`, so a nested shared directory is not picked up.

## Tracked in this repo

`sync.sh` copies `config.toml` and `AGENTS.md` from each home into
`home/codex/{own,fna}/`, and the shared memory into `home/codex/shared/`. Credentials
live in `auth.json`, which is never copied. `restore.sh codex` puts them back, creates
the `~/.codex` symlink, and tells you to authenticate each account.

## Setting up a second account from scratch

```bash
mkdir -p ~/.codex-fna              # config.toml + AGENTS.md via restore.sh codex
codex --fna                        # then /login inside the TUI
```

## Rolling back to a single home

```bash
rm ~/.codex && mv ~/.codex-own ~/.codex    # then drop codex() from ~/.zshrc
```
