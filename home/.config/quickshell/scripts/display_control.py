#!/usr/bin/env python3
"""Display and colour control: modes, layout, vibrance, gamma, VRR.

This is the engine behind the display panel in the bar. It exists because the
three things it drives speak three different languages:

  * modes, position, scale, VRR -> hyprctl. And specifically `hyprctl eval`
    with a Lua call, because this config is Lua and `hyprctl keyword` refuses
    to work with non-legacy parsers.
  * saturation -> nvibrant, which is positional: one value per connector
    index, HDMI first then the DPs. Hyprland names outputs, nvibrant numbers
    them, so the two have to be matched up (see vibrance_map).
  * gamma and temperature -> hyprsunset, a daemon. Values are pushed to it
    over its own IPC; it has to be running or nothing happens.

Nothing here survives a reboot on its own -- Hyprland re-reads its config,
nvibrant resets with the driver, hyprsunset starts fresh -- so `set-*` writes
the choice to disk and `restore` plays it all back.

  list                            JSON: monitors, modes, colour state
  set-mode OUT WxH@R              resolution and refresh rate
  set-position OUT X Y            layout
  set-scale OUT S                 fractional scaling
  set-vrr 0|1|2                   off / on / fullscreen only
  set-vibrance OUT V              0-1023, 0 is neutral
  set-temperature K               1000-20000, 6000 is neutral
  set-brightness PCT              10-100, 100 is neutral
  focus-cursor-monitor            focus the monitor under the pointer
  restore                         re-apply everything saved
"""

import json
import os
import re
import subprocess
import sys

STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "quickshell", "display.json",
)

# gammastep's neutral temperature is 6500K, not 6000: at 6500 it leaves the
# ramp alone entirely.
NEUTRAL = {"temperature": 6000, "brightness": 100, "gamma": 1.0}

SHADER = os.path.expanduser("~/.config/hypr/shaders/gamma.frag")


# ── plumbing ─────────────────────────────────────────────────────────────

def run(*args, timeout=6):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def hypr_json(what):
    r = run("hyprctl", "-j", what)
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return []


def hypr_eval(lua):
    """hyprctl keyword is unusable with a Lua config; eval is the way in."""
    return run("hyprctl", "eval", lua).returncode == 0


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def save(data):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, STATE)          # atomic; never a half-written state file


def remember(section, key, value):
    d = load()
    d.setdefault(section, {})
    if key is None:
        d[section] = value
    else:
        d[section][key] = value
    save(d)


# ── monitors ─────────────────────────────────────────────────────────────

def parse_mode(text):
    """'2560x1440@120.00Hz' -> (2560, 1440, 120.00)"""
    m = re.match(r"(\d+)x(\d+)@([\d.]+)", text)
    return (int(m[1]), int(m[2]), float(m[3])) if m else None


def monitors():
    out = []
    for m in hypr_json("monitors"):
        modes = []
        seen = set()
        for t in m.get("availableModes", []):
            p = parse_mode(t)
            if not p or p in seen:
                continue
            seen.add(p)
            modes.append({"text": f"{p[0]}x{p[1]}@{p[2]:g}", "w": p[0], "h": p[1], "hz": p[2]})
        # highest refresh first, then widest -- the order people scan for
        modes.sort(key=lambda x: (-x["hz"], -x["w"]))
        out.append({
            "name": m["name"],
            "description": f"{m.get('make','')} {m.get('model','')}".strip(),
            "width": m["width"], "height": m["height"],
            "refresh": round(m["refreshRate"], 2),
            "x": m["x"], "y": m["y"],
            "scale": m.get("scale", 1),
            "vrr": m.get("vrr", False),
            "focused": m.get("focused", False),
            "modes": modes,
        })
    return out


def apply_monitor(name, *, mode=None, position=None, scale=None):
    """Hyprland wants the whole spec, so unspecified fields are read back."""
    cur = next((m for m in monitors() if m["name"] == name), None)
    if cur is None:
        return False
    mode = mode or f"{cur['width']}x{cur['height']}@{cur['refresh']:g}"
    position = position or f"{cur['x']}x{cur['y']}"
    scale = cur["scale"] if scale is None else scale
    ok = hypr_eval(
        f'hl.monitor({{ output = "{name}", disabled = false, '
        f'mode = "{mode}Hz", position = "{position}", scale = {scale} }})'
    )
    if ok:
        remember("monitors", name, {"mode": mode, "position": position, "scale": scale})
    return ok


# ── saturation ───────────────────────────────────────────────────────────

def vibrance_map():
    """Match Hyprland's output names to nvibrant's positional indices.

    nvibrant reports one line per connector -- 'Success' where a display is
    actually attached, 'None' where the port is empty. Those attached slots,
    in order, correspond to the connected outputs of the same kind. Reading
    the mapping instead of hardcoding it means it survives replugging.
    """
    r = run("nvibrant")
    slots = []
    for line in r.stdout.splitlines():
        m = re.search(r"\((\d+),\s*(HDMI|DP)\s*\).*?•\s*(Success|None)", line)
        if m:
            slots.append({"index": int(m[1]), "kind": m[2], "live": m[3] == "Success"})
    live = [s for s in slots if s["live"]]
    mapping, used = {}, set()
    for mon in monitors():
        kind = "HDMI" if mon["name"].upper().startswith("HDMI") else "DP"
        for s in live:
            if s["kind"] == kind and s["index"] not in used:
                mapping[mon["name"]] = s["index"]
                used.add(s["index"])
                break
    return mapping, (max((s["index"] for s in slots), default=6) + 1)


def apply_vibrance(values):
    """values: {output_name: 0..1023}. Every slot must be passed positionally."""
    mapping, count = vibrance_map()
    args = ["0"] * count
    for name, v in values.items():
        if name in mapping:
            args[mapping[name]] = str(int(v))
    ok = run("nvibrant", *args).returncode == 0
    if ok:
        remember("vibrance", None, {k: int(v) for k, v in values.items()})
    return ok


def current_vibrance():
    saved = load().get("vibrance", {})
    return {m["name"]: saved.get(m["name"], 0) for m in monitors()}


# ── gamma and temperature ────────────────────────────────────────────────

def sunset_socket():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    return f"/run/user/{os.getuid()}/hypr/{sig}/.hyprsunset.sock"


def sunset_reachable():
    """Running is not the same as listening: a dead hyprsunset leaves its
    socket file behind and the next one cannot bind to it. Probed by opening
    the socket, not by sending a command -- `hyprctl hyprsunset temperature`
    with no argument reports the value *and re-applies it*."""
    import socket
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sk:
            sk.settimeout(0.5)
            sk.connect(sunset_socket())
        return True
    except OSError:
        return False


def ensure_sunset():
    import time
    if sunset_reachable():
        return True
    run("pkill", "-x", "hyprsunset")
    time.sleep(0.4)
    try:
        os.unlink(sunset_socket())
    except OSError:
        pass
    subprocess.Popen(
        ["hyprsunset", "-t", str(NEUTRAL["temperature"]),
         "-g", str(NEUTRAL["brightness"]), "--gamma_max", "200"],
        start_new_session=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    for _ in range(40):
        if sunset_reachable():
            return True
        time.sleep(0.1)
    return False


def apply_gamma(value):
    """Gamma as a screen shader, because this GPU leaves no other route.

    The colour pipeline here exposes CTM but not GAMMA_LUT, and a 3x3 matrix
    is linear: it cannot express out = in^(1/g). So the exponent is compiled
    into a one-line fragment shader and Hyprland applies it per frame.

    The usual argument against a screen shader is that it blocks direct
    scanout. Not a cost here: render:direct_scanout is off anyway, so
    fullscreen games already go through composition.

    At exactly 1.0 the shader is unset rather than applied as a no-op, so
    neutral costs nothing at all.
    """
    value = max(0.4, min(2.5, float(value)))
    if abs(value - 1.0) < 0.005:
        hypr_eval('hl.config({ decoration = { screen_shader = "" } })')
        return True
    try:
        src = open(SHADER).read()
    except OSError:
        return False
    src = re.sub(r"const float GAMMA = [\d.]+;",
                 f"const float GAMMA = {value:.4f};", src)
    with open(SHADER, "w") as f:
        f.write(src)
    # Cleared first: assigning the path Hyprland already holds is a no-op, and
    # it would keep serving the old exponent.
    hypr_eval('hl.config({ decoration = { screen_shader = "" } })')
    return hypr_eval(f'hl.config({{ decoration = {{ screen_shader = "{SHADER}" }} }})')


def apply_colour(temperature=None, brightness=None):
    """Temperature and brightness through hyprsunset; gamma is not possible.

    This hardware exposes CTM -- a 3x3 colour matrix -- but not GAMMA_LUT.
    gammastep needs the LUT and reports "Zero outputs support gamma
    adjustment", so it does nothing at all here. hyprsunset uses the CTM and
    works.

    The catch is arithmetic: a 3x3 matrix is a linear map. Scaling channels
    gives temperature and brightness, but out = in^(1/g) is not linear and no
    matrix can express it. On this GPU there is no colour-pipeline route to a
    real gamma curve; the only one left is a compositor shader.
    """
    saved = load().get("colour", dict(NEUTRAL))
    if "brightness" not in saved:
        saved["brightness"] = saved.pop("gamma", NEUTRAL["brightness"])

    if temperature is not None:
        saved["temperature"] = max(1000, min(20000, int(temperature)))
    if brightness is not None:
        saved["brightness"] = max(20, min(200, int(brightness)))

    if not ensure_sunset():
        remember("colour", None, saved)
        return False
    if temperature is not None:
        run("hyprctl", "hyprsunset", "temperature", str(saved["temperature"]))
    if brightness is not None:
        run("hyprctl", "hyprsunset", "gamma", str(saved["brightness"]))

    remember("colour", None, saved)
    return True


def colour_active():
    return sunset_reachable()



def focus_cursor_monitor():
    """Focus whichever monitor the pointer is on.

    follow_mouse already does this on its own, but not while a layer surface
    holds the keyboard: the launcher's overlay keeps focus where it was, and a
    window spawned the instant it closes lands on the old monitor. Asking
    explicitly removes the race.

    `hyprctl dispatch focusmonitor NAME` is not usable -- this config is Lua,
    so hyprctl parses the argument as Lua and errors on the hyphen in a
    monitor name. eval with the dispatcher built in Lua is the way in.
    """
    r = run("hyprctl", "cursorpos")
    try:
        x, y = (int(p.strip()) for p in r.stdout.split(","))
    except (ValueError, IndexError):
        return None
    for m in monitors():
        if m["x"] <= x < m["x"] + m["width"] and m["y"] <= y < m["y"] + m["height"]:
            hypr_eval(f'hl.dispatch(hl.dsp.focus({{ monitor = "{m["name"]}" }}))')
            return m["name"]
    return None


# ── restore ──────────────────────────────────────────────────────────────

def restore():
    d = load()
    for name, spec in d.get("monitors", {}).items():
        apply_monitor(name, mode=spec.get("mode"), position=spec.get("position"),
                      scale=spec.get("scale"))
    if d.get("vibrance"):
        apply_vibrance(d["vibrance"])
    c = d.get("colour")
    if c:
        apply_colour(c.get("temperature"), c.get("brightness"))
        if c.get("gamma") is not None:
            apply_gamma(c["gamma"])


def snapshot():
    d = load()
    return {
        "monitors": monitors(),
        "vibrance": current_vibrance(),
        "colour": d.get("colour", dict(NEUTRAL)),
        "colour_active": colour_active(),
        "vrr": hypr_json("getoption misc:vrr").get("int", 0)
              if isinstance(hypr_json("getoption misc:vrr"), dict) else 0,
    }


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "list"
    if cmd == "list":
        print(json.dumps(snapshot()))
    elif cmd == "set-mode" and len(a) >= 3:
        apply_monitor(a[1], mode=a[2]); print(json.dumps(snapshot()))
    elif cmd == "set-position" and len(a) >= 4:
        apply_monitor(a[1], position=f"{a[2]}x{a[3]}"); print(json.dumps(snapshot()))
    elif cmd == "set-scale" and len(a) >= 3:
        apply_monitor(a[1], scale=float(a[2])); print(json.dumps(snapshot()))
    elif cmd == "set-vrr" and len(a) >= 2:
        hypr_eval(f'hl.config({{ misc = {{ vrr = {int(a[1])} }} }})')
        remember("vrr", None, int(a[1])); print(json.dumps(snapshot()))
    elif cmd == "set-vibrance" and len(a) >= 3:
        v = current_vibrance(); v[a[1]] = int(a[2])
        apply_vibrance(v); print(json.dumps(snapshot()))
    elif cmd == "set-temperature" and len(a) >= 2:
        apply_colour(temperature=int(a[1])); print(json.dumps(snapshot()))
    elif cmd == "set-gamma" and len(a) >= 2:
        g = round(float(a[1]), 3)
        apply_gamma(g)
        d = load(); d.setdefault("colour", dict(NEUTRAL))["gamma"] = g; save(d)
        print(json.dumps(snapshot()))
    elif cmd == "set-brightness" and len(a) >= 2:
        apply_colour(brightness=int(a[1])); print(json.dumps(snapshot()))
    elif cmd == "focus-cursor-monitor":
        print(focus_cursor_monitor() or "")
    elif cmd == "restore":
        restore(); print(json.dumps(snapshot()))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
