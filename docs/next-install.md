# Next install: things to do differently

Deferred from the 2026-09-09 security audit of the current laptop. These are
account-model decisions that only make sense to get right on a fresh install,
not to retrofit.

See also [ssd-firmware-and-migration.md](ssd-firmware-and-migration.md): the Samsung 980 PRO
is being carried over to the new machine and needs its firmware updated first, plus the
LUKS-discards mistake to avoid repeating on the fresh install.

## Do not make the daily user root in all but name

On the current machine the daily user is in `docker` and `libvirt`. Membership
in `docker` alone is root without a password: any code running as that user can
`docker run -v /:/host` and own the machine. That turns every browser tab,
npm dependency and AUR PKGBUILD into a potential root compromise.

On the new machine:

- **Rootless Docker.** `docker-rootless-extras` is already in `packages-aur.txt`;
  set it up from day one (`dockerd-rootless-setuptool.sh install`) and never add
  the user to the `docker` group. If something truly needs the rootful daemon,
  run it through `sudo docker` so there is at least a password prompt and a log
  line.
- **No `libvirt` group either.** Use `sudo virsh` or polkit rules scoped to the
  specific actions needed.
- **Keep `wheel` as the only privileged group**, with sudo asking for a password
  (no `NOPASSWD`).

## Isolate wallet software from the development account

Ledger Live, Trezor Suite and rotki currently share a user account with Brave,
Spotify, VS Code, Slack, Docker and ~70 AUR packages. Anything that lands in that
account can read wallet app state, watch the clipboard and keylog.

On the new machine, pick one:

- **Separate local user** for wallets only: no dev tooling, no AUR, no browser
  extensions, switch to it with a fast user switch when needed. Cheapest option,
  good enough against user-level malware.
- **Dedicated VM** (e.g. a minimal Fedora/Debian guest with USB passthrough for
  the hardware wallets) if stronger separation is wanted.

Hardware wallets already keep the keys off the host; the isolation is about the
companion apps, transaction display and seed-phrase handling.

## Shrink and review the AUR surface

69 foreign packages today. AUR PKGBUILDs are unsigned and have been hijacked
before. On the new machine:

- Install from the official repos or Flatpak where an equivalent exists
  (Brave, Spotify, VS Code, Signal, Slack all have one).
- For what stays on AUR, use a helper that shows PKGBUILD diffs on every
  update (`paru` does by default) and actually read them.
- Keep the wallet apps off AUR entirely: use the vendor AppImage/Flatpak with
  the vendor signature verified, or install them only in the wallet user/VM.
