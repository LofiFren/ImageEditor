#!/bin/bash
#
# Give an Omarchy monitors.lua the uConsole's screen settings: scale 1 (Omarchy
# defaults to auto/2, made for laptop screens, which makes everything huge on
# this 5" panel) and the DSI panel's rotation. Safe to run again.
#
# Usage: uconsole-monitors.sh <monitors.lua> [transform]
#   transform: Hyprland's rotation, 3 (270 degrees) by default.

set -euo pipefail

FILE="${1:?usage: uconsole-monitors.sh <monitors.lua> [transform]}"
TRANSFORM="${2:-3}"

[ -f "${FILE}" ] || { echo "ERROR: ${FILE} not found." >&2; exit 1; }

sed -i -e 's/^local omarchy_gdk_scale = .*/local omarchy_gdk_scale = 1/' \
       -e 's/^local omarchy_monitor_scale = .*/local omarchy_monitor_scale = 1/' "${FILE}"
grep -q '^local omarchy_monitor_scale = 1$' "${FILE}" \
    || { echo "ERROR: could not set Omarchy's monitor scale -- ${FILE} changed shape." >&2; exit 1; }

if ! grep -q 'output = "DSI-1"' "${FILE}"; then
    cat >> "${FILE}" << LUA

-- ClockworkPi uConsole: the DSI panel is a portrait 720x1280 mounted sideways.
-- transform 3 = 270 degrees, which reads landscape. Try 1 if it is upside down.
hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = 1, transform = ${TRANSFORM} })
LUA
fi
