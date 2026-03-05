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

# Periodic gcal refresh aligned to 5-minute clock boundaries (:00, :05, :10, ...)
# so color transitions (10-min warning, live) happen at predictable times
(exec -a polybar-gcal-refresh bash -c '
sleep 15
polybar-msg action "#gcal.hook.1"
last=$(date +%s)
while true; do
    # Sleep until the next 5-minute wall-clock boundary
    now=$(date +%s)
    sleep_time=$(( 300 - now % 300 ))
    sleep $sleep_time
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
