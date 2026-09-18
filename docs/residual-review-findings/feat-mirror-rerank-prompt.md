# Residual Review Findings — feat/mirror-rerank-prompt

From the `ce-code-review` pass on this branch (correctness, security, adversarial,
testing, maintainability, reliability; validated independently) plus the
`ce-simplify-code` pass. Every actionable finding was applied and is covered by
`tests/mirror-rerank.sh`. These are the items deliberately **not** applied, with
the reason, and the limitations recorded rather than fixed. No tracker is
configured for this repo, so this file is the durable record. Run artifact:
`/tmp/compound-engineering-1000/ce-code-review/20260918-3281413-mirrors/`.

## Decisions pending (owner's call, not applied)

- **P2 — the rated gate accepts a list where one mirror rated and nineteen timed
  out.** The rated mirror sorts first and pacman tries mirrors in order, so the
  installed list works, but its fallbacks are unrated. Raising the floor to
  `MIN_SERVERS` (10) rated mirrors would keep the flag armed on poor links until
  a good one is reached — the plan's F1 intent — at the cost of never clearing on
  a marginal connection. KTD7 as approved says "at least one". Left at one.
- **P2 — any failure after the rate test repeats the full ~530MB download.** A
  refused or expired sudo password (the prompt lands 5-10 minutes after `y`) or
  an `eos-rankmirrors` failure leaves the flag armed and the next accept re-rates
  all sixty mirrors, discarding a validated list. Two design changes are on the
  table: `sudo -v` right after the lock so the password prompt lands while the
  user is present (sudo's cached credential may still expire during a long rate
  test), or keeping the validated list next to the state file and reusing one
  younger than an hour. The plan accepts the post-rate-test prompt as written.

## Pre-existing, adjacent (out of this plan's scope)

- **P1 — `_settings_sync_check` has no interactive/TTY guard.** The weekly sync
  prompt directly above the new hook (`home/.zshrc`, since 2026-02-28) blocks on
  `read -r -k 1` in any shell that sources `.zshrc` once `.last_sync` is a week
  old — the exact hazard the new hook guards against with
  `[[ -o interactive && -t 0 ]] || return 0`, and it shares the Ctrl-C exposure
  the new hook now traps. The same one-line guard (and the same `localtraps`
  trap) belongs there, as its own commit; the plan excludes the sync check from
  scope.

## Declined, with reason

- **P2 — extract a `_ask_yn` helper for the y/N prompt idiom in `.zshrc`.** The
  new hook is the idiom's third occurrence, which crosses the repo's recorded
  "extract on the third" line. Declined in this branch: two of the three call
  sites are inside `_settings_sync_check`, which is untested and outside the
  scope of the simplification pass. Extract when that function is next touched
  (the guard above is the natural moment).
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
