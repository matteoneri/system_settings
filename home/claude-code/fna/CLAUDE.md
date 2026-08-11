# Global Development Standards

Global instructions for all projects. Project-specific CLAUDE.md files override these defaults.

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

Two workflow plugins are installed. **Compound Engineering is the default for
brainstorming, planning, and doing the work.** Superpowers supplies discipline
*inside* that flow — it is not a competing pipeline.

This overrides the Superpowers `using-superpowers` skill, which otherwise routes
creative work to `superpowers:brainstorming`. Its own instruction-priority rules
say these instructions win, so follow this section instead.

### Default pipeline (Compound Engineering)

Names changed in compound-engineering 3.x: the `/ce:*` colon form is gone, and so is
`/slfg` — its swarm behaviour was folded into `/lfg`.

Phase-ordered routing table for the dev loop. Each skill carries its own
instructions, so this says *when to reach for what*, not how to run it.

- **Frame** — `/ce-ideate` generate and score options · `/ce-brainstorm` refine *your* idea into requirements · `/ce-pov` decisive second opinion on an approach, doc, or adopt/don't call
- **Plan** — `/ce-plan` structured plan (or deepen an existing one) · `/ce-doc-review` stress-test a plan/spec through role lenses
- **Isolate** — `/ce-worktree` before touching code
- **Build** — `/ce-work` execute a plan or clear build request end-to-end
- **Diagnose** — `/ce-debug` errors, stack traces, regressions, stuck investigations
- **Tighten** — `/ce-simplify-code` after implementation, before review · `/ce-optimize` metric-driven loops: retrieval relevance, clustering quality, prompt quality, build perf
- **Verify** — `/ce-code-review` bugs, regressions, tests, standards · `/ce-test-browser` pages touched by the branch · `/ce-dogfood` autonomous browser QA of the diff · `/ce-polish` dev server + browser iteration
- **Ship** — `/ce-commit` then push and raise the PR by hand (see Bitbucket note below)
- **Learn** — `/ce-compound` capture a solved problem · `/ce-compound-refresh` audit stale or superseded learnings
- **Continuity** — `/ce-handoff` hand off or resume across sessions · `/ce-explain` durable teaching artifact for a concept or diff
- **Meta** — `/ce-setup` CE health + repo-local config
- **Full auto** — `/lfg` plan → implement → review → commit → push → PR → watch CI, no check-ins

Browser skills need the `agent-browser` CLI (`npm i -g agent-browser && agent-browser install`).

**FNA repos are on Bitbucket** (`bitbucket.org:fnard/…`), and every CE PR skill drives
`gh`, which only speaks to GitHub. So **pushing and raising PRs here is manual.** Do not
attempt `/ce-commit-push-pr`, `/ce-babysit-pr`, or `/ce-resolve-pr-feedback` on FNA work —
they will fail against Bitbucket. `/ce-commit` is plain git and works fine. `/ce-code-review`
also works, since it can review a local diff without a PR. If a PR description would help,
ask for the body as text and paste it into Bitbucket by hand.

Out of scope here: `/ce-test-xcode` (no Apple toolchain on this machine),
`/ce-riffrec-feedback-analysis` (Riffrec captures), `/ce-retune` (skill-corpus
benchmarking). Product-side rather than dev loop, use deliberately: `/ce-strategy`,
`/ce-ideate` upstream framing, `/ce-product-pulse`, `/ce-promote`, `/ce-proof`, `/ce-sweep`.

Do **not** reach for the Superpowers equivalents of these phases:
`superpowers:brainstorming`, `superpowers:writing-plans`,
`superpowers:executing-plans`, `superpowers:subagent-driven-development`.

### Discipline inside the work (Superpowers)

Use these *within* `/ce-work`, not instead of it:

- **TDD**: `/superpowers:test-driven-development` — red-green-refactor, always.
- **Debugging**: `/superpowers:systematic-debugging` — 4-phase root cause analysis, not symptom treatment.
- **Verification**: `/superpowers:verification-before-completion` — evidence before assertions.
- **Parallel independent tasks**: `/superpowers:dispatching-parallel-agents`.

### Git Workflow

- **Always use git worktrees** for feature work. Never develop directly on `main`/`master`,
  and **never switch the shared checkout's branch** — several sessions may be live in the
  same repo at once, so `git checkout -b` there hijacks their working tree. Add a worktree
  instead; check `git worktree list` first to see who else is active.
- Use `/ce-worktree` to create them — for a fresh branch, or to attach a worktree to an existing branch/PR/commit.
- Each feature branch gets its own worktree — work in isolation.
- **Merging to `main`/`master`**: only when explicitly instructed; otherwise ask first when the work is ready to integrate.

### When to use which

| Task | Use |
|------|-----|
| Starting a feature | `/ce-worktree` → `/ce-brainstorm` → `/ce-plan` |
| Executing a plan | `/ce-work` — with TDD applied inside it |
| Quick bug fix | `/superpowers:systematic-debugging` (or `/ce-debug`) |
| Before review | `/ce-simplify-code` |
| Pre-merge review | `/ce-code-review` |
| Committing | `/ce-commit` — push + PR by hand (Bitbucket) |
| Tuning a measurable outcome | `/ce-optimize` (retrieval, prompts, perf) |
| Running out of context | `/ce-handoff` before the session ends |
| Claiming work is done | `/superpowers:verification-before-completion` |
| Capturing learnings | `/ce-compound` |
| Parallel independent tasks | `/superpowers:dispatching-parallel-agents` |

Do not duplicate these workflows in project CLAUDE.md files. Project files should only add project-specific conventions.

## FNA session bus (this machine only)

The FNA sessions (`fna_payments`, `fna_models`, `paynet_aws_containers`) exchange ephemeral
signals via `~/Documents/Projects/ActiveProjects/FNA/.session-bus/` — protocol in its README.
Send with `send.sh <your-identity> "msg"` (single-writer, append-only); sibling messages
arrive automatically at the next prompt (UserPromptSubmit hook). For live delivery during
active co-work, arm a persistent Monitor (`tail -n 0 -F`) on the sibling mailboxes.
**Bus = transport, never record**: anything durable or Federico-facing still goes to the
coordination board/inboxes in `paynet_aws_containers`.

## Commits

- Imperative mood, ≤72 char subject line, one logical change per commit.
- Never commit secrets, API keys, or credentials.
- Never commit or push to main/master without explicit permission. Use feature branches.
