#!/usr/bin/env python3
"""Screens-off and lock timing, for the Settings window's Power & idle page.

The source of truth stays where it was: the two timeouts in hypridle.conf and
XIAOMI_MODE in idle-screens.sh. This only reads them and rewrites the numbers
in place, so the files keep their comments and can still be edited by hand.

  get                      JSON {screensOff, lock, xiaomiMode}, seconds
  set-screens-off SECONDS  the listener that runs idle-screens.sh
  set-lock SECONDS         the listener that runs loginctl lock-session
  set-xiaomi-mode MODE     ddc-off | cover

A timeout change restarts hypridle, which only reads its config at start; its
output goes to the same log the Hyprland config sends it to.
"""

import json
import os
import re
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config/hypr/hypridle.conf")
SCRIPT = os.path.join(HOME, ".config/hypr/scripts/idle-screens.sh")
LOG = os.path.join(HOME, ".local/state/hypridle.log")

# One listener block: "listener {" up to the brace that closes it. The
# comments between blocks are outside these matches and survive untouched.
BLOCK = re.compile(r"^listener\s*\{.*?^\}", re.S | re.M)
TIMEOUT = re.compile(r"^(\s*timeout\s*=\s*)(\d+)", re.M)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    # Written beside and renamed over, so a crash halfway never leaves a
    # truncated config -- and given the original's mode first: a fresh file
    # comes out 644, and idle-screens.sh is run directly by hypridle, so
    # losing its executable bit silently stops the screens ever going off.
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)


def find(text, marker):
    """The listener whose on-timeout mentions `marker`."""
    for m in BLOCK.finditer(text):
        if marker in m.group(0):
            return m
    return None


def timeout_of(text, marker):
    m = find(text, marker)
    if not m:
        return None
    t = TIMEOUT.search(m.group(0))
    return int(t.group(2)) if t else None


def set_timeout(marker, seconds):
    text = read(CONF)
    m = find(text, marker)
    if not m:
        sys.exit(f"no listener running {marker!r} in {CONF}")
    block = TIMEOUT.sub(lambda t: t.group(1) + str(int(seconds)), m.group(0), count=1)
    write(CONF, text[:m.start()] + block + text[m.end():])
    restart_hypridle()


def restart_hypridle():
    subprocess.run(["pkill", "-x", "hypridle"], capture_output=True)
    for _ in range(20):
        if subprocess.run(["pgrep", "-x", "hypridle"], capture_output=True).returncode != 0:
            break
        time.sleep(0.05)
    # Through Hyprland rather than spawned from here, so it belongs to the
    # compositor's session the same way the one started at login does -- and
    # does not die with whatever process asked for the restart.
    subprocess.run(
        ["hyprctl", "eval",
         'hl.dispatch(hl.dsp.exec_cmd("hypridle > $HOME/.local/state/hypridle.log 2>&1"))'],
        capture_output=True,
    )


def xiaomi_mode():
    m = re.search(r"^XIAOMI_MODE=(\S+)", read(SCRIPT), re.M)
    return m.group(1) if m else "ddc-off"


def set_xiaomi_mode(mode):
    if mode not in ("ddc-off", "cover"):
        sys.exit("mode must be ddc-off or cover")
    text = read(SCRIPT)
    text, n = re.subn(r"^XIAOMI_MODE=\S+", "XIAOMI_MODE=" + mode, text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"no XIAOMI_MODE line in {SCRIPT}")
    write(SCRIPT, text)
    # The script is read afresh every time hypridle runs it: nothing to restart.


def snapshot():
    text = read(CONF)
    return {
        "screensOff": timeout_of(text, "idle-screens.sh"),
        "lock": timeout_of(text, "lock-session"),
        "xiaomiMode": xiaomi_mode(),
    }


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "get"
    if cmd == "set-screens-off" and len(a) == 2:
        set_timeout("idle-screens.sh", int(a[1]))
    elif cmd == "set-lock" and len(a) == 2:
        set_timeout("lock-session", int(a[1]))
    elif cmd == "set-xiaomi-mode" and len(a) == 2:
        set_xiaomi_mode(a[1])
    elif cmd != "get":
        sys.exit(__doc__)
    print(json.dumps(snapshot()))


if __name__ == "__main__":
    main()
