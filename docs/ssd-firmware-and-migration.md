# Samsung 980 PRO: firmware update and migration to the new laptop

**Status: deferred, waiting on the replacement laptop.** Written 2026-09-15.
Decision already taken: keep this SSD and move it into the new machine. That makes
the firmware update mandatory rather than optional, because an un-updated drive
carries the fault across with it.

Companion to [next-install.md](next-install.md), which covers the account-model
changes for the new machine.

## Why this exists

The drive holding `/`, `/boot/efi` and the LUKS `/home` is a **Samsung 980 PRO 2TB,
serial `S6B0NG0RA36145V`**, running firmware **3B2QGXA7**. That firmware is the one
in Samsung's failure advisory, which mainly affects the 2 TB model. The documented
failure mode is the drive switching to read-only without warning, taking its
contents with it.

The published diagnostic signature is a nonzero media-error count together with
available spare below 100%. Both are present here.

### Baseline recorded 2026-09-14 — compare against this later

| SMART field | Samsung 980 PRO 2TB | SK hynix PC711 (control, same laptop) |
|---|---|---|
| Media and data integrity errors | 11,126 | 0 |
| Available spare | 73% | 100% |
| Percentage used (wear) | 9% | 0% |
| Power-on hours | 3,645 | 25,327 |
| Data units written | 84.2 TB | 3.96 TB |
| Unsafe shutdowns | 277 of 868 cycles | 2,206 of 2,852 |
| Critical warning | 0x00 | 0x00 |

The control drive matters: same laptop, same power events, seven times the running
hours, and it is pristine. So this is not environmental and not ordinary ageing.
Wear is only 9% with 84 TB written against a ~1200 TB rating, so the flash is not
exhausted — spare is falling far ahead of wear, which points at defects.

**What has NOT happened:** no kernel I/O errors, no block-layer or ext4 errors, no
filesystem corruption, clean PCIe AER counters, both filesystems still mounted
read-write. Documented cases show errors that appear and vanish across reboots
while the counter climbs, and drives that passed 32,000 errors before locking
read-only. A high counter with no symptoms is the described pre-failure state, not
proof of health.

Sources: [Tom's Hardware](https://www.tomshardware.com/news/samsung-980-pro-ssd-failures-firmware-update),
[NAS Compares](https://nascompares.com/news/avoid-loss-of-data-upgrade-your-samsung-980-pro-ssd-to-the-latest-firmware-0e-error-fix/),
[Puget Systems](https://www.pugetsystems.com/support/guides/critical-samsung-ssd-firmware-update/).

## Target firmware

**5B2QGXA7.** Confirmed current as of 2026-09-15, and confirmed unaffected (so is
4B2QGXA7). Samsung does not publish to LVFS, so **fwupd cannot do this** — it sees
the drive but lists it under "no available firmware updates". Re-check for a newer
release before starting.

## Identify the drive by serial, never by device path

This machine runs Intel VMD/RST and **NVMe enumeration flips between boots**. The
Samsung was `nvme1n1` on 2026-09-09 and `nvme0n1` after the next reboot, with the
SK hynix Windows drive taking the other index. The repo's own `fstrim` logs show
the same filesystem alternating names across weeks.

```sh
# resolve the real path before any command that writes
grep -l S6B0NG0RA36145V /sys/class/nvme/nvme*/serial
```

Read `model` and `firmware_rev` from that same directory. Never paste an `nvmeN`
path from an old note, including this one.

## Step 0 — back up. Blocking.

Non-negotiable: ~1.6 TB on a degrading drive, and a flash carries a small brick
risk. Needs external media; none was attached when this was written.

- Include **`cryptsetup luksHeaderBackup`**. `/home` has a single passphrase
  keyslot and no header backup; a damaged header loses the volume even with the
  correct passphrase.
- Include `/etc`, `/boot` (kernels and initramfs live there on the ext4 root, not
  on the ESP) and a package list (`pacman -Qqe`, `pacman -Qqm`), not just `/home`.
- **Skip** `~/pCloudDrive` and the live `docker-data/docker/overlay2/*/merged`
  paths when copying. Traversing the pCloud FUSE mount wedges it — see the
  pcloud-fuse-blocks-sleep-shutdown note.
- Do **not** use pCloud as the backup target. Flaky FUSE layer, and a 1.6 TB
  network sync is the wrong tool for a pre-flash safety copy.

## Step 1 — Route A: Samsung's own ISO (try this first)

Supported path. Attempt it before anything clever.

```sh
curl -LO https://semiconductor.samsung.com/resources/software-resources/Samsung_SSD_980_PRO_5B2QGXA7.iso
lsblk -o NAME,SIZE,TRAN,RM,MODEL          # identify the USB stick
sudo dd if=Samsung_SSD_980_PRO_5B2QGXA7.iso of=/dev/sdX bs=4M oflag=sync status=progress
```

`sdX` is the **USB stick**, never an NVMe device. Boot it on AC power. If the
updater lists the 980 PRO, let it run and do not interrupt or power off.

## Step 2 — Route B: fallback if the drive does not appear

If the updater cannot see the drive, that is **Intel VMD** — Samsung's ISO kernel
may be too old to see through it.

**Do not "fix" this by switching the BIOS storage mode to AHCI.** The machine is
already in RAID/VMD mode and Linux sees both drives fine; switching changes the PCI
topology and will stop Windows booting until it is prepared for it.

Instead boot a **current EndeavourOS/Arch live USB** (kernel 6.x handles VMD), which
also leaves the target drive unmounted. From the live environment:

```sh
mkdir /tmp/iso && sudo mount -o loop ./Samsung_SSD_980_PRO_5B2QGXA7.iso /tmp/iso/
mkdir /tmp/fwupdate && cd /tmp/fwupdate
gzip -dc /tmp/iso/initrd | cpio -idv --no-absolute-filenames
cd root/fumagician/
sudo ./fumagician
```

Gentoo's wiki flags this path as not Samsung-approved with a small data-loss risk,
which is another reason Step 0 comes first. Never cut power mid-update; reboot
manually when it finishes.

**Never run this from the normal installed system** — it would flash the drive that
`/` and `/home` are mounted from, live.

## Step 3 — verify and set a new baseline

```sh
D=$(dirname "$(grep -l S6B0NG0RA36145V /sys/class/nvme/nvme*/serial)")
cat "$D/firmware_rev"          # expect 5B2QGXA7
sudo smartctl -A /dev/nvmeN | grep -iE 'Available Spare|Percentage Used|Media and Data'
```

Record the numbers here, dated, next to the 2026-09-14 baseline above.

## Step 4 — the keep-or-bin decision, after the update

The firmware fix stops the bug. **It does not undo what already happened**: the 27%
of spare blocks already retired do not come back, and the error counter does not
reset. So the drive enters the new laptop from a degraded baseline.

The case for keeping it is real — endurance is barely touched.

**The test:** note available spare right after the flash, then check again after a
few weeks of normal use.

- Holds steady → bug-induced damage, it stopped, the drive is fine to carry forward.
- Still falling → the flash was not the whole story. **Do not put it in the new
  machine.**

## Step 5 — moving the drive into the new laptop

- Confirm the new machine takes **M.2 2280 NVMe**.
- If the new machine also runs Intel VMD/RST, the same enumeration instability and
  the same Samsung-tooling blind spot apply. Do the firmware update **before** the
  migration, while this laptop is still available as a known-good environment.
- The LUKS volume itself is portable. The **root filesystem is not** — it carries
  machine-specific state (NVIDIA driver and its pinning history, i3 and monitor
  layout, firmware-era workarounds). Plan on carrying `/home` across and doing a
  clean install of the system, which also delivers the account-model changes in
  [next-install.md](next-install.md) (rootless Docker, no `docker`/`libvirt` group,
  wallets isolated, smaller AUR surface) and the encrypted-root and Secure Boot
  decisions that could not be retrofitted here.
- Unrelated but same trip: 277 unclean shutdowns out of 868 power cycles on this
  drive. The pCloud FUSE mount that hangs shutdown is the likely contributor and is
  worth fixing before it follows you to the new machine.

## Context worth keeping

The stutter investigation that surfaced all this had a **second, independent cause**
that is not the drive firmware: `/home` was 99% full and **TRIM never reached it**,
because the LUKS container was opened without `allow-discards`, so `discard_max_bytes`
is 0 and `fstrim` silently skipped it every week — only `/` and `/boot/efi` were ever
trimmed. Freeing space helped (28 GB → 88 GB free on 2026-09-15). **On the new
machine, open the LUKS container with discards enabled from the start** and confirm
`fstrim` actually lists the home filesystem in its logs.
