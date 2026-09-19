# Mirror re-rank prompt

A standing flag that arms when the laptop's timezone changes or the pacman
mirror ranking is more than 30 days old, and a prompt at every new terminal
that keeps asking until a re-rank actually succeeds. It replaces a `tzupdate`
wrapper that asked once and forgot.

Plan: `docs/plans/2026-09-18-001-feat-mirror-rerank-prompt-plan.md` (plan key `mirrors`).

## Using it

While the flag is armed, every new interactive terminal prints why and what it
costs, then asks:

```
[mirrors] A mirror re-rank is due:
timezone changed: Asia/Dubai -> Europe/Helsinki
last ranked 276 days ago (limit 30)
re-ranking downloads up to ~530MB and takes 5-10 min
Update mirrors now? [y/N]
```

`y` runs the re-rank. Anything else leaves the flag armed and the next terminal
asks again. There is no dismiss, snooze, or never: persistence is the point.
The prompt appears whatever network you are on, metered included, which is why
it states the cost first.

It arms when any of these hold:

- the system timezone differs from the one recorded at the last ranking —
  however the zone changed, `tzupdate` or otherwise;
- the last ranking is more than 30 days old;
- there is no record of a ranking at all.

Only a run in which **both** rankings succeed clears it. You can also drive the
script directly:

```bash
~/.config/i3/scripts/mirror-rerank status   # why it is armed; exit 1 when fresh
~/.config/i3/scripts/mirror-rerank run      # re-rank if due; when the ranking is
                                            # fresh it says so on stderr and exits 0
                                            # (remove the state file to force one)
```

## What `y` runs, and what it costs

1. `sudo -v` — your password is asked **first**, right after the lock, while
   you are still at the keyboard. A refusal stops the run before anything is
   downloaded. The cached credential is what the installs below use; if the
   rate test outlasts sudo's cache (five minutes by default) the install will
   ask once more.
2. `reflector --protocol https --age 12 --latest 60 --sort rate --number 20`,
   as your user, into a private temporary directory. It keeps the sixty most
   recently synced mirrors (synced within twelve **hours** — `--age` is hours)
   and rate-tests all sixty from where you are, keeping the fastest twenty.
   Rating downloads each mirror's full `extra.db` (~8.9MB here), one mirror at
   a time, so a run is up to ~530MB and 5-10 minutes with the terminal blocked.
3. The result is refused unless every server line is `https://`, there are at
   least ten of them, and at least **ten** mirrors were actually rated. A link
   that serves reflector's status file but times out most downloads otherwise
   produces a list that is mostly unranked with a clean exit; on such a link the
   flag stays armed until you reach a better one, which is the point.
4. Two `sudo install` calls, argv-form, never a shell string: the live list to
   `/etc/pacman.d/mirrorlist.bak`, then the new list into place as `root:root
   0644`.
5. `eos-rankmirrors`, which ranks the EndeavourOS list and escalates by itself.
   Its exit status cannot report a failed write, so success is judged by the
   file: the mirrorlist's modification time advanced, or the tool said the
   ranking was already current, and it never printed `Failed.`.
6. The zone and time are recorded.

If any step after the rate test fails, the flag stays armed and the next `y`
repeats the download. Asking for the password first removes the commonest cause
of that; the remaining one is `eos-rankmirrors` failing on its own.

A second terminal that answers `y` while a run is in progress says so and does
nothing; one that answers `y` after the run finished finds the state fresh and
exits quietly.

## What it does not do

It never ranks unattended. `reflector.timer` stays disabled and there is no
pacman hook — verified 2026-09-18: `systemctl is-enabled reflector.timer`
prints `disabled`, and `/etc/pacman.d/hooks/` is empty. This is recorded here
rather than asserted by the test suite because the feature never touches either,
so a suite gate could only fail for unrelated reasons (and `is-enabled` exits 1
while printing `disabled`).

It does not suppress the prompt on metered connections, even though the
data-saving mode knows which connections are metered. It does not touch how
`paru` upgrades run.

## Installation

Everything lives under `home/` and is restored normally: the script by the `i3`
component (`restore.sh` copies and `chmod +x`s the whole scripts directory) and
the hook by `shell-desktop` (the full `.zshrc`). `sync.sh` already globs the
scripts directory, so neither needed an edit. There are no `/etc` files.

Install order matters: `sync.sh` copies live → repo and `restore.sh` copies repo
→ live. Edit the repo copies, install them, then run `sync.sh` to confirm they
match — running `sync.sh` first would overwrite the new repo copies with the old
live ones.

## State, and disarming by hand

The record is `~/.local/state/mirror-rerank/state`:

```
zone=Asia/Dubai
ranked_at=1758200000
```

It must survive reboot, so it lives under the XDG state directory, not the
runtime directory. It is machine-local — it says what *this* machine last ranked
and under which zone — and is deliberately not synced. A missing, empty, or
malformed file arms rather than reading as fresh.

To disarm without ranking (you know the mirrors are fine):

```bash
mkdir -p ~/.local/state/mirror-rerank
printf 'zone=%s\nranked_at=%s\n' "$(timedatectl show -p Timezone --value)" "$(date +%s)" \
  > ~/.local/state/mirror-rerank/state
```

To re-arm: `rm ~/.local/state/mirror-rerank/state`.

The lock is `$XDG_RUNTIME_DIR/mirror-rerank.lock`, held with `flock` and released
by the kernel when the process dies, so a terminal closed mid-run cannot leave
the feature saying "in progress".

## Recovering the Arch mirrorlist

If a ranking left you on a bad list — pacman cannot reach any repository — the
previous list is one command away:

```bash
sudo install -o root -g root -m 0644 -- /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
```

`eos-rankmirrors` keeps its own `/etc/pacman.d/endeavouros-mirrorlist.bak` the
same way, and can rebuild its list from hardcoded fallback mirrors.

## Trust boundary

Reflector fetches the mirror list from `archlinux.org` over verified TLS, so a
captive portal fails closed rather than injecting mirrors. pacman verifies
package signatures whatever the mirror. What a hostile or stale mirror *can* do
is downgrade or freeze — serve an old database, withhold updates, offer an old
validly-signed package — because `/etc/pacman.conf` here is `SigLevel =
Required DatabaseOptional`: the repository database itself is not
signature-required. The https-only gate and the `.bak` are the mitigations; the
root cause is that pacman setting, which this feature leaves alone.

One habit this feature trains, recorded on purpose: it asks for a root password
in response to a banner at terminal start, on whatever network you are on.
Nothing distinguishes it from a lookalike printed by anything else that can
write to the terminal.

## Testing

```bash
bash tests/mirror-rerank.sh
```

The suite stubs `timedatectl`, `reflector`, `eos-rankmirrors` and `sudo`, and
points the state, the lock, and both mirrorlists into a temporary directory, so
it never touches `/etc/pacman.d/`, your live state, or the real lock. The hook is
extracted from the tracked `.zshrc` and driven under a pseudo-terminal, because
zsh's `read -k` reads the terminal, not stdin. `bash tests/datasave-mode.sh`
carries the repo-wide drift check that fails when the installed script differs
from the tracked one.
