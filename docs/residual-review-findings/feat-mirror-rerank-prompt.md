# Residual Review Findings — feat/mirror-rerank-prompt

From the `ce-code-review` pass on this branch (correctness, security, adversarial,
testing, maintainability, reliability; validated independently) plus the
`ce-simplify-code` pass. Every actionable finding was applied and is covered by
`tests/mirror-rerank.sh`. These are the items that were left to the owner, what
was decided, and the limitations recorded rather than fixed. No tracker is
configured for this repo, so this file is the durable record. Run artifact:
`/tmp/compound-engineering-1000/ce-code-review/20260918-3281413-mirrors/`.

## Decided by the owner on 2026-09-19, and applied

- **P2 — the rated gate accepted a list where one mirror rated and nineteen
  timed out.** Decided: raise the floor. `validate_mirrorlist` now requires at
  least `MIN_RATED` (10) mirrors rated at a non-zero rate, not one. On a poor
  link the flag stays armed until a better one is reached, which is the plan's
  F1 intent; the cost is that a marginal connection never clears the flag.
- **P2 — any failure after the rate test repeated the full ~530MB download.**
  Decided: the cheap mitigation. `run` calls `sudo -v` right after the lock and
  the fresh re-check, so the password prompt lands while the user is present and
  a refusal costs nothing. The remaining repeat path is an `eos-rankmirrors`
  failure after a good Arch install; caching the validated list was not taken.
- **P1, pre-existing — `_settings_sync_check` had no interactive/TTY guard and
  the same Ctrl-C exposure.** Decided: fix it in this branch. It now carries the
  same `[[ -o interactive && -t 0 ]] || return 0` guard and the same INT trap
  as the mirror hook.
- **P2 — extract the y/N prompt idiom, now at its third occurrence.** Applied
  as part of the sync-check fix, the natural moment to touch that function:
  `_ask_yn` owns the prompt, the single-key read, the type-ahead drain, and the
  trailing newline for all three prompts.

## Declined, with reason

- **P3 — `live_zone` should set a global instead of printing, saving one fork per
  terminal.** Declined: one subshell on the status path is not worth a less clear
  contract; `EPOCHSECONDS` already removed the `date` fork that mattered.

## Known limitations, recorded not fixed

- **`COST_LINE` is a hand-typed string** with no code link to `POOL` or `KEEP`; a
  future change to either constant would silently leave the prompt's stated cost
  wrong. Documented beside the constants as a manual-sync obligation.
- **The "was not ranked, not saving" success path is practically unreachable**
  against the installed `eos-rankmirrors` 26.8: its ranked output carries a
  dated header, so it is never byte-identical to the fetched list. Real-world
  success rests on the mirrorlist's mtime advancing. The branch fails closed if
  the tool changes.
- **`eos-rankmirrors`' stderr is captured wholesale**, so during the EndeavourOS
  phase the user sees only its stdout list, and a bare `[sudo]` prompt on the
  terminal if its internal escalation re-prompts. Failures are still surfaced by
  the log tail.
- **`$XDG_RUNTIME_DIR` is used without the owner/mode check the fallback path
  applies.** `/run/user/1000` is `0700` here (verified); a design asymmetry, not
  an exposure.
- **The rated-gate regex is pinned to reflector's `--verbose` format** (verified
  exact against reflector 2023-5). A format change would make the gate fail
  closed — reject — never silently pass.
- **The flag is armed from install.** No state file exists and both live lists
  date from 2025-12-16, so every new terminal prompts until a full run succeeds
  or the state is written by hand (`docs/mirror-rerank.md`, "disarming by hand").
  Intended.
- **Same-uid environment overrides steer the privileged step.** Anything able to
  set the login shell's environment already executes code as the user, so no
  new trust boundary is crossed; the `MIRROR_RERANK_*` namespacing is the plan's
  recorded mitigation.
- **The feature trains typing a root password in response to a startup banner**,
  on whatever network the laptop is on, and sudo's cached credential then also
  covers `eos-rankmirrors`' internal escalation. Accepted and documented in
  `docs/mirror-rerank.md`.
- **A `tzupdate` during the 5-10 minute run** leaves the recorded zone (read at
  lock time) stale and re-arms the flag at the next terminal — the conservative
  direction, at the cost of another full run.
- **`docs/specs/2026-04-17-selective-restore-and-portable-zshrc.md:62`** still
  lists `tzupdate` among what the portable zshrc drops. Stale wording; no
  runtime effect.

## Coverage note

The cross-model adversarial peer did not run: it would have sent this diff —
the owner's zshrc and system scripts — to an external provider, which was not
authorized for this session (the same choice recorded for
`feat/data-saving-mode`). The in-process adversarial reviewer was the only
adversarial lens; its agreement with the other reviewers is **not** independent
corroboration. All seven applied findings were, however, independently
reproduced by a separate validation pass before being applied.
