#!/bin/bash
# Tests for data saving mode (docs/plans/2026-09-14-001-feat-data-saving-mode-plan.md).
#
# Exercises the pure functions of datasave-status and datasave-toggle by sourcing
# them behind their BASH_SOURCE guard, with every external effect stubbed:
# SYSTEMCTL and NMCLI are overridable, and DATASAVE_STATE points at a temporary
# file, so the suite never starts or stops a real service and never touches the
# live mode state.
#
# Run: bash tests/datasave-mode.sh

# Default to the copy tracked in this repo, not the one installed on the
# machine, so the test exercises what a reviewer is reading.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATUS="${DATASAVE_STATUS_SCRIPT:-$REPO_ROOT/home/.config/i3/scripts/datasave-status}"
TOGGLE="${DATASAVE_TOGGLE_SCRIPT:-$REPO_ROOT/home/.config/i3/scripts/datasave-toggle}"
FAILED=0

fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }
pass() { echo "  ok: $*"; }

# Every test runs against a scratch state file, never the live one.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
export DATASAVE_STATE="$SCRATCH/datasave-state"
# The toggle must resolve the tracked status script, not the installed one,
# or the suite silently exercises whatever happens to be on the machine.
export DATASAVE_STATUS="$STATUS"

# Asserts a command's stdout equals an expected string.
assert_out() {
    local desc="$1" expected="$2"; shift 2
    local actual
    actual="$("$@" 2>/dev/null)"
    if [[ "$actual" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected '$expected', got '$actual')"
    fi
}

assert_true()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
assert_false() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }

state_on()  { : > "$DATASAVE_STATE"; }
state_off() { rm -f "$DATASAVE_STATE"; }

echo "== datasave-status renders both states =="
if source "$STATUS" >/dev/null 2>&1; then
    assert_out "render on prints the on glyph"   "$GLYPH_ON"  render on
    assert_out "render off prints the off glyph" "$GLYPH_OFF" render off
    [[ "$GLYPH_ON" != "$GLYPH_OFF" ]] \
        && pass "the two glyphs differ" \
        || fail "the two glyphs are identical, so the indicator cannot show state"
else
    fail "could not source $STATUS to reach its functions"
fi

echo "== sourcing the status script has no side effects =="
state_off
( source "$STATUS" >/dev/null 2>&1 )
[[ -e "$DATASAVE_STATE" ]] \
    && fail "sourcing created a state file" \
    || pass "sourcing created no state file"

echo "== is-on reflects the state file =="
state_off
assert_false "is-on exits non-zero when the mode is off" bash "$STATUS" is-on
state_on
assert_true  "is-on exits zero when the mode is on" bash "$STATUS" is-on
state_off

echo "== stopped <name> reads the recorded consumers =="
state_on
printf 'pcloud\n' > "$DATASAVE_STATE"
assert_true  "stopped pcloud is true when recorded"        bash "$STATUS" stopped pcloud
assert_false "stopped keyring is false when not recorded"  bash "$STATUS" stopped keyring
assert_false "stopped with no name is rejected"            bash "$STATUS" stopped
state_off
assert_false "stopped pcloud is false when the mode is off" bash "$STATUS" stopped pcloud

echo "== record and clear maintain the state file =="
state_off
bash "$STATUS" record pcloud >/dev/null 2>&1
assert_true "record turns the mode on"          bash "$STATUS" is-on
assert_true "record registers the consumer"     bash "$STATUS" stopped pcloud
bash "$STATUS" record pcloud >/dev/null 2>&1
[[ "$(grep -c '^pcloud$' "$DATASAVE_STATE")" == "1" ]] \
    && pass "recording twice does not duplicate the entry" \
    || fail "recording twice duplicated the entry"
bash "$STATUS" clear >/dev/null 2>&1
assert_false "clear turns the mode off" bash "$STATUS" is-on
[[ -e "$DATASAVE_STATE" ]] \
    && fail "clear left the state file behind" \
    || pass "clear removed the state file"

echo "== the status script follows the repo's CLI convention =="
assert_false "an unknown subcommand exits non-zero" bash "$STATUS" bogus
out="$(bash "$STATUS" bogus 2>&1 >/dev/null)"
[[ "$out" == usage:* ]] \
    && pass "an unknown subcommand prints usage to stderr" \
    || fail "an unknown subcommand printed '$out' instead of a usage line"
bash "$STATUS" bogus >/dev/null 2>&1
[[ $? -eq 2 ]] \
    && pass "an unknown subcommand exits 2" \
    || fail "an unknown subcommand did not exit 2"

echo "== datasave-status can turn the mode on without recording a consumer =="
state_off
bash "$STATUS" on >/dev/null 2>&1
assert_true  "on turns the mode on"                      bash "$STATUS" is-on
assert_false "on records no consumer"                    bash "$STATUS" stopped pcloud
bash "$STATUS" clear >/dev/null 2>&1

# ---------------------------------------------------------------------------
# datasave-toggle. Every external effect is stubbed: the suite replaces the
# consumer list with fakes it controls, so no real service is ever touched.
# ---------------------------------------------------------------------------

export NOTIFY_LOG="$SCRATCH/notify.log"   # exported: the stub runs as a child process

# Sources the toggle with a stubbed consumer set. $1 = whether the fake stop
# succeeds ("ok") or fails ("broken").
load_toggle() {
    local behaviour="$1"
    CONSUMERS="fake"
    NOTIFY_SEND="$SCRATCH/stub-notify"
    export CONSUMERS NOTIFY_SEND
    cat > "$SCRATCH/stub-notify" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$NOTIFY_LOG"
STUB
    chmod +x "$SCRATCH/stub-notify"
    # shellcheck disable=SC1090
    source "$TOGGLE" >/dev/null 2>&1 || return 1
    if [[ "$behaviour" == "ok" ]]; then
        ds_stop_fake()  { STOPPED=1; return 0; }
        ds_start_fake() { STARTED=1; return 0; }
    else
        ds_stop_fake()  { return 1; }
        ds_start_fake() { STARTED=1; return 0; }
    fi
}

echo "== the toggle records only what it actually stopped =="
state_off; STOPPED=0; STARTED=0; : > "$NOTIFY_LOG"
if load_toggle ok; then
    enable_mode >/dev/null 2>&1
    assert_true "enabling turns the mode on"          bash "$STATUS" is-on
    assert_true "a stopped consumer is recorded"      bash "$STATUS" stopped fake
    [[ "$STOPPED" == "1" ]] && pass "the consumer's stop ran" || fail "the consumer's stop did not run"
    [[ -s "$NOTIFY_LOG" ]] && pass "enabling notifies" || fail "enabling sent no notification"
else
    fail "could not source $TOGGLE to reach its functions"
fi

echo "== a consumer that fails to stop is not recorded =="
state_off; : > "$NOTIFY_LOG"
if load_toggle broken; then
    enable_mode >/dev/null 2>&1
    assert_true  "the mode still turns on"                 bash "$STATUS" is-on
    assert_false "a consumer that failed is not recorded"  bash "$STATUS" stopped fake
    [[ -s "$NOTIFY_LOG" ]] && pass "a partial failure still notifies" || fail "a partial failure sent no notification"
fi

echo "== disabling restores only what this mode stopped =="
state_off; STARTED=0; : > "$NOTIFY_LOG"
if load_toggle ok; then
    enable_mode >/dev/null 2>&1
    STARTED=0
    disable_mode >/dev/null 2>&1
    [[ "$STARTED" == "1" ]] && pass "a recorded consumer is restored" || fail "a recorded consumer was not restored"
    assert_false "disabling turns the mode off" bash "$STATUS" is-on
    [[ -e "$DATASAVE_STATE" ]] && fail "disabling left the state file behind" || pass "disabling removed the state file"
fi

echo "== a consumer stopped by hand beforehand is left alone =="
state_off; STARTED=0
if load_toggle broken; then
    # The fake reports it could not stop it (already stopped by the user),
    # so disabling must not start something this mode never stopped.
    enable_mode >/dev/null 2>&1
    STARTED=0
    disable_mode >/dev/null 2>&1
    [[ "$STARTED" == "0" ]] && pass "an unrecorded consumer is not started" || fail "disabling started a consumer it never stopped"
fi

echo "== sourcing the toggle has no side effects =="
state_off
( CONSUMERS=fake source "$TOGGLE" >/dev/null 2>&1 )
[[ -e "$DATASAVE_STATE" ]] \
    && fail "sourcing the toggle changed the mode" \
    || pass "sourcing the toggle changed nothing"

# ---------------------------------------------------------------------------
# The polybar consumers. A curl stub proves no network call is made, and every
# cache path is redirected into the scratch directory.
# ---------------------------------------------------------------------------

ETH="$REPO_ROOT/home/.config/i3/scripts/eth_price"
GCAL="$REPO_ROOT/home/.config/i3/scripts/gcal-next"
STUBBIN="$SCRATCH/bin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/curl" <<'STUB'
#!/bin/bash
printf 'called\n' >> "$CURL_LOG"
exit 1
STUB
chmod +x "$STUBBIN/curl"
export CURL_LOG="$SCRATCH/curl.log"

echo "== the polybar consumers honor the mode =="
state_off
bash "$STATUS" on >/dev/null 2>&1

: > "$CURL_LOG"
printf '%s\n' "CACHED-ETH" > "$SCRATCH/eth-cache"
out="$(PATH="$STUBBIN:$PATH" ETH_PRICE_CACHE="$SCRATCH/eth-cache" bash "$ETH" 2>/dev/null)"
[[ "$out" == "CACHED-ETH" ]] \
    && pass "eth_price serves its cached value while the mode is on" \
    || fail "eth_price printed '$out' instead of the cached value"
[[ -s "$CURL_LOG" ]] \
    && fail "eth_price made a network call while the mode is on" \
    || pass "eth_price made no network call while the mode is on"

out="$(PATH="$STUBBIN:$PATH" ETH_PRICE_CACHE="$SCRATCH/nope" bash "$ETH" 2>/dev/null)"
[[ -n "$out" ]] \
    && pass "eth_price still renders with no cache (module stays on the bar)" \
    || fail "eth_price printed nothing with no cache, which hides the module"

out="$(GCAL_CACHE_FILE="$SCRATCH/nope" bash "$GCAL" 2>/dev/null)"
[[ -n "$out" ]] \
    && pass "gcal-next renders a marker with no cache instead of vanishing" \
    || fail "gcal-next printed nothing with no cache, which hides the module"

printf '2020-01-01\n09:00 10:00 Old meeting\n' > "$SCRATCH/gcal-stale"
out="$(GCAL_CACHE_FILE="$SCRATCH/gcal-stale" bash "$GCAL" 2>/dev/null)"
[[ "$out" != *"Old meeting"* && -n "$out" ]] \
    && pass "gcal-next does not present a previous day's events as today's" \
    || fail "gcal-next printed '$out' for a stale-day cache"

echo "== with the mode off the consumers fetch as before =="
bash "$STATUS" clear >/dev/null 2>&1
: > "$CURL_LOG"
PATH="$STUBBIN:$PATH" ETH_PRICE_CACHE="$SCRATCH/eth-cache" bash "$ETH" >/dev/null 2>&1
[[ -s "$CURL_LOG" ]] \
    && pass "eth_price fetches when the mode is off" \
    || fail "eth_price did not fetch when the mode is off"

echo "== the login sweep restores the timer and clears stale state =="
cat > "$STUBBIN/stub-systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
exit 0
STUB
chmod +x "$STUBBIN/stub-systemctl"
export SYSTEMCTL_LOG="$SCRATCH/systemctl.log"
: > "$SYSTEMCTL_LOG"
state_off
bash "$STATUS" record keyring >/dev/null 2>&1   # a mode left on across logout
(
    SYSTEMCTL="$STUBBIN/stub-systemctl"
    CONSUMERS="fake"
    export SYSTEMCTL CONSUMERS
    # shellcheck disable=SC1090
    source "$TOGGLE" >/dev/null 2>&1
    reconcile_session >/dev/null 2>&1
)
grep -q "start archlinux-keyring-wkd-sync.timer" "$SYSTEMCTL_LOG" \
    && pass "the sweep starts the keyring timer" \
    || fail "the sweep did not start the keyring timer"
grep -q -- "--no-ask-password" "$SYSTEMCTL_LOG" \
    && pass "the sweep cannot raise a password prompt" \
    || fail "the sweep omitted --no-ask-password, so it could block on a dialog"
assert_false "the sweep clears stale state" bash "$STATUS" is-on

echo "== the desktop wiring is actually reachable =="
I3="$REPO_ROOT/home/.config/i3/config"
BAR="$REPO_ROOT/home/.config/polybar/config.ini"
grep -q 'bindsym \$mod+Shift+z exec --no-startup-id ~/.config/i3/scripts/datasave-toggle' "$I3" \
    && pass "\$mod+Shift+z is bound to the toggle" \
    || fail "\$mod+Shift+z is not bound"
grep -q 'datasave-toggle reconcile' "$I3" \
    && pass "the login sweep is wired into i3" \
    || fail "the login sweep is not wired into i3"
grep -q 'dropdown-newsboat -e ~/.config/i3/scripts/newsboat-launch' "$I3" \
    && pass "newsboat starts through the launcher at login" \
    || fail "newsboat still starts without the launcher, so the mode cannot reach it"
grep -q '^\[module/datasave\]' "$BAR" \
    && pass "the polybar module block exists" \
    || fail "the polybar module block is missing"
grep -qE '^modules-(left|center|right) =.*\bdatasave\b' "$BAR" \
    && pass "the module is listed on a bar, not just defined" \
    || fail "the module is defined but never listed, so it renders nowhere"

# ---------------------------------------------------------------------------
# The NetworkManager dispatcher. nmcli and systemd-run are stubbed, so nothing
# queries NetworkManager and no notification reaches the session.
# ---------------------------------------------------------------------------

DISPATCH="$REPO_ROOT/etc/NetworkManager/dispatcher.d/90-datasave-metered"
export NMCLI_LOG="$SCRATCH/nmcli.log"
export NOTIFY_ARGS="$SCRATCH/notify-args.log"

cat > "$STUBBIN/stub-nmcli" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$NMCLI_LOG"
printf '%s\n' "${STUB_METERED:-unknown}"
STUB
cat > "$STUBBIN/stub-systemd-run" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$NOTIFY_ARGS"
STUB
chmod +x "$STUBBIN/stub-nmcli" "$STUBBIN/stub-systemd-run"

# run_dispatch <action> <metered> <connection-id>
run_dispatch() {
    : > "$NOTIFY_ARGS"; : > "$NMCLI_LOG"
    env NMCLI="$STUBBIN/stub-nmcli" SYSTEMD_RUN="$STUBBIN/stub-systemd-run" \
        STUB_METERED="$2" CONNECTION_UUID="11111111-2222-3333-4444-555555555555" \
        CONNECTION_ID="$3" NMCLI_LOG="$NMCLI_LOG" NOTIFY_ARGS="$NOTIFY_ARGS" \
        bash "$DISPATCH" wlan0 "$1" >/dev/null 2>&1
}

echo "== the metered offer fires only on an explicit mark =="
run_dispatch up yes "HomeWifi"
[[ -s "$NOTIFY_ARGS" ]] && pass "an explicitly metered connection offers the mode" || fail "no offer on an explicitly metered connection"
[[ "$(wc -l < "$NOTIFY_ARGS")" == "1" ]] && pass "exactly one notification" || fail "expected exactly one notification"

run_dispatch up "yes (guessed)" "HomeWifi"
[[ -s "$NOTIFY_ARGS" ]] && fail "a guessed-metered connection offered the mode" || pass "a guessed-metered connection offers nothing"

run_dispatch up unknown "HomeWifi"
[[ -s "$NOTIFY_ARGS" ]] && fail "an unmarked connection offered the mode" || pass "an unmarked connection offers nothing"

run_dispatch down yes "HomeWifi"
[[ -s "$NOTIFY_ARGS" ]] && fail "a non-up action offered the mode" || pass "only the up action offers the mode"

echo "== the dispatcher does not trust the connection name =="
run_dispatch up yes "HomeWifi"
benign="$(cat "$NOTIFY_ARGS")"
run_dispatch up yes '-X --evil <b>spoofed</b>'
hostile="$(cat "$NOTIFY_ARGS")"
[[ "$benign" == "$hostile" ]] \
    && pass "the notification text is identical whatever the SSID is called" \
    || fail "the connection name leaked into the notification"
grep -q "uuid" "$NMCLI_LOG" \
    && pass "the profile is looked up by UUID" \
    || fail "the lookup does not use the UUID"
grep -q "evil" "$NMCLI_LOG" \
    && fail "the attacker-chosen connection name reached the nmcli call" \
    || pass "the connection name never reaches the nmcli call"

echo "== the tracked copies match the installed ones =="
# sync.sh copies live -> repo, so a live edit that was never synced would leave
# the tracked copy behind. /etc files are excluded: they are backup-only and are
# installed by hand, so they are legitimately absent from the live machine.
if [[ -n "${DATASAVE_STATUS_SCRIPT:-}${DATASAVE_TOGGLE_SCRIPT:-}" ]]; then
    pass "skipped — an explicit script path was set"
else
    drift=0
    for rel in .config/i3/scripts/datasave-status \
               .config/i3/scripts/datasave-toggle \
               .config/i3/scripts/newsboat-launch \
               .config/i3/scripts/eth_price \
               .config/i3/scripts/gcal-next \
               .config/i3/config \
               .config/polybar/config.ini \
               .config/newsboat/config.datasave; do
        if [[ -e "$HOME/$rel" ]] && ! diff -q "$HOME/$rel" "$REPO_ROOT/home/$rel" >/dev/null 2>&1; then
            fail "tracked copy of $rel differs from the installed one — run sync.sh"
            drift=1
        fi
    done
    (( drift == 0 )) && pass "tracked and installed copies match"
fi

echo
if (( FAILED > 0 )); then
    echo "FAILED: $FAILED assertion(s)"
    exit 1
fi
echo "All assertions passed."
