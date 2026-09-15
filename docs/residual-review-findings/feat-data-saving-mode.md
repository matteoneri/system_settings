# Residual Review Findings — feat/data-saving-mode

From the `ce-code-review` pass on this branch (correctness, security, reliability,
testing, adversarial) plus the `ce-simplify-code` pass (reuse, quality,
efficiency). Everything actionable was applied in `4f02959`; these are the items
deliberately **not** applied, with the reason. No tracker is configured for this
repo, so this file is the durable record.

## Declined, with reason

- **P2 — extract the tracked-vs-installed drift check shared by `tests/datasave-mode.sh`
  and `tests/session-layout-roundtrip.sh`.** Declined: two occurrences. The
  project standard is to extract on the third ("no premature abstraction").
- **P2 — "plain i3 `exec` re-fires on `i3-msg restart`, racing the login sweep against
  newsboat's mode read".** Declined: the premise is wrong. Only `exec_always`
  re-runs on restart; this config uses both forms deliberately (19 `exec`, 2
  `exec_always`) and says so at `home/.config/i3/config`. The ordering was still
  made deterministic by moving the sweep above the newsboat launch.
- **P3 — also stop `archlinux-keyring-wkd-sync.service` when stopping its timer,
  so an in-flight key sync does not keep downloading.** Declined for now: it
  requires widening the polkit grant to a third unit, which is a real cost
  against a narrow window (the sync must be running at the moment the mode is
  enabled). Revisit if it is ever observed.
- **P3 — `reconcile` starts the keyring timer without checking it was this mode
  that stopped it.** Declined: by the time the sweep runs the record is gone with
  the runtime directory, which is exactly why the sweep exists. Conditioning it
  on the record would mean never restoring. The accepted cost is documented in
  the function's comment.

## Known limitations, recorded not fixed

- **`DESKTOP_USER` / `subject.user` are hardcoded to `matteo`** in the dispatcher
  and the polkit rule, and `pcloud-resume.service` hardcodes uid 1000. On a
  machine restored under a different username the mode degrades silently: no
  metered offer, no privileged stops. Consistent with the existing pCloud units,
  which already hardcode the same identity.
- **The cached ETH price has a staleness *marker* but no age *bound*.** After a
  long trip the bar shows an old price beside the paused glyph rather than
  falling back to the placeholder.
- **`pcloud-teardown`'s orphan-FUSE branch reads `/proc/self/mountinfo` in the
  system manager's namespace only.** A FUSE mount inside another mount namespace
  is invisible there and would be classified as orphaned. Pre-existing; the new
  `ExecCondition` and the mount-aware guard narrow how often that branch is
  reached, they do not change the branch itself.
- **polkit's `auth_admin_keep` cache lifetime was taken as documented, not
  measured.** A stop that succeeds on a warm cache and a start that fails on a
  cold one is the sequence the re-record fix now handles.
- **Nothing privileged has run in its installed form.** The three `/etc` files are
  not installed on this machine, so every claim about the unit, the dispatcher
  and polkit acting together is from the files, not an observed run. The plan's
  manual verification gate covers this.

## Coverage note

The cross-model adversarial peer did not run: it would have sent this diff to an
external provider, which was not authorized for this session, so the in-process
adversarial reviewer was the only adversarial lens. Its agreement with the other
reviewers is **not** independent corroboration.
