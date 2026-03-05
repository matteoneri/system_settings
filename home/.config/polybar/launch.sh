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

