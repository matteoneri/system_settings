# Shared codex memory

Read by **both** codex homes (`~/.codex-own` and `~/.codex-fna`). One fact per bullet,
durable and verified. Append when you learn something that outlives the session; delete
what turns out to be wrong. Do not put session narrative or project status here — those
belong in the repo (`ce-compound`, `ce-handoff`), not in a machine-level memory.

## How this machine is set up

- **Two codex homes.** `~/.codex-own` (personal ChatGPT account) and `~/.codex-fna` (FNA
  work account). The `codex()` wrapper in `~/.zshrc` picks one by working directory
  (`Projects/ActiveProjects/{OWN,FNA}`), by `--own` / `--fna`, or by prompting. `~/.codex`
  is a symlink to `~/.codex-own`, so codex started outside the wrapper lands there.
- **Both homes reach both project trees.** The `all-worktrees` permission profile is the
  default in each; an FNA session may read an OWN worktree and vice versa.
- **Claude Code has the same split** — `~/.claude-own` / `~/.claude-fna`, same directory
  rules. Its own memory store is `~/.claude-fna/projects/-home-matteo/memory/`; it holds
  machine-level gotchas (suspend/hibernate, NVIDIA, pCloud FUSE, audio) worth reading
  before debugging anything hardware-shaped.
- **`system_settings` is the source of truth for config.** After changing any system
  config (zshrc, i3, kitty, starship, …), run
  `~/Documents/Projects/system_settings/sync.sh`, commit on a feature branch, and update
  `.last_sync`. That repo follows the normal worktree rule: no direct work on `main`.

## Standing rules

- **Never `git push`.** It needs authentication no session has. Ask the user to push.
- **Never merge to `main`/`master`** without being told to. Ask when work is ready.
- **Always work in a git worktree**, never in the shared checkout, and never switch the
  shared checkout's branch — other sessions are often live in the same repo.
