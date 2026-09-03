#!/usr/bin/env python3
"""Choose which part of a wallpaper the desktop shows.

hyprpaper only knows cover, contain and tile: all three decide the framing
themselves and none of them can be told to favour one side of the picture.
So the framing happens here instead -- the image is cropped to the screen's
shape at a chosen point and handed over already the right size, which is a
thing hyprpaper cannot get wrong.

The choice is a focus point rather than a rectangle. Only one axis ever has
any slack, since the crop keeps the screen's aspect and one dimension always
runs out first, and a point says where along that axis to sit without having
to know which axis it is. 0.5, 0.5 crops dead centre, which is what cover
did, so a wallpaper nobody has framed looks exactly as it did before.

    wallpaper_crop.py current
    wallpaper_crop.py get <image>
    wallpaper_crop.py apply <image> [<focusX> <focusY>]
"""

import hashlib
import json
import os
import subprocess
import sys

STATE = os.path.expanduser("~/.cache/quickshell/wallpaper-focus.json")
CACHE = os.path.expanduser("~/.cache/quickshell/wallpapers")
HYPRPAPER = os.path.expanduser("~/.config/hypr/hyprpaper.conf")


def load_state():
    try:
        with open(STATE, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return {"focus": {}, "current": ""}
    state.setdefault("focus", {})
    state.setdefault("current", "")
    return state


def save_state(state):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2)
    os.replace(tmp, STATE)


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def image_size(path):
    out = run("magick", "identify", "-format", "%w %h", path + "[0]")
    width, height = out.split()
    return int(width), int(height)


def screen_size():
    """The largest screen, so one crop serves every monitor that shares its
    shape and the biggest one is never the one being upscaled."""
    try:
        monitors = json.loads(run("hyprctl", "monitors", "-j"))
    except (subprocess.CalledProcessError, OSError, ValueError):
        return 1920, 1080
    best = (0, 0)
    for monitor in monitors:
        width, height = int(monitor.get("width", 0)), int(monitor.get("height", 0))
        # A rotated monitor reports its panel size, not what is on screen.
        if int(monitor.get("transform", 0)) % 2 == 1:
            width, height = height, width
        if width * height > best[0] * best[1]:
            best = (width, height)
    return best if best[0] > 0 else (1920, 1080)


def crop_box(src_w, src_h, dst_w, dst_h, focus_x, focus_y):
    """The rectangle of the source that ends up on screen.

    Whichever axis has room to spare is the one the focus moves along; the
    other is pinned because the crop already spans all of it.
    """
    if src_w * dst_h > src_h * dst_w:
        box_h = src_h
        box_w = round(src_h * dst_w / dst_h)
    else:
        box_w = src_w
        box_h = round(src_w * dst_h / dst_w)
    box_w, box_h = min(box_w, src_w), min(box_h, src_h)

    x = round((src_w - box_w) * min(max(focus_x, 0.0), 1.0))
    y = round((src_h - box_h) * min(max(focus_y, 0.0), 1.0))
    return box_w, box_h, x, y


def cmd_get(path):
    src_w, src_h = image_size(path)
    dst_w, dst_h = screen_size()
    state = load_state()
    focus = state["focus"].get(os.path.abspath(path), [0.5, 0.5])
    box_w, box_h, _, _ = crop_box(src_w, src_h, dst_w, dst_h, 0.5, 0.5)
    print(json.dumps({
        "path": path,
        "width": src_w,
        "height": src_h,
        "screenWidth": dst_w,
        "screenHeight": dst_h,
        "focusX": focus[0],
        "focusY": focus[1],
        # Fraction of the source the crop spans. Whichever of these is below
        # 1 is the axis with room to move, and the widget reads them to know
        # which way it is allowed to drag.
        "coverX": box_w / src_w,
        "coverY": box_h / src_h,
    }))


def cmd_apply(path, focus_x=None, focus_y=None):
    """Render the crop and remember it.

    Called without a focus this re-applies whatever framing the wallpaper was
    last given, which is what picking one from the carousel should do: the
    framing belongs to the wallpaper, not to the moment it was chosen.
    """
    path = os.path.abspath(path)
    if focus_x is None or focus_y is None:
        stored = load_state()["focus"].get(path, [0.5, 0.5])
        focus_x, focus_y = stored[0], stored[1]
    src_w, src_h = image_size(path)
    dst_w, dst_h = screen_size()
    box_w, box_h, x, y = crop_box(src_w, src_h, dst_w, dst_h, focus_x, focus_y)

    # Named for everything that changes the output, so re-applying the same
    # framing reuses the file and a wallpaper edited in place does not.
    try:
        stamp = os.path.getmtime(path)
    except OSError:
        stamp = 0
    key = "%s|%s|%dx%d|%d,%d" % (path, stamp, dst_w, dst_h, x, y)
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]
    # JPEG for photographs, PNG for anything that might have flat colour or
    # transparency: a screen-sized PNG of a photo is tens of megabytes.
    ext = ".jpg" if os.path.splitext(path)[1].lower() in (".jpg", ".jpeg") else ".png"
    out = os.path.join(CACHE, digest + ext)

    os.makedirs(CACHE, exist_ok=True)
    if not os.path.exists(out):
        tmp = out + ".tmp" + ext
        run("magick", path + "[0]",
            "-crop", "%dx%d+%d+%d" % (box_w, box_h, x, y), "+repage",
            "-resize", "%dx%d!" % (dst_w, dst_h),
            "-quality", "95", tmp)
        os.replace(tmp, out)

    state = load_state()
    state["focus"][path] = [focus_x, focus_y]
    state["current"] = path
    save_state(state)

    # Anything else cropped from this same wallpaper is a framing the user
    # has moved on from.
    prune(out, path)

    print(json.dumps({"path": path, "rendered": out,
                      "focusX": focus_x, "focusY": focus_y}))


def prune(keep, source):
    """Drop earlier crops of this same wallpaper.

    The cache is keyed by a digest that cannot be read back, so the mapping
    the other way is kept in the state file: every rendered file this source
    has ever produced, minus the one still in use.
    """
    state = load_state()
    rendered = state.setdefault("rendered", {})
    previous = rendered.get(source, [])
    for old in previous:
        if old != keep:
            try:
                os.remove(old)
            except OSError:
                pass
    rendered[source] = [keep]
    save_state(state)


def cmd_current():
    """The wallpaper in use, as the user's own file rather than as the crop.

    The state file knows it directly. Falling back to hyprpaper's config only
    helps for a wallpaper set before this script existed, where the config
    still points at the original.
    """
    state = load_state()
    if state["current"] and os.path.exists(state["current"]):
        print(state["current"])
        return
    try:
        with open(HYPRPAPER, encoding="utf-8") as handle:
            for line in handle:
                stripped = line.strip()
                if stripped.startswith("path"):
                    _, _, value = stripped.partition("=")
                    value = value.strip()
                    # A cached crop is not an answer to this question.
                    if value and not value.startswith(CACHE):
                        print(value)
                    return
    except OSError:
        return


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == "current":
        cmd_current()
    elif args[0] == "get" and len(args) == 2:
        cmd_get(args[1])
    elif args[0] == "apply" and len(args) == 2:
        cmd_apply(args[1])
    elif args[0] == "apply" and len(args) == 4:
        cmd_apply(args[1], float(args[2]), float(args[3]))
    else:
        sys.exit(__doc__)


main()
