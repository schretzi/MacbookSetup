#!/bin/bash
# Simple clock, ticking once per update_freq (sketchybarrc: 10s).
set -uo pipefail

sketchybar --set "$NAME" label="$(date '+%a %d %b %H:%M')"
