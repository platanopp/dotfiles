#!/usr/bin/env bash
# Brings the virtual display in and out for the length of a stream.
#
# DP-1 has no cable in it. The kernel force-enables the connector with a canned
# EDID, so at the DRM level it is there from boot and always will be -- that
# cannot be undone without a reboot, and undoing it is not wanted anyway: it is
# what guarantees Hyprland has somewhere to draw when every physical panel is
# switched off. What this script controls is the other half, whether Hyprland
# *uses* it, which is what actually shows up as a phantom monitor.
#
#   attach   enable it, at the streaming mode  (stream start)
#   detach   disable it, IF something else is enabled  (stream end, and login)
#   blank    turn the physical panels off  (opt-in, see sunshine.conf)
#   unblank  turn them back on
#
# That condition on `detach` is the whole safety of this. Hyprland has no guard
# against disabling its last output -- it has a FallbackStateKeeper, which is
# precisely the unusable state to stay out of -- so disabling DP-1 while the
# real panels are off would kill the session, with no way back in but SSH.
#
# hyprctl keyword does not work here ("keyword can't work with non-legacy
# parsers"), because the config is Lua. `hyprctl eval` is the way in.
#
# The panel values in `unblank` are copied from the two hl.monitor blocks near
# the end of ~/.config/hypr/hyprland.lua. If either is retuned there, retune it
# here too; there is no way to ask Hyprland for "whatever the config said".
set -uo pipefail

VIRTUAL="DP-1"
VIRTUAL_MODE="1600x900@60.00Hz"
VIRTUAL_POSITION="2560x0"

# hyprctl only lists monitors that are enabled, so this is the live answer to
# "would turning DP-1 off leave us with nothing".
enabled_monitors() {
    hyprctl monitors -j 2>/dev/null | python3 -c 'import sys,json;print("\n".join(m["name"] for m in json.load(sys.stdin)))' 2>/dev/null
}

case "${1:-}" in
attach)
    hyprctl eval "hl.monitor({ output = \"$VIRTUAL\", disabled = false, mode = \"$VIRTUAL_MODE\", position = \"$VIRTUAL_POSITION\", scale = 1 })" >/dev/null
    # Sunshine picks its output right after these prep commands return, and a
    # wl_output takes a moment to appear. Waiting here is cheaper than a stream
    # that starts on the wrong screen.
    for _ in $(seq 20); do
        enabled_monitors | grep -qx "$VIRTUAL" && break
        sleep 0.1
    done
    ;;
detach)
    others="$(enabled_monitors | grep -vx "$VIRTUAL" || true)"
    if [ -z "$others" ]; then
        echo "keeping $VIRTUAL: it is the only enabled output"
        exit 0
    fi
    hyprctl eval "hl.monitor({ output = \"$VIRTUAL\", disabled = true })" >/dev/null
    ;;
blank)
    hyprctl eval 'hl.monitor({ output = "HDMI-A-1", disabled = true })' >/dev/null
    hyprctl eval 'hl.monitor({ output = "DP-2", disabled = true })' >/dev/null
    ;;
unblank)
    hyprctl eval 'hl.monitor({ output = "HDMI-A-1", disabled = false, mode = "2560x1440@120.00Hz", position = "0x0", scale = 1, cm = "srgb" })' >/dev/null
    hyprctl eval 'hl.monitor({ output = "DP-2", disabled = false, mode = "1920x1080@239.76Hz", position = "-1920x240", scale = 1, cm = "srgb" })' >/dev/null
    ;;
*)
    echo "usage: ${0##*/} attach|detach|blank|unblank" >&2
    exit 1
    ;;
esac
