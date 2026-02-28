#!/bin/sh

step=10

case "$1" in
    up)   brightnessctl set "+${step}%" ;;
    down) brightnessctl set "${step}%-" ;;
    *)    exit 1 ;;
esac

notify-send "Brightness - $(brightnessctl -m | cut -d',' -f4)"
