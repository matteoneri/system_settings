# Global Development Standards — OWN account

This is the **OWN** codex home (`~/.codex-own`), selected by the `codex()` wrapper in
`~/.zshrc` when the working directory is under `Projects/ActiveProjects/OWN`, or by
`codex --own`. It is also what a bare `codex` outside the wrapper gets, since `~/.codex`
symlinks here. The sibling home is `~/.codex-fna` (work account). Both homes can read and
write both project trees; only the account, history and sessions differ.

Project-specific `AGENTS.md` files override these defaults.

## Philosophy

- **Quality over speed** — always prefer the correct, production-grade solution over a quick fix. Understand the root cause before writing code. Use the recommended patterns for the framework version in use (e.g., SQLAlchemy 2.0 ORM bulk patterns, not legacy workarounds). If a fix feels hacky, it probably is — find the proper approach.
- **No speculative features** — don't add features, flags, or configuration unless actively needed.
- **No premature abstraction** — don't create utilities until you've written the same code three times.
- **Clarity over cleverness** — prefer explicit, readable code over dense one-liners.
- **Justify new dependencies** — each dependency is attack surface and maintenance burden.
- **Replace, don't deprecate** — when a new implementation replaces an old one, remove the old one entirely. No backward-compatible shims or dual config formats.
- **Finish the job** — handle edge cases you can see, clean up what you touched, flag broken things adjacent to your change. But don't invent new scope.
- **Bias toward action** — decide and move for anything easily reversed; state your assumption. Ask before committing to interfaces, data models, architecture, or destructive operations.

## Code Quality

### Hard limits

- ≤100 lines per function, cyclomatic complexity ≤8
- ≤5 positional parameters
- No commented-out code — delete it

### Zero warnings policy

Fix every warning from linters, type checkers, compilers, and tests. If a warning truly can't be fixed, add an inline ignore with a justification comment. Never leave warnings unaddressed.

### Error handling

- Fail fast with clear, actionable messages.
- Never swallow exceptions silently.
- Include context: what operation, what input, suggested fix.

## Testing

- **Test behavior, not implementation.** If a refactor breaks tests but not code, the tests were wrong.
- **Test edges and errors, not just the happy path.** Empty inputs, boundaries, malformed data, missing files — bugs live in edges.
- **Mock boundaries, not logic.** Only mock things that are slow, non-deterministic, or external services you don't control.
- **Verify tests catch failures.** Break the code, confirm the test fails, then fix.
- **TDD by default** — red, green, refactor. Write the failing test first.
- **Evidence before assertions** — never claim work is complete, fixed, or passing without running the verification command and reading its output.
- **Debug systematically** — find the root cause before proposing a fix; treat the symptom last, not first.

## CLI Tool Preferences

| tool | replaces | notes |
|------|----------|-------|
| `rg` (ripgrep) | grep | fast regex search |
| `fd` | find | fast file finder |
| `ast-grep` | — | AST-based code search, prefer over rg for structural queries |

### Rust projects

Toolchain is rustup-managed; these four live in `~/.cargo/bin`, with aliases in `~/.cargo/config.toml`:

| tool | use | alias |
|------|-----|-------|
| `cargo-nextest` | test runner: per-test isolation, retries, profiles | `cargo nt` / `cargo ntf` |
| `cargo-hack` | feature-combination checks — catches broken feature gates | `cargo hack-powerset` / `cargo hack-each` |
| `cargo-deny` | licences, security advisories, banned/duplicate deps, source allow-list | — |
| `cargo-machete` | unused-dependency scan | `cargo unused` |

Use all four where they improve the flow. Two need per-project config — copy the canonical
versions from `~/Documents/Projects/system_settings/templates/rust/`:

- **`.config/nextest.toml`** at the workspace root. Nextest has **no** user-level config, so
  every workspace needs its own. Ships a `default` profile for local runs and a `ci` profile
  with retries, no fail-fast, and JUnit output.
- **`deny.toml`** at the workspace root. Lean and enforcing: widen a rule by adding to
  `allow` / `exceptions` / `skip` **with a reason**, never by downgrading a severity.

`cargo hack` and `cargo machete` need no config. Expect the first `cargo deny check` in a new
project to fail on real findings (unlisted permissive licences, live security advisories) —
triage them rather than loosening the policy. An unpublished workspace crate reports as
"unlicensed" until it declares `publish = false` or a `license` field.

## Workflow

The **compound-engineering** plugin is installed in both codex homes. It is the default
for brainstorming, planning, and doing the work. Phase-ordered routing — each skill
carries its own instructions, so this says *when to reach for what*, not how to run it.

- **Frame** — `ce-ideate` generate and score options · `ce-brainstorm` refine *your* idea into requirements · `ce-pov` decisive second opinion on an approach, doc, or adopt/don't call
- **Plan** — `ce-plan` structured plan (or deepen an existing one) · `ce-doc-review` stress-test a plan/spec through role lenses
- **Isolate** — `ce-worktree` before touching code
- **Build** — `ce-work` execute a plan or clear build request end-to-end
- **Diagnose** — `ce-debug` errors, stack traces, regressions, stuck investigations
- **Tighten** — `ce-simplify-code` after implementation, before review · `ce-optimize` metric-driven loops
- **Verify** — `ce-code-review` bugs, regressions, tests, standards · `ce-test-browser` pages touched by the branch · `ce-dogfood` autonomous browser QA of the diff
- **Learn** — `ce-compound` capture a solved problem · `ce-compound-refresh` audit stale learnings
- **Continuity** — `ce-handoff` hand off or resume across sessions · `ce-explain` durable teaching artifact

Browser skills need the `agent-browser` CLI (`npm i -g agent-browser && agent-browser install`).

Out of scope here: `ce-test-xcode` (no Apple toolchain on this machine),
`ce-riffrec-feedback-analysis` (Riffrec captures), `ce-retune` (skill-corpus benchmarking).

The Superpowers plugin is **not** installed in codex — it is Claude Code only. Its
disciplines still apply and are folded into the Testing section above; do not look for
`superpowers:*` skills here.

### Remotes and PRs

Repos under this account are on **GitHub**, so the CE PR skills (`ce-commit-push-pr`,
`ce-babysit-pr`, `ce-resolve-pr-feedback`) work — they drive `gh`. On a Bitbucket remote
they fail; commit with `ce-commit` and raise the PR by hand there.

### Git Workflow

- **Always use git worktrees** for feature work. Never develop directly on `main`/`master`,
  and **never switch the shared checkout's branch** — several sessions may be live in the
  same repo at once, so `git checkout -b` there hijacks their working tree. Add a worktree
  instead; check `git worktree list` first to see who else is active.
- Use `ce-worktree` to create them — for a fresh branch, or to attach a worktree to an
  existing branch/PR/commit.
- Each feature branch gets its own worktree — work in isolation.
- **Never `git push`** — it needs authentication this session does not have. Ask the user to push.
- **Merging to `main`/`master`**: only when explicitly instructed; otherwise ask first when
  the work is ready to integrate.

## Commits

- Imperative mood, ≤72 char subject line, one logical change per commit.
- Never commit secrets, API keys, or credentials.
- Never commit or push to main/master without explicit permission. Use feature branches.
- **Never cite a work-unit id alone — prefix it with its plan's key.** A bare `U3` (or "step 4",
  "task 2") names nothing once a second plan is live, and a reader grepping the history cannot tell
  which document it meant. Use whatever identifies the plan uniquely in that repo — its filename
  key, a short code, an issue number — spell it identically in the plan and in the commit, and
  settle it before the first commit cites it: renumbering afterwards silently repoints every
  subject already written.

## Shared memory

`~/.codex-shared/MEMORY.md` is read by **both** codex homes. Durable, cross-account facts
about this machine and how to work on it go there — not in this file, and not in a
session transcript that the other account will never see. Read it when you need prior
context; append to it when you learn something durable and verified. Keep it to facts
that outlive a session: machine quirks, hard-won gotchas, standing decisions.

Codex's built-in memory database (`$CODEX_HOME/memories_1.sqlite`) is **not** shared: it is
a per-home index derived from that home's own threads, so it cannot span accounts.
`~/.codex-shared/MEMORY.md` is the thing that does.

To share a skill between the two homes, keep it in `~/.codex-shared/skills/<name>/` and
symlink it into each home as `$CODEX_HOME/skills/<name>` — codex discovers skills as a
flat `skills/<name>/SKILL.md`, so a nested shared directory is not picked up.
