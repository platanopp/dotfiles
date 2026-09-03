#!/usr/bin/env python3
"""Reports yazi's keybinds as JSON, for the shell's shortcut sheet.

Two sources, because either alone would mislead. The user's own
``keymap.toml`` is the short list of things they added, and it is the part
that changes; yazi's defaults are the other ninety per cent of what the
keyboard actually does, and they live compiled into the binary rather than
in any file on disk.

So the defaults are read back out of the binary's embedded config instead of
being copied into a table here -- a table would keep claiming `d` trashes a
file long after an upgrade decided otherwise. Only a curated set is shown,
and their labels are translated; anything unrecognised is left out rather
than padding the sheet with the whole manual.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tomllib

USER_KEYMAP = os.path.expanduser("~/.config/yazi/keymap.toml")

# `{ on = "d", run = "remove", desc = "Trash selected files" }` as it appears
# in the default config compiled into the yazi binary.
DEFAULT_RE = re.compile(
    r'\{\s*on\s*=\s*(?P<on>"(?:[^"\\]|\\.)*"|\[[^\]]*\])\s*,'
    r"\s*run\s*=\s*(?P<run>\"(?:[^\"\\]|\\.)*\"|\[[^\]]*\])\s*,"
    r'\s*desc\s*=\s*"(?P<desc>(?:[^"\\]|\\.)*)"'
)

# The defaults worth putting on a cheat sheet, keyed by the key sequence as
# it is written in the config, with the label to show for it. A default whose
# key is not here is skipped, and one that has disappeared from the binary is
# skipped too -- so this can only ever show fewer things than yazi does,
# never something yazi no longer supports.
CURATED = {
    "<Enter>": ("Open · extract archives", "Files"),
    "o": ("Open", "Files"),
    "O": ("Open with…", "Files"),
    "y": ("Copy", "Files"),
    "x": ("Cut", "Files"),
    "p": ("Paste", "Files"),
    "P": ("Paste, overwriting", "Files"),
    "d": ("Move to trash", "Files"),
    "D": ("Delete permanently", "Files"),
    "a": ("Create a file (or a folder with /)", "Files"),
    "A": ("Create several at once", "Files"),
    "r": ("Rename", "Files"),
    "-": ("Symlink", "Files"),
    "g t": ("Open the trash", "Getting around"),
    "g g": ("Go to the top", "Getting around"),
    "G": ("Go to the bottom", "Getting around"),
    "h": ("Parent folder", "Getting around"),
    "l": ("Enter the folder", "Getting around"),
    "H": ("Back", "Getting around"),
    "L": ("Forward", "Getting around"),
    "t t": ("New tab", "Getting around"),
    "<Space>": ("Select or deselect", "Selecting"),
    "v": ("Visual mode (selection)", "Selecting"),
    "<C-r>": ("Invert the selection", "Selecting"),
    ".": ("Show hidden files", "Looking around"),
    "f": ("Filter the folder", "Looking around"),
    "s": ("Search by name (fd)", "Looking around"),
    "S": ("Search by content (ripgrep)", "Looking around"),
    ",": ("Sort by…", "Looking around"),
    ";": ("Run a command", "Commands"),
    ":": ("Run a command and wait", "Commands"),
    "q": ("Quit", "Commands"),
}

USER_GROUP = "My own"

KEY_NAMES = {
    "<Enter>": "Enter",
    "<Space>": "Space",
    "<Esc>": "Esc",
    "<Tab>": "Tab",
    "<Backspace>": "Backspace",
}

MOD_NAMES = {"C": "Ctrl", "A": "Alt", "S": "Shift", "D": "Super"}


def pretty_key(token):
    """`<C-a>` -> `Ctrl + A`; a bare letter is left as typed."""
    if token in KEY_NAMES:
        return KEY_NAMES[token]
    combo = re.fullmatch(r"<([CASD])-(.+)>", token)
    if combo:
        mod = MOD_NAMES.get(combo.group(1), combo.group(1))
        key = combo.group(2)
        return f"{mod} + {key.upper() if len(key) == 1 else key}"
    if token.startswith("<") and token.endswith(">"):
        return token[1:-1]
    return token


def pretty_sequence(on):
    """A bind is one key or a sequence of them: `["g", "h"]` -> `g h`."""
    if isinstance(on, str):
        return pretty_key(on)
    return " ".join(pretty_key(part) for part in on)


def sequence_id(on):
    """The sequence as the config spells it, for matching against CURATED."""
    return on if isinstance(on, str) else " ".join(on)


def run_text(run):
    return run if isinstance(run, str) else " ; ".join(run)


def read_user_binds():
    try:
        with open(USER_KEYMAP, "rb") as f:
            data = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        return None, f"Could not read keymap.toml: {exc}"

    binds = []
    for section in ("mgr", "manager"):
        entries = data.get(section, {}).get("prepend_keymap", [])
        for entry in entries:
            on, run = entry.get("on"), entry.get("run")
            if on is None or run is None:
                continue
            binds.append({
                "keys": pretty_sequence(on),
                "action": entry.get("desc") or run_text(run),
                "command": None,
                "category": USER_GROUP,
            })
    return binds, None


def read_default_binds():
    """The curated defaults, as the installed yazi actually has them."""
    binary = shutil.which("yazi")
    if not binary:
        return []
    try:
        blob = subprocess.run(
            ["strings", binary], capture_output=True, timeout=20, text=True
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return []

    seen = set()
    binds = []
    for match in DEFAULT_RE.finditer(blob):
        raw_on = match.group("on")
        try:
            on = tomllib.loads(f"v = {raw_on}")["v"]
        except tomllib.TOMLDecodeError:
            continue
        key = sequence_id(on)
        if key not in CURATED or key in seen:
            continue
        seen.add(key)
        label, category = CURATED[key]
        binds.append({
            "keys": pretty_sequence(on),
            "action": label,
            "command": None,
            "category": category,
        })
    return binds


def group(binds, order):
    grouped = {}
    for bind in binds:
        grouped.setdefault(bind["category"], []).append(bind)
    return [
        {"name": name, "binds": grouped[name]}
        for name in order
        if grouped.get(name)
    ]


def main():
    user, error = read_user_binds()
    if error:
        json.dump({"error": error, "count": 0, "groups": []},
                  sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return

    defaults = read_default_binds()
    # A user bind wins: yazi applies prepend_keymap over its own defaults, so
    # showing both would list the same key twice saying different things.
    taken = {bind["keys"] for bind in user}
    defaults = [bind for bind in defaults if bind["keys"] not in taken]

    groups = (
        group(user, [USER_GROUP])
        + group(defaults, ["Files", "Getting around", "Selecting", "Looking around", "Commands"])
    )

    json.dump({
        "error": None,
        "count": len(user) + len(defaults),
        "custom": len(user),
        "groups": groups,
    }, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
