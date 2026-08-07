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

- **Brainstorm**: `/ce-brainstorm` — turn a vague idea into right-sized requirements before planning.
- **Plan**: `/ce-plan` — structured plans for multi-step work.
- **Work**: `/ce-work` — execute a plan or concrete prompt end-to-end.
- **Review**: `/ce-code-review` — structured review for bugs, regressions, tests, standards.
- **Compound**: `/ce-compound` — document a solved problem as a durable repo learning.
- **Debug**: `/ce-debug` — diagnosis loop for errors, stack traces, regressions.
- **Simplify**: `/ce-simplify-code` — tighten settled code for clarity and reuse.
- **Full auto**: `/lfg` — the whole autonomous pipeline, hands-off: plan → implement → review → PR → watch CI.

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

- **Always use git worktrees** for feature work. Never develop directly on `main`/`master`.
- Use `/superpowers:using-git-worktrees` or `/ce-worktree` to create worktrees.
- Each feature branch gets its own worktree — work in isolation.
- **Merging to `main`/`master`**: only when explicitly instructed; otherwise ask first when the work is ready to integrate.

### When to use which

| Task | Use |
|------|-----|
| Starting a feature | `/ce-brainstorm` → `/ce-plan` |
| Executing a plan | `/ce-work` — with TDD applied inside it |
| Quick bug fix | `/superpowers:systematic-debugging` (or `/ce-debug`) |
| Pre-merge review | `/ce-code-review` |
| Claiming work is done | `/superpowers:verification-before-completion` |
| Capturing learnings | `/ce-compound` |
| Parallel independent tasks | `/superpowers:dispatching-parallel-agents` |

Do not duplicate these workflows in project CLAUDE.md files. Project files should only add project-specific conventions.

## Commits

- Imperative mood, ≤72 char subject line, one logical change per commit.
- Never commit secrets, API keys, or credentials.
- Never commit or push to main/master without explicit permission. Use feature branches.
