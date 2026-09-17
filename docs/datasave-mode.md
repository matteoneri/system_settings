# Data saving mode

A manual toggle, in the same shape as the Do Not Disturb one, that stops the
background work which spends internet data unattended. Anything you are actively
driving — browser, terminal, editors, agent CLIs — is never touched.

Plan: `docs/plans/2026-09-14-001-feat-data-saving-mode-plan.md` (plan key `datasave`).

## Using it

- **`$mod+Shift+z`** toggles it, next to `$mod+z` for Do Not Disturb.
- **Left-click the polybar indicator** does the same. The indicator shows a cloud
  normally and a struck-through cloud while the mode is on. Polybar has no IPC in
  this setup, so it follows on its own 5s poll rather than instantly.
- Joining a connection you have **marked metered** raises a notification offering
  the mode. It never enables itself.

Mark a connection metered once and NetworkManager remembers it:

```bash
nmcli connection modify "<connection name>" connection.metered yes
```

Marking is deliberate: NetworkManager also *guesses* metered at the device level
and reports `yes (guessed)` on ordinary wifi, so keying the offer on the guess
would prompt you daily on networks that are fine.

## What it stops

| Consumer | While the mode is on |
|---|---|
| pCloud | Stopped through the same teardown the suspend path uses |
| polybar ETH module | Throttled to one fetch per 5 minutes instead of every 60s |
| polybar calendar module | Serves its cached day, no request to Google |
| `archlinux-keyring-wkd-sync.timer` | Stopped |
| newsboat | Quit if it is hidden; a later open starts without auto-reload |

Each consumer is independent and fails soft. The mode records only what it
actually stopped, so turning it off never starts something it did not stop — if
you had already quit pCloud yourself, it stays quit.

A newsboat you are **reading** is left alone, because the mode never disturbs
anything on screen.

## What it does not do

It does not throttle foreground applications, and it does not block traffic at
the firewall. It stops a named list, so a background consumer added to this
machine later will keep using data until it is added to that list too.

## It suppresses a security control, not only a data cost

While the mode is on, Arch packager keys are not refreshed and pCloud backups are
not current. That is fine for a trip; it is not something to leave on for weeks.

## Installation

The scripts and desktop config live under `home/` and are restored normally by
`restore.sh`. Three files live under `etc/`, which this repository **backs up but
never restores** — install them by hand on a new machine:

```bash
sudo install -m 0644 -o root -g root \
  etc/systemd/system/pcloud-datasave.service /etc/systemd/system/pcloud-datasave.service
sudo install -m 0644 -o root -g root \
  etc/polkit-1/rules.d/49-datasave-units.rules /etc/polkit-1/rules.d/49-datasave-units.rules
sudo install -m 0755 -o root -g root \
  etc/NetworkManager/dispatcher.d/90-datasave-metered /etc/NetworkManager/dispatcher.d/90-datasave-metered
sudo systemctl daemon-reload
```

NetworkManager silently ignores a dispatcher script that is not root-owned or
that is group- or world-writable, so the ownership and mode above matter.

**Until the polkit rule is installed**, the mode still stops the polybar fetches
and newsboat, but reports pCloud and the keyring timer as not stopped. Managing
system units is `auth_admin_keep` on this machine; the toggle passes
`--no-ask-password`, so an unauthorized call fails quietly instead of raising a
modal password dialog. The rule is scoped to one user and those two units.

## State

The mode's state is a file in `$XDG_RUNTIME_DIR`, listing what it stopped.
logind removes that directory at logout, which is what makes the mode
session-scoped — it is off after a reboot or a logout. Because the record goes
with it, i3 runs `datasave-toggle reconcile` at login to restart the keyring
timer and clear stale state.

## Testing

```bash
bash tests/datasave-mode.sh
```

The suite stubs `systemctl`, `nmcli`, `curl` and `notify-send`, and points the
state file at a temporary path, so it never touches a real service or your live
mode state. The scenarios that need a live pCloud, an authenticated unit start,
or a real NetworkManager event are verified by hand — see the plan's Verification
Contract.
