#!/bin/bash
export LC_ALL=C
bluetoothctl --timeout 4 scan on >/dev/null 2>&1
paired=$(bluetoothctl devices Paired | awk '{print $2}')
connected=$(bluetoothctl devices Connected | awk '{print $2}')
bluetoothctl devices | while read -r _ mac name; do
    p="no"
    c="no"
    echo "$paired" | grep -q "^$mac$" && p="yes"
    echo "$connected" | grep -q "^$mac$" && c="yes"
    echo "$mac|$p|$c|$name"
done
