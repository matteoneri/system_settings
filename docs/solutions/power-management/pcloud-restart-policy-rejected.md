---
title: "Restart=on-failure on pcloud.service is unsafe once SIGKILL stops being a success status"
date: 2026-08-23
category: power-management
module: pcloud-sleep-path
problem_type: design_decision
component: systemd
symptoms:
  - "pCloud dies mid-session (OOM, crash) and nothing brings it back"
  - "A restart policy looks like the obvious fix and passes review in isolation"
root_cause: interaction_between_two_individually_correct_changes
resolution_type: rejected
severity: medium
tags: [systemd, pcloud, suspend, fuse, restart-policy, code-review, rejected]
---

# Finding #12: Restart= on pcloud.service -- REJECTED

## Status

**Rejected**, 2026-08-23. Raised by the `reliability` reviewer during the code review of
the pCloud sleep-path units (commit `e6fa561`). Not applied, and should not be applied in
the form proposed.

## What was proposed

`~/.config/systemd/user/pcloud.service` has no `Restart=`, so a pCloud that dies
mid-session for any reason stays dead until the next suspend/resume cycle or a manual
start. The reviewer proposed:

```ini
Restart=on-failure
RestartSec=5
```

with the argument that `SuccessExitStatus` already exempts the deliberate teardown kill,
so the policy would only engage on a genuine crash.

## Why it was rejected

That argument was true when written and stopped being true in the same review.

Finding #4 narrowed the unit from `SuccessExitStatus=SIGTERM SIGKILL` to
`SuccessExitStatus=SIGTERM`, because listing SIGKILL reported kernel OOM kills as clean
stops. That is the right change on its own. But it also means the teardown's **SIGKILL
fallback** is no longer exempt:

1. Lid closes; `pcloud-suspend.service` runs `/usr/local/bin/pcloud-teardown`.
2. The teardown asks pCloud to exit (SIGTERM), waits up to 5s, then `pkill -KILL`.
3. If it reached the SIGKILL fallback, `pcloud.service` now enters **failed**.
4. `Restart=on-failure` + `RestartSec=5` relaunches pCloud about five seconds later --
   inside the suspend sequence, after `pcloud-suspend.service` has already finished.
5. The relaunched pCloud re-creates the FUSE mount the teardown just released, moments
   before `systemd-suspend.service` freezes `user.slice`.

That is precisely the condition the whole sleep path exists to prevent: a live pCloud
FUSE mount present at freeze time. The fix would reintroduce the original bug on exactly
the path where the teardown had the most trouble.

**#4 and #12 are each safe alone and harmful together.** The reviewer evaluated #12
against the pre-#4 unit, which is why the interaction was missed.

## What to do instead

Nothing, for now. The gap #12 identifies is real but small: pCloud dying mid-session
without a resume to revive it. Weigh that against the cost before acting.

If crash recovery is wanted later, the restart policy must be inhibited for the sleep
window. Options, roughly in order of preference:

- Have `pcloud-suspend.service` stop the user unit through the user bus
  (`systemctl --user --machine=matteo@.host stop pcloud.service`) *before* the teardown
  runs. A systemd-initiated stop is a clean stop regardless of signal, so the unit never
  enters `failed` on the suspend path and a restart policy could then coexist. Cost: adds
  a user-bus call to the suspend path, which is the latency-sensitive half.
- `StartLimitIntervalSec` / `StartLimitBurst` tuned so a single suspend-time failure
  cannot trigger a relaunch. Fragile -- it depends on timing rather than on intent.

## Related

- Commit `e6fa561` -- the sleep-path units and the rest of the review fixes.
- Finding #4 (applied): `SuccessExitStatus` narrowed to SIGTERM so OOM kills stay visible.
- The rejection is also recorded as a comment in `home/.config/systemd/user/pcloud.service`,
  at the point where someone would be tempted to add the directive.
