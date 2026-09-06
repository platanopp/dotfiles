#!/usr/bin/env bash
# One lock cycle, narrated on stdout so the shell can animate around it.
#
# The lock surface belongs to veila and is put up by the compositor through
# ext-session-lock, above every layer this shell can draw on -- so quickshell
# can see neither edge of it for itself. This prints the two moments it needs:
#
#   locked     the curtain is up and actually holding the screen
#   unlocked   it has let go and the desktop is visible again
#   failed     the lock never came up; take the fade back down
#
# Exits with the cycle. Read by AppState.lockSession(); see lockProc there.
set -uo pipefail

emit() { printf '%s\n' "$1"; }

# Our own session only. Another seat unlocking on the same machine is not this
# shell's cue, and the object path is what tells them apart. Without it the
# monitor still works, just unfiltered.
session="$(veila status 2>/dev/null | sed -n 's/^session=//p')"

# Started before the lock rather than after it: a lock dismissed faster than
# this script gets back to listening would otherwise never report its unlock.
#
# stdbuf because gdbus prints through C stdio, which block-buffers onto a
# pipe -- the signal would sit in a 4K buffer until something else pushed it
# out, which is exactly the delay this is here to avoid.
hint_fd=""
if command -v gdbus >/dev/null 2>&1; then
    if [ -n "$session" ]; then
        coproc HINT { exec stdbuf -oL gdbus monitor --system \
            --dest org.freedesktop.login1 --object-path "$session" 2>/dev/null; }
    else
        coproc HINT { exec stdbuf -oL gdbus monitor --system \
            --dest org.freedesktop.login1 2>/dev/null; }
    fi
    hint_fd="${HINT[0]}"
fi

if ! veila lock --wait-ready >/dev/null 2>&1; then
    emit failed
    exit 1
fi
emit locked

# veilad flips logind's LockedHint on both sides of the lock and it arrives as
# a signal, so the fade out starts on the frame the curtain leaves instead of
# a poll later. Two backstops sit under it, because a late fade out means the
# desktop comes back from under a black screen that has no reason to be there:
#
#   * the curtain's own pid, tested through /proc. `[` is a shell builtin, so
#     this costs nothing to check on every tick.
#   * `veila status`, the authority, asked every couple of seconds for the
#     case where neither of the other two is available.
curtain="$(pgrep -x veila-curtain 2>/dev/null | head -n1)"
probe_at=0

while :; do
    if [ -n "$hint_fd" ]; then
        if read -r -t 0.25 -u "$hint_fd" line; then
            case $line in
                *LockedHint*false*) break ;;
            esac
            continue
        elif [ $? -le 128 ]; then
            # Not a timeout: the monitor has gone. Backstops carry it alone.
            hint_fd=""
        fi
    else
        sleep 0.25
    fi

    [ -n "$curtain" ] && [ ! -d "/proc/$curtain" ] && break

    if [ "$SECONDS" -ge "$probe_at" ]; then
        probe_at=$(( SECONDS + 2 ))
        veila status 2>/dev/null | grep -qx 'active_lock=true' || break
    fi
done

emit unlocked
