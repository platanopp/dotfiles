#!/usr/bin/env python3
"""Power profiles for the bar: list them, apply one, and remember the choice.

power-profiles-daemon is the Linux counterpart of Windows' power plans, with
one difference that matters here: **it remembers nothing**. Every boot comes up
on "balanced" regardless of what was set before. So `set` writes the name to
disk and `restore` applies it again when the shell starts; without that pair
the bar's button would forget itself on every reboot.

State lives under ~/.local/state rather than XDG_RUNTIME_DIR, which is a tmpfs
wiped on shutdown -- surviving the reboot is the entire point.

  list      JSON: the available profiles and which one is active
  set NAME  apply NAME and remember it
  restore   re-apply the last remembered one, if there is one
"""

import json
import os
import subprocess
import sys

STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "quickshell", "power-profile",
)

# Nerd Font glyphs, fastest to slowest.
ICONS = {
    "performance": "\U000f03c5",   # speedometer
    "balanced":    "\U000f0fc5",   # speedometer-medium
    "power-saver": "\U000f0fc6",   # speedometer-slow
}
LABELS = {
    "performance": "Performance",
    "balanced":    "Balanced",
    "power-saver": "Power saver",
}


def ppctl(*args):
    return subprocess.run(["powerprofilesctl", *args],
                          capture_output=True, text=True, timeout=5)


def listing():
    """Names sit at the left margin and end in ':'; the active one carries '*'.

    Detail lines (CpuDriver, Degraded, ...) are indented four spaces, so
    requiring the name to start at column 0 or 2 is enough to tell them apart.
    """
    r = ppctl("list")
    profiles, active = [], ""
    for line in r.stdout.splitlines():
        if not line.strip().endswith(":"):
            continue
        if line.startswith("    "):           # a detail line, not a profile
            continue
        is_active = line.lstrip().startswith("*")
        name = line.replace("*", "").strip().rstrip(":")
        if not name:
            continue
        if is_active:
            active = name
        profiles.append({
            "name": name,
            "label": LABELS.get(name, name),
            "icon": ICONS.get(name, "\U000f0fc5"),
            "active": is_active,
        })
    return {"active": active, "profiles": profiles,
            "icon": ICONS.get(active, "\U000f0fc5"),
            "label": LABELS.get(active, active)}


def remember(name):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        f.write(name + "\n")
    os.replace(tmp, STATE)         # atomic: never leaves a half-written file


def apply(name):
    r = ppctl("set", name)
    if r.returncode != 0:
        print(r.stderr.strip(), file=sys.stderr)
        return False
    remember(name)
    return True


def restore():
    try:
        with open(STATE) as f:
            saved = f.read().strip()
    except OSError:
        return False               # nothing was ever chosen: leave the default
    if not saved:
        return False
    available = [p["name"] for p in listing()["profiles"]]
    if saved not in available:
        return False               # profile is gone (different driver, etc.)
    return ppctl("set", saved).returncode == 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        print(json.dumps(listing()))
    elif cmd == "set" and len(sys.argv) > 2:
        ok = apply(sys.argv[2])
        print(json.dumps(listing()))
        sys.exit(0 if ok else 1)
    elif cmd == "restore":
        restore()
        print(json.dumps(listing()))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
