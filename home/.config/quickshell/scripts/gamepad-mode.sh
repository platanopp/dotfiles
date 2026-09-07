#!/usr/bin/env bash
# Runs gamepad_mode.py for the length of a stream.
#
# Called from global_prep_cmd in sunshine.conf. Sunshine waits for `do` to
# return before the stream starts, so `start` must not block -- it launches the
# mapper detached and leaves. `stop` kills it again when the client goes away.
#
# The mapper waits for the pad rather than looking once: Sunshine creates the
# virtual controller with the stream, a moment after these prep commands run.
set -uo pipefail

MAPPER="$HOME/.config/quickshell/gamepad_mode.py"
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/gamepad-mode.pid"
LOG="${XDG_RUNTIME_DIR:-/tmp}/gamepad-mode.log"

notify() {
    notify-send -a "Modo mando" -i input-gaming "$1" || true
}

running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

case "${1:-}" in
start)
    if running; then
        echo "already running as $(cat "$PIDFILE")"
        exit 0
    fi
    # setsid so it outlives the prep command's own process group, which
    # Sunshine reaps as soon as `do` returns.
    setsid python3 "$MAPPER" >"$LOG" 2>&1 &
    echo $! >"$PIDFILE"
    notify "Modo mando disponible"
    ;;
stop)
    if running; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
    fi
    rm -f "$PIDFILE"
    notify "Modo mando apagado"
    ;;
status)
    running && echo "running as $(cat "$PIDFILE")" || echo "not running"
    ;;
*)
    echo "usage: ${0##*/} start|stop|status" >&2
    exit 1
    ;;
esac
