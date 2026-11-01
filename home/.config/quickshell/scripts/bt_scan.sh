#!/bin/bash
# Bluetooth devices for the bar's panel: "MAC|PAIRED|CONNECTED|NAME|ICON". Scans four seconds first
# when on, unless called with "quick"; unnamed devices (shown as dashed addresses) are left out
# unless paired.
export LC_ALL=C
powered=$(bluetoothctl show | awk '/Powered:/{print $2; exit}')
[ "$powered" = "yes" ] && [ "$1" != "quick" ] && bluetoothctl --timeout 4 scan on >/dev/null 2>&1
paired=$(bluetoothctl devices Paired | awk '{print $2}')
connected=$(bluetoothctl devices Connected | awk '{print $2}')
bluetoothctl devices | while read -r _ mac name; do
    p="no"
    c="no"
    echo "$paired" | grep -qx "$mac" && p="yes"
    echo "$connected" | grep -qx "$mac" && c="yes"
    if [ "$p" = "no" ] && [ "${name//-/:}" = "$mac" ]; then
        continue
    fi
    icon=$(bluetoothctl info "$mac" | awk '/Icon:/{print $2; exit}')
    echo "$mac|$p|$c|$name|$icon"
done
