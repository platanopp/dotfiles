#!/usr/bin/env bash
# Hands the desktop to the virtual display for the length of a stream.
#
# Called from global_prep_cmd in sunshine.conf, which is commented out by
# default -- read the note there before enabling it. The short version: `on`
# leaves this machine with no output anyone in the room can see, and if the
# stream dies without running `off`, getting the panels back means SSH.
#
# hyprctl keyword does not work here ("keyword can't work with non-legacy
# parsers"), because the config is Lua. `hyprctl eval` is the way in.
#
# The `off` values are copied from the two hl.monitor blocks near the end of
# ~/.config/hypr/hyprland.lua. If either monitor is ever retuned there, retune
# it here too -- there is no way to ask Hyprland for "whatever the config said".
set -euo pipefail

case "${1:-}" in
on)
    hyprctl eval 'hl.monitor({ output = "HDMI-A-1", disabled = true })'
    hyprctl eval 'hl.monitor({ output = "DP-2", disabled = true })'
    ;;
off)
    hyprctl eval 'hl.monitor({ output = "HDMI-A-1", disabled = false, mode = "2560x1440@120.00Hz", position = "0x0", scale = 1, cm = "srgb" })'
    hyprctl eval 'hl.monitor({ output = "DP-2", disabled = false, mode = "1920x1080@239.76Hz", position = "-1920x240", scale = 1, cm = "srgb" })'
    ;;
*)
    echo "usage: ${0##*/} on|off" >&2
    exit 1
    ;;
esac
