#!/bin/sh
# Succeeds while the session is locked, fails otherwise; for hypridle's
# condition_cmd (hypridle.conf).
#
# By logind's LockedHint, which the shell's lock screen sets as it locks and
# unlocks (pushLockedHint in LockEngine.qml), asked of the session the same
# way. If logind cannot be asked, this fails: the session counts as unlocked,
# and the screens go off the way they did before there was a locked case.
busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1/session/auto \
    org.freedesktop.login1.Session LockedHint 2>/dev/null | grep -qx 'b true'
