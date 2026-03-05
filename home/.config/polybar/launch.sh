#!/bin/bash

# Terminate already running bar instances and gcal refresh loop
killall -q polybar
pkill -f "polybar-gcal-refresh" 2>/dev/null

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch polybar on each monitor
for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar main 2>&1 | tee -a /tmp/polybar-$m.log & disown
done

# Periodic gcal refresh: force on launch (with retry), then every 5 min
# Uses CLOCK_MONOTONIC via date checks to detect suspend/resume gaps
(exec -a polybar-gcal-refresh bash -c '
sleep 15
polybar-msg action "#gcal.hook.1"
# Retry once more after 30s in case network was not ready
sleep 30
polybar-msg action "#gcal.hook.0"
last=$(date +%s)
while true; do
    sleep 300
    now=$(date +%s)
    elapsed=$((now - last))
    last=$now
    # If more than 10 min passed (suspend/resume), force refresh
    if (( elapsed > 600 )); then
        polybar-msg action "#gcal.hook.1"
    else
        polybar-msg action "#gcal.hook.0"
    fi
done
') & disown
