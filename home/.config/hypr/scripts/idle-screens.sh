#!/usr/bin/env bash
# Screens off and back on for hypridle.
#
#   idle-screens.sh off
#   idle-screens.sh on
#
# Monitors are powered off in two different ways, because they behave
# differently when they go dark (which ones are attached is asked of
# Hyprland on each run, see POWER_OFF below):
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

# Which screens there are, asked of Hyprland each time rather than written
# down: an unplugged monitor is simply not in the list, and any new one is put
# to sleep like the Samsung. The Xiaomi is recognised by its make, not by the
# connector it happens to be on, and is left out of POWER_OFF for the
# treatment below; with no Xiaomi attached, that part is skipped.
#
# Switched off over DDC, the Xiaomi drops its link and leaves this list, so
# "on" cannot find it there -- it went unwoken until 2026-10-18, a dark side
# screen until someone pressed its button. "off" leaves a mark instead
# ($xiaomi_off_mark, below), and "on" wakes it by that.
POWER_OFF=()
XIAOMI_OUTPUT=""
while IFS=$'\t' read -r name make; do
    [ -n "$name" ] || continue
    if [[ "$make" == *Xiaomi* ]]; then XIAOMI_OUTPUT=$name
    else POWER_OFF+=("$name"); fi
done < <(hyprctl -j monitors 2>/dev/null | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    print(m["name"] + "\t" + (m.get("make") or ""))
' 2>/dev/null)
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
# Present while the Xiaomi is switched off by "off" (ddc-off mode).
xiaomi_off_mark="$state-xiaomi-off"

power() {
    local args=()
    for o in "${POWER_OFF[@]}"; do args+=("--$1" "$o"); done
    [ ${#args[@]} -gt 0 ] && wlopm "${args[@]}"
}

ddc() {
    ( flock 9; ddcutil "${DDC_XIAOMI[@]}" "$@" ) 9>"$ddc_lock"
}

# Power goes over DDC by ddc-power.py, which writes the VESA message to the
# monitor's I2C bus itself: ddcutil, asked to wake a monitor that is off,
# spent 4.4 s identifying it before sending anything, and the Xiaomi took
# 7.3 s to come back; this way, 2.5 s -- the monitor's own start-up and HDMI
# link. ddcutil stays as the fallback. The bus is looked up while the monitor
# is still attached and kept in the mark, with the connector whose link "on"
# waits for.
ddc_power() {
    ( flock 9; python3 "$(dirname "$0")/ddc-power.py" "$@" ) 9>"$ddc_lock"
}

xiaomi_off() {
    [ -n "$XIAOMI_OUTPUT" ] || return 0
    local bus
    bus=$(python3 "$(dirname "$0")/ddc-power.py" find 2>/dev/null)
    echo "${bus:-} $XIAOMI_OUTPUT" >"$xiaomi_off_mark"
    if [ -n "$bus" ] && ddc_power "$bus" off 2>/dev/null; then
        return 0
    fi
    ddc setvcp D6 05 --noverify >/dev/null 2>&1
}

xiaomi_on() {
    # By the mark, not by XIAOMI_OUTPUT: switched off, it is not attached.
    [ -e "$xiaomi_off_mark" ] || return 0
    local bus connector
    read -r bus connector <"$xiaomi_off_mark"
    # Sent until the link is back (up to 12 s), see ddc-power.py.
    if [ -n "$bus" ] && ddc_power "$bus" on "$connector" 2>/dev/null; then
        rm -f "$xiaomi_off_mark"
        return 0
    fi
    # The fallback. A missed write here means a dark screen until someone
    # finds its button -- so it is checked, and sent again if it did not
    # take. Should none take, the mark stays and the next wake tries again.
    for _ in 1 2 3 4 5; do
        ddc setvcp D6 01 --noverify >/dev/null 2>&1
        sleep 1.5
        if ddc getvcp D6 --terse 2>/dev/null | grep -q 'x01'; then
            rm -f "$xiaomi_off_mark"
            return 0
        fi
    done
    return 1
}

dim() {
    [ -n "$XIAOMI_OUTPUT" ] || return 0
    local cur
    cur=$(ddc getvcp 10 --terse 2>/dev/null | awk '{print $4}')
    [ -n "$cur" ] && [ "$cur" -gt 0 ] && echo "$cur" >"$brightness_file"
    ddc setvcp 10 0 --noverify >/dev/null 2>&1
}

undim() {
    [ -n "$XIAOMI_OUTPUT" ] || return 0
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
        [ -n "$XIAOMI_OUTPUT" ] && qs ipc call screens blank "$XIAOMI_OUTPUT"
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
