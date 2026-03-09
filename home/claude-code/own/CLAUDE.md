# Global Development Standards

Global instructions for all projects. Project-specific CLAUDE.md files override these defaults.

## Philosophy

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

Two workflow plugins are installed: **Superpowers** (implementation discipline) and **Compound Engineering** (planning depth + multi-agent review). Use each for what it's best at:

### Implementation (Superpowers)

- **TDD**: `/superpowers:test-driven-development` — red-green-refactor, always.
- **Debugging**: `/superpowers:systematic-debugging` — 4-phase root cause analysis, not symptom treatment.
- **Verification**: `/superpowers:verification-before-completion` — evidence before assertions.
- **Subagent execution**: `/superpowers:subagent-driven-development` — fresh agent per task, two-stage review.

### Planning & Review (Compound Engineering)

- **Brainstorm**: `/ce:brainstorm` — explore requirements and approaches before planning.
- **Plan**: `/ce:plan` — implementation plans with parallel research agents.
- **Work**: `/ce:work` — execute with worktrees and task tracking.
- **Review**: `/ce:review` — 15 specialized agents in parallel (security, performance, architecture, simplicity, data integrity, etc.).
- **Compound**: `/ce:compound` — document learnings so future work benefits.
- **Full auto**: `/lfg` (sequential) or `/slfg` (swarm/parallel) for autonomous end-to-end workflows.

### When to use which

| Task | Use |
|------|-----|
| Starting a feature | `/ce:brainstorm` → `/ce:plan` |
| Implementing | Superpowers TDD + subagent execution |
| Quick bug fix | `/superpowers:systematic-debugging` |
| Pre-merge review | `/ce:review` |
| Claiming work is done | `/superpowers:verification-before-completion` |
| Capturing learnings | `/ce:compound` |
| Parallel independent tasks | `/superpowers:dispatching-parallel-agents` |

Do not duplicate these workflows in project CLAUDE.md files. Project files should only add project-specific conventions.

## Commits

- Imperative mood, ≤72 char subject line, one logical change per commit.
- Never commit secrets, API keys, or credentials.
- Never commit or push to main/master without explicit permission. Use feature branches.
