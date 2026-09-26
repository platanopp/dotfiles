#!/usr/bin/env bash
# Screens off and back on for hypridle.
#
#   idle-screens.sh off
#   idle-screens.sh on
#
# The two monitors are powered off in different ways, because they behave
# differently when they go dark:
#
#   Samsung Odyssey, DP-2 -- DPMS through wlopm. It keeps its DisplayPort
#   link while asleep (zero disconnects in every test), so Hyprland simply
#   stops sending it frames and starts again.
#
#   Xiaomi, HDMI-A-1 -- told to switch itself off over DDC/CI (VCP D6 = 05)
#   while Hyprland keeps drawing to it. It drops its HDMI link whenever its
#   panel goes off, however that happens. Put to sleep with DPMS, the link came
#   back while Hyprland was also waking the output, and the DRM state stuck on
#   a pending page flip: once, neither panel came back and the machine had to
#   be switched off at the button. Switched off over DDC, Hyprland never
#   powers the output down -- the connector goes and comes back, and it copes:
#   five cycles in a row on 2026-09-26, all back on the first DDC write, all
#   drawing again. The monitor does not answer DDC reads while off, but it
#   still obeys the write that switches it back on.
#
# XIAOMI_MODE picks how the Xiaomi goes dark:
#
#   ddc-off  really off, as above (the default)
#   cover    never off: covered in black by the shell (BlankOverlay.qml) with
#            its backlight at 0 over DDC. The monitor stays awake behind the
#            cover, so its link never drops. The fallback if ddc-off ever
#            comes back frozen.
set -u
export LC_ALL=C

XIAOMI_MODE=ddc-off

POWER_OFF=(DP-2)
XIAOMI_OUTPUT=HDMI-A-1
# By manufacturer, not by i2c bus number, which can change between boots.
DDC_XIAOMI=(--mfg XMI)

# cover mode: how long the Samsung takes to show a picture after being told to
# power on, so the cover lifts when it does rather than before.
WAKE_DELAY=1.0

state="${XDG_RUNTIME_DIR:-/tmp}/idle-screens"
brightness_file="$state-brightness"
# Every DDC call takes this lock. Moving the mouse just as the screens go off
# would otherwise send "on" while "off" is still in flight, and whichever
# arrives last wins -- a monitor left dark.
ddc_lock="$state-ddc.lock"

power() {
    local args=()
    for o in "${POWER_OFF[@]}"; do args+=("--$1" "$o"); done
    [ ${#args[@]} -gt 0 ] && wlopm "${args[@]}"
}

ddc() {
    ( flock 9; ddcutil "${DDC_XIAOMI[@]}" "$@" ) 9>"$ddc_lock"
}

xiaomi_off() {
    ddc setvcp D6 05 --noverify >/dev/null 2>&1
}

xiaomi_on() {
    # The first write has always been enough, but the monitor is waking from
    # off and a missed write here means a dark screen until someone finds its
    # button -- so it is checked, and sent again if it did not take.
    for _ in 1 2 3 4 5; do
        ddc setvcp D6 01 --noverify >/dev/null 2>&1
        sleep 1.5
        ddc getvcp D6 --terse 2>/dev/null | grep -q 'x01' && return 0
    done
    return 1
}

dim() {
    local cur
    cur=$(ddc getvcp 10 --terse 2>/dev/null | awk '{print $4}')
    [ -n "$cur" ] && [ "$cur" -gt 0 ] && echo "$cur" >"$brightness_file"
    ddc setvcp 10 0 --noverify >/dev/null 2>&1
}

undim() {
    local want
    want=$(cat "$brightness_file" 2>/dev/null)
    [ -n "$want" ] && ddc setvcp 10 "$want" --noverify >/dev/null 2>&1
}

case "${1:-}:$XIAOMI_MODE" in
    off:ddc-off)
        power off
        xiaomi_off
        ;;
    on:ddc-off)
        # Both at once: the Samsung's DPMS and the Xiaomi's DDC write go out
        # together, so neither waits on the other to start waking.
        xiaomi_on &
        power on
        wait
        ;;
    off:cover)
        qs ipc call screens blank "$XIAOMI_OUTPUT"
        power off
        dim
        ;;
    on:cover)
        power on
        undim &
        sleep "$WAKE_DELAY"
        wait
        qs ipc call screens unblank
        ;;
    *)
        echo "usage: $0 off|on   (XIAOMI_MODE=ddc-off|cover)" >&2
        exit 2
        ;;
esac
