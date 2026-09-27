#!/bin/bash
# Bluetooth devices for the bar's panel: "MAC|PAIRED|CONNECTED|NAME|ICON".
# Scans for four seconds first when the adapter is on. Devices nearby that
# never gave a name (bluetoothctl shows their address, dashed, as the name)
# are left out unless they are paired: a list of addresses helps nobody.
export LC_ALL=C
powered=$(bluetoothctl show | awk '/Powered:/{print $2; exit}')
[ "$powered" = "yes" ] && bluetoothctl --timeout 4 scan on >/dev/null 2>&1
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
