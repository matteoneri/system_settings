#!/bin/bash

step=10

case "$1" in
    up)   brightnessctl set "+${step}%" ;;
    down) brightnessctl set "${step}%-" ;;
    *)    exit 1 ;;
esac

dunstify -t 1000 -r 2594 "Brightness - $(brightnessctl -m | cut -d',' -f4)"
