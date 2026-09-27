#!/bin/bash
# The bar's network line: "SSID<TAB>SIGNAL<TAB>ETH". SSID empty and SIGNAL -1
# when not on Wi-Fi; ETH 1 when a wired connection is up.
export LC_ALL=C
ssid="" signal=-1
# -e no: an SSID with a colon in it stays whole; it is everything after the
# first two fields.
line=$(nmcli -t -e no -f active,signal,ssid dev wifi 2>/dev/null | grep -m1 '^yes:')
if [ -n "$line" ]; then
    rest=${line#yes:}
    signal=${rest%%:*}
    ssid=${rest#*:}
fi
eth=0
nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q '^ethernet:connected$' && eth=1
printf '%s\t%s\t%s\n' "$ssid" "$signal" "$eth"
