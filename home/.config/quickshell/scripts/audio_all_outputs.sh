#!/usr/bin/env bash
# Sound out of every output at once (Settings -> Sound -> All outputs).
#
# audio_all_outputs.sh on | off | status
#
# PipeWire's module-combine-sink with no output list feeds every device, including ones
# plugged in later. It lives only as long as PipeWire, so the shell reloads it
# (services/Audio.qml); nothing is written to PipeWire's config. "on" makes it the default and
# remembers the one it replaced; "off" goes back.
set -u

NAME=all_outputs
PREVIOUS="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/audio-all-outputs-previous"

module() {
    pactl list short modules | awk -v arg="sink_name=$NAME" \
        '$2 == "module-combine-sink" && index($0, arg) { print $1; exit }'
}

case "${1:-status}" in
on)
    if [ -z "$(module)" ]; then
        current=$(pactl get-default-sink)
        if [ "$current" != "$NAME" ]; then
            mkdir -p "$(dirname "$PREVIOUS")"
            printf '%s\n' "$current" > "$PREVIOUS"
        fi
        pactl load-module module-combine-sink sink_name=$NAME \
            'sink_properties=device.description="All outputs"' > /dev/null
    fi
    pactl set-default-sink $NAME
    ;;
off)
    # Back to the output it replaced, before the combined one goes, so that
    # what is playing moves there rather than to whatever PipeWire picks.
    if [ "$(pactl get-default-sink)" = "$NAME" ] && [ -s "$PREVIOUS" ]; then
        pactl set-default-sink "$(cat "$PREVIOUS")"
    fi
    m=$(module)
    if [ -n "$m" ]; then
        pactl unload-module "$m"
    fi
    ;;
status)
    [ -n "$(module)" ] && echo on || echo off
    ;;
esac
