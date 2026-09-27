#!/usr/bin/env python3
"""Hyprland options the Settings window may change, and nothing else.

The window never edits hyprland.lua. It keeps its own choices in
~/.config/hypr/gui-settings.json and writes them out as gui-settings.lua,
which hyprland.lua runs last so these values win. Only the options listed in
SPEC can be set, each checked against its type and range before anything is
written -- so what reaches Lua is always a number, a boolean or one of a few
known words, never text from outside.

Applying does not reload Hyprland. A reload would re-read every monitor rule
and throw away what the Displays and Colour pages set at runtime (modes,
positions, the gamma shader). Instead the new file is run live with
`hyprctl eval dofile(...)`: that is exactly what happens at the next start,
so if it fails now it would have failed then -- and on failure the previous
files are put back and run again, as if nothing had happened.

A change that applied is then committed to ~/dotfiles (sync.sh first), on
its own and only for .config/hypr. Never pushed.

  get               JSON {options: {key: {value, overridden, ...spec}}, git}
  set KEY VALUE     check, write, apply, commit
  reset KEY         drop the override and go back to what hyprland.lua says
"""

import json
import os
import subprocess
import sys
from datetime import datetime

HOME = os.path.expanduser("~")
HYPR = os.path.join(HOME, ".config/hypr")
STATE = os.path.join(HYPR, "gui-settings.json")
LUA = os.path.join(HYPR, "gui-settings.lua")


def backup_repo():
    """The repository Settings -> About backs up to (shell-settings.json's
    backupRepo), ~/dotfiles when unset -- the same one the About page uses."""
    try:
        with open(os.path.join(HOME, ".config/quickshell/shell-settings.json"), encoding="utf-8") as fh:
            path = json.load(fh).get("backupRepo") or "~/dotfiles"
    except (OSError, json.JSONDecodeError):
        path = "~/dotfiles"
    return os.path.expanduser(path)


DOTFILES = backup_repo()

# key: (hyprctl option, type, range or choices, label)
#
# Left out on purpose: the keyboard layout (a wrong one and the lock screen's
# password cannot be typed), monitors (the Displays page, with its
# keep-or-revert), binds, window rules and anything that runs a command.
SPEC = {
    "gaps_in":          ("general:gaps_in", "int", (0, 40), "Gap between windows"),
    "gaps_out":         ("general:gaps_out", "sides", (0, 80), "Gap to the screen edge"),
    # The top edge of the same option, on a slider of its own: the bar sits
    # in it, and the shell's pills follow it down (AppState.gapTop). Stored
    # inside gaps_out's entry -- one option, one line in gui-settings.lua.
    "gaps_top":         ("general:gaps_out", "top", (0, 80), "Gap to the top edge"),
    "border_size":      ("general:border_size", "int", (0, 8), "Border"),
    "layout":           ("general:layout", "enum", ("dwindle", "master", "scrolling"), "Layout"),
    "rounding":         ("decoration:rounding", "int", (0, 40), "Corner rounding"),
    "active_opacity":   ("decoration:active_opacity", "float", (0.4, 1.0), "Focused window opacity"),
    "inactive_opacity": ("decoration:inactive_opacity", "float", (0.2, 1.0), "Other windows opacity"),
    "dim_inactive":     ("decoration:dim_inactive", "bool", None, "Dim other windows"),
    "blur":             ("decoration:blur:enabled", "bool", None, "Blur"),
    "blur_size":        ("decoration:blur:size", "int", (1, 16), "Blur size"),
    "blur_passes":      ("decoration:blur:passes", "int", (1, 6), "Blur passes"),
    "shadow":           ("decoration:shadow:enabled", "bool", None, "Shadows"),
    "animations":       ("animations:enabled", "bool", None, "Animations"),
    "sensitivity":      ("input:sensitivity", "float", (-1.0, 1.0), "Pointer speed"),
    "accel_profile":    ("input:accel_profile", "enum", ("adaptive", "flat"), "Acceleration"),
    "follow_mouse":     ("input:follow_mouse", "enum", (1, 0), "Focus follows"),
    "repeat_delay":     ("input:repeat_delay", "int", (150, 1000), "Key repeat delay"),
    "repeat_rate":      ("input:repeat_rate", "int", (10, 80), "Key repeat rate"),
    "natural_scroll":   ("input:natural_scroll", "bool", None, "Natural scrolling"),
    "scroll_factor":    ("input:scroll_factor", "float", (0.3, 3.0), "Scroll speed"),
    "hide_cursor_typing": ("cursor:hide_on_key_press", "bool", None, "Hide cursor while typing"),
}


# ── Reading ──────────────────────────────────────────────────────────────

def run(*args, timeout=10):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def live(key):
    """The value Hyprland is actually using, whichever file set it."""
    option, kind = SPEC[key][0], SPEC[key][1]
    try:
        d = json.loads(run("hyprctl", "getoption", option, "-j").stdout)
    except (json.JSONDecodeError, subprocess.TimeoutExpired):
        return None
    if kind in ("int",):
        if "css" in d:           # gaps_in comes back as "15 15 15 15"
            return int(d["css"].split()[0])
        return d.get("int")
    if kind in ("sides", "top"):
        parts = [int(p) for p in d.get("css", "0").split()]
        parts = (parts * 4)[:4] if len(parts) == 1 else parts
        if len(parts) == 2:
            parts = [parts[0], parts[1], parts[0], parts[1]]
        elif len(parts) == 3:
            parts = [parts[0], parts[1], parts[2], parts[1]]
        return {"top": parts[0], "right": parts[1], "bottom": parts[2], "left": parts[3]}
    if kind == "float":
        return round(float(d.get("float", 0)), 3)
    if kind == "bool":
        return bool(d.get("bool", d.get("int", 0)))
    if kind == "enum":
        v = d.get("str", d.get("int"))
        if v == "[[EMPTY]]" or v == "":
            return SPEC[key][2][0]      # unset means Hyprland's default: the first choice
        return v
    return None


def load_state():
    try:
        with open(STATE, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return {}


# ── Checking ─────────────────────────────────────────────────────────────

def coerce(key, raw):
    """The value as its option's type, or an exception. Everything written to
    Lua goes through here."""
    kind, bounds = SPEC[key][1], SPEC[key][2]
    if kind in ("int", "sides", "top"):
        v = int(round(float(raw)))
        lo, hi = bounds
        if not lo <= v <= hi:
            raise ValueError(f"{key} must be between {lo} and {hi}")
        return v
    if kind == "float":
        v = round(float(raw), 3)
        lo, hi = bounds
        if not lo <= v <= hi:
            raise ValueError(f"{key} must be between {lo} and {hi}")
        return v
    if kind == "bool":
        if str(raw).lower() in ("1", "true", "yes", "on"):
            return True
        if str(raw).lower() in ("0", "false", "no", "off"):
            return False
        raise ValueError(f"{key} is on or off")
    if kind == "enum":
        for choice in bounds:
            if str(choice) == str(raw):
                return choice
        raise ValueError(f"{key} must be one of {', '.join(map(str, bounds))}")
    raise ValueError(f"unknown option {key}")


# ── Writing ──────────────────────────────────────────────────────────────

def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {lua_value(v[k])}" for k in ("top", "bottom", "left", "right")) + " }"
    # Only enum words reach here, and they come from SPEC, never from input.
    return '"' + str(v) + '"'


def render(state):
    """gui-settings.lua from the overrides: one hl.config call, nested the way
    the option names are."""
    tree = {}
    for key, entry in sorted(state.items()):
        if key not in SPEC:
            continue
        path = SPEC[key][0].split(":")
        node = tree
        for part in path[:-1]:
            node = node.setdefault(part, {})
        node[path[-1]] = entry["value"]

    def emit(node, depth):
        pad = "    " * depth
        out = []
        for name, v in node.items():
            if isinstance(v, dict) and not (set(v) <= {"top", "bottom", "left", "right"} and v):
                out.append(f"{pad}{name} = {{")
                out.extend(emit(v, depth + 1))
                out.append(f"{pad}}},")
            else:
                out.append(f"{pad}{name} = {lua_value(v)},")
        return out

    lines = [
        "-- Written by the shell's Settings window (Hyprland page), through",
        "-- ~/.config/quickshell/scripts/hypr_settings.py. Not meant to be",
        "-- edited by hand: the next change made in the window rewrites it from",
        "-- gui-settings.json. hyprland.lua runs this last, so these values win.",
        "",
    ]
    if tree:
        lines.append("hl.config({")
        lines.extend(emit(tree, 1))
        lines.append("})")
    return "\n".join(lines) + "\n"


def write_atomic(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def snapshot_files():
    saved = {}
    for p in (STATE, LUA):
        try:
            with open(p, encoding="utf-8") as fh:
                saved[p] = fh.read()
        except OSError:
            saved[p] = None
    return saved


def restore_files(saved):
    for p, text in saved.items():
        if text is None:
            try:
                os.unlink(p)
            except OSError:
                pass
        else:
            write_atomic(p, text)


def run_live(path):
    """Run a Lua file inside Hyprland; the error text, or "" when it worked."""
    r = run("hyprctl", "eval", f'dofile("{path}")')
    out = (r.stdout + r.stderr).strip()
    return "" if out == "ok" else (out or f"hyprctl exited {r.returncode}")


def apply_live(key, value):
    """Push one value into the running compositor, for a reset -- where the
    file no longer mentions the option and running it would change nothing."""
    path = SPEC[key][0].split(":")
    inner = f"{path[-1]} = {lua_value(value)}"
    for part in reversed(path[:-1]):
        inner = f"{part} = {{ {inner} }}"
    r = run("hyprctl", "eval", f"hl.config({{ {inner} }})")
    out = (r.stdout + r.stderr).strip()
    return "" if out == "ok" else out


# ── Committing ───────────────────────────────────────────────────────────

def commit(message):
    """sync.sh, then a commit of .config/hypr alone. Anything else pending in
    the repo is left as it was, unstaged, for its owner to commit."""
    if not os.path.isdir(os.path.join(DOTFILES, ".git")):
        return {"committed": False, "reason": "no ~/dotfiles repository"}
    sync = os.path.join(DOTFILES, "sync.sh")
    if os.access(sync, os.X_OK):
        run(sync, timeout=120)
    run("git", "-C", DOTFILES, "add", "home/.config/hypr")
    if run("git", "-C", DOTFILES, "diff", "--cached", "--quiet").returncode == 0:
        return {"committed": False, "reason": "nothing changed"}
    # A change made by pressing a control is the user's own commit.
    body = message + "\n\nMade in the Settings window; applied live and checked.\n"
    # The pathspec keeps the commit to .config/hypr even if something else
    # was already staged by hand.
    p = subprocess.run(["git", "-C", DOTFILES, "commit", "-q", "-F", "-", "--", "home/.config/hypr"],
                       input=body, capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        return {"committed": False, "reason": p.stderr.strip()}
    return {"committed": True, "hash": run("git", "-C", DOTFILES, "rev-parse", "--short", "HEAD").stdout.strip()}


def git_status():
    if not os.path.isdir(os.path.join(DOTFILES, ".git")):
        return {"repo": False}
    log = run("git", "-C", DOTFILES, "log", "-1", "--format=%h%x09%cr%x09%s").stdout.strip().split("\t")
    ahead = run("git", "-C", DOTFILES, "rev-list", "--count", "@{u}..HEAD").stdout.strip()
    return {"repo": True, "hash": log[0] if log else "", "when": log[1] if len(log) > 1 else "",
            "subject": log[2] if len(log) > 2 else "", "unpushed": int(ahead) if ahead.isdigit() else None}


# ── Commands ─────────────────────────────────────────────────────────────

def describe(v):
    if isinstance(v, bool):
        return "on" if v else "off"
    if isinstance(v, dict):
        return str(v.get("left"))
    return str(v)


def cmd_get():
    state = load_state()
    out = {}
    for key, (option, kind, bounds, label) in SPEC.items():
        v = live(key)
        if kind == "sides" and isinstance(v, dict):
            v = v["left"]
        elif kind == "top" and isinstance(v, dict):
            v = v["top"]
        owner = "gaps_out" if kind == "top" else key
        overridden = owner in state
        if kind in ("sides", "top") and overridden:
            # Each slider is overridden only on its own edges.
            val, base = state[owner]["value"], state[owner].get("base") or {}
            edges = ("top",) if kind == "top" else ("bottom", "left", "right")
            overridden = isinstance(val, dict) and any(val.get(e) != base.get(e) for e in edges)
        out[key] = {"value": v, "overridden": overridden, "type": kind, "label": label,
                    "bounds": list(bounds) if bounds else None}
    print(json.dumps({"options": out, "git": git_status()}))


def cmd_set(key, raw):
    if key not in SPEC:
        sys.exit(f"not an option this window may change: {key}")
    value = coerce(key, raw)
    kind = SPEC[key][1]
    before = live(key)
    if kind == "top":
        return set_top(value, before)

    state = load_state()
    # Letting go of a slider where it already was is not a change: nothing
    # to write, and no "border 0 -> 0" commit.
    same = before == value or (isinstance(before, dict) and before.get("left") == value)
    if same and key not in state:
        print(json.dumps({"ok": True, "commit": {"committed": False, "reason": "unchanged"}}))
        return
    base = state.get(key, {}).get("base", before)
    if kind == "sides":
        # Only the sides and the bottom: the top edge is sized for the bar, and
        # the shell parks its pills off it.
        top = before["top"] if isinstance(before, dict) else value
        stored = {"top": top, "bottom": value, "left": value, "right": value}
    else:
        stored = value
    state[key] = {"value": stored, "base": base}

    saved = snapshot_files()
    write_atomic(STATE, json.dumps(state, indent=2) + "\n")
    write_atomic(LUA, render(state))
    err = run_live(LUA)
    if err:
        # Files back, and the running value too: part of the call may have
        # landed before the error did.
        restore_files(saved)
        if os.path.exists(LUA):
            run_live(LUA)
        if before is not None:
            apply_live(key, before)
        print(json.dumps({"ok": False, "error": err}))
        sys.exit(1)

    label = SPEC[key][3]
    msg = f"settings(hyprland): {label.lower()} {describe(before)} -> {describe(stored)}"
    result = {"ok": True, "commit": commit(msg)}
    print(json.dumps(result))


def set_top(value, before):
    """gaps_top: the top edge of gaps_out, the other three kept as they are."""
    if not isinstance(before, dict):
        before = {e: before or 0 for e in ("top", "right", "bottom", "left")}
    state = load_state()
    if before["top"] == value:
        print(json.dumps({"ok": True, "commit": {"committed": False, "reason": "unchanged"}}))
        return
    base = state.get("gaps_out", {}).get("base", before)
    stored = {"top": value, "bottom": before["bottom"], "left": before["left"], "right": before["right"]}
    state["gaps_out"] = {"value": stored, "base": base}
    apply_state(state, "gaps_out", before,
                f"settings(hyprland): gap to the top edge {before['top']} -> {value}")


def apply_state(state, key, before, msg):
    """Write, run live, roll back on failure, commit on success."""
    saved = snapshot_files()
    write_atomic(STATE, json.dumps(state, indent=2) + "\n")
    write_atomic(LUA, render(state))
    err = run_live(LUA)
    if err:
        restore_files(saved)
        if os.path.exists(LUA):
            run_live(LUA)
        if before is not None:
            apply_live(key, before)
        print(json.dumps({"ok": False, "error": err}))
        sys.exit(1)
    print(json.dumps({"ok": True, "commit": commit(msg)}))


def reset_edges(state, key):
    """gaps_out and gaps_top share one entry: resetting one puts back only
    its own edges, and drops the entry once nothing differs from the base."""
    entry = state.get("gaps_out")
    if not entry:
        return None
    base, val = entry.get("base") or {}, dict(entry["value"])
    edges = ("top",) if key == "gaps_top" else ("bottom", "left", "right")
    for e in edges:
        val[e] = base.get(e, val[e])
    before = live("gaps_out")
    if all(val.get(e) == base.get(e) for e in ("top", "bottom", "left", "right")):
        state.pop("gaps_out")
        return before, base
    state["gaps_out"] = {"value": val, "base": base}
    return before, val


def cmd_reset(key):
    state = load_state()
    if key in ("gaps_out", "gaps_top"):
        r = reset_edges(state, key)
        if r is None:
            print(json.dumps({"ok": True, "commit": {"committed": False, "reason": "not overridden"}}))
            return
        before, target = r
        saved = snapshot_files()
        write_atomic(STATE, json.dumps(state, indent=2) + "\n")
        write_atomic(LUA, render(state))
        err = run_live(LUA) or apply_live("gaps_out", target)
        if err:
            restore_files(saved)
            run_live(LUA)
            print(json.dumps({"ok": False, "error": err}))
            sys.exit(1)
        msg = f"settings(hyprland): {SPEC[key][3].lower()} back to the config's value"
        print(json.dumps({"ok": True, "commit": commit(msg)}))
        return
    if key not in state:
        print(json.dumps({"ok": True, "commit": {"committed": False, "reason": "not overridden"}}))
        return
    base = state.pop(key).get("base")
    saved = snapshot_files()
    write_atomic(STATE, json.dumps(state, indent=2) + "\n")
    write_atomic(LUA, render(state))
    err = run_live(LUA) or (apply_live(key, base) if base is not None else "")
    if err:
        restore_files(saved)
        run_live(LUA)
        print(json.dumps({"ok": False, "error": err}))
        sys.exit(1)
    msg = f"settings(hyprland): {SPEC[key][3].lower()} back to the config's value"
    print(json.dumps({"ok": True, "commit": commit(msg)}))


def main():
    a = sys.argv[1:]
    try:
        if not a or a[0] == "get":
            cmd_get()
        elif a[0] == "set" and len(a) == 3:
            cmd_set(a[1], a[2])
        elif a[0] == "reset" and len(a) == 2:
            cmd_reset(a[1])
        else:
            sys.exit(__doc__)
    except ValueError as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
