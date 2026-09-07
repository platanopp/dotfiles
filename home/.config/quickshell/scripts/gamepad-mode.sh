#!/usr/bin/env bash
# Front end to the gamepad mapper, for the control panel and for hands.
#
# The mapper itself is a user service now (gamepad-mode.service, next to this
# file) that runs for the whole session, so there is nothing here to launch or
# reap -- what is left is asking it to switch modes and asking which mode it is
# in.
#
#   toggle   flip between plain gamepad and desktop control  (== L3 + R3)
#   state    stopped | waiting | off | on, the same file the shell watches
#   start    bring the service up
#   stop     take it down
#   status   both of the above, for a terminal
#
# `toggle` goes over SIGUSR1 rather than through the state file, because the
# mapper owns the state: writing "on" from out here would say the mode changed
# without any of it actually changing.
set -uo pipefail

UNIT="gamepad-mode.service"
STATE="${XDG_RUNTIME_DIR:-/tmp}/gamepad-mode.state"

case "${1:-}" in
toggle)
    systemctl --user kill --signal=SIGUSR1 "$UNIT"
    ;;
state)
    # The mapper removes the file on its way out, so no file means no mapper.
    cat "$STATE" 2>/dev/null || echo stopped
    ;;
start)
    systemctl --user start "$UNIT"
    ;;
stop)
    systemctl --user stop "$UNIT"
    ;;
status)
    echo "service: $(systemctl --user is-active "$UNIT")"
    echo "mode:    $(cat "$STATE" 2>/dev/null || echo stopped)"
    ;;
*)
    echo "usage: ${0##*/} toggle|state|start|stop|status" >&2
    exit 1
    ;;
esac
