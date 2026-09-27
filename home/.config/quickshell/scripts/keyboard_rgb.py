#!/usr/bin/env python3
"""Light a Wooting keyboard with the wallpaper itself: the whole picture laid
over the board, each key lit with the colour of the part of the picture
under it -- by the key's real place and size, so the space bar takes a wide
strip along the bottom and Backspace a double-width patch top right.

Talks to the keyboard through Wooting's RGB SDK (libwooting-rgb-sdk.so, in
~/.local/lib or the system's lib). The SDK paints over the active profile
without changing it: the profile's own colours come back on `reset`, a
profile switch on the keyboard, or unplugging it. This script never calls
wooting_rgb_close(), which would reset the colours on the way out.

  apply IMAGE [BRIGHTNESS]   paint from IMAGE; BRIGHTNESS 10-100 (default 100)
  palette IMAGE              JSON: the colour of every key, without touching
                             the keyboard
  reset                      back to the profile's colours
  status                     JSON: whether a keyboard is there, and which

Prints JSON: {"ok": true, ...} or {"ok": false, "error": ...}.
"""

import colorsys
import ctypes
import json
import os
import sys

LIB_CANDIDATES = [
    os.path.expanduser("~/.local/lib/libwooting-rgb-sdk.so"),
    "/usr/local/lib/libwooting-rgb-sdk.so",
    "/usr/lib/libwooting-rgb-sdk.so",
    "libwooting-rgb-sdk.so.0",
]

# A 60% ISO board, row by row as it sits on the desk: (width in key units,
# column in Wooting's matrix). Matrix rows are these rows plus one; row 0
# is the function row a 60% board does not have. Every row is 15 units.
LAYOUT = [
    [(1, 0), (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9),
     (1, 10), (1, 11), (1, 12), (2, 13)],
    [(1.5, 0), (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9),
     (1, 10), (1, 11), (1, 12), (1.5, 13)],
    [(1.75, 0), (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9),
     (1, 10), (1, 11), (1, 12), (1.25, 13)],
    [(1.25, 0), (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9),
     (1, 10), (1, 11), (2.75, 13)],
    [(1.25, 0), (1.25, 1), (1.25, 2), (6.25, 6), (1.25, 10), (1.25, 11), (1.25, 12), (1.25, 13)],
]
UNITS = 15


class Meta(ctypes.Structure):
    _fields_ = [("connected", ctypes.c_bool), ("model", ctypes.c_char_p),
                ("max_rows", ctypes.c_uint8), ("max_columns", ctypes.c_uint8),
                ("led_index_max", ctypes.c_uint8), ("device_type", ctypes.c_int),
                ("v2_interface", ctypes.c_bool), ("layout", ctypes.c_int),
                ("uses_small_packets", ctypes.c_bool), ("uses_multi_report", ctypes.c_bool)]


def load_sdk():
    for path in LIB_CANDIDATES:
        try:
            lib = ctypes.CDLL(path)
        except OSError:
            continue
        lib.wooting_rgb_kbd_connected.restype = ctypes.c_bool
        lib.wooting_rgb_device_info.restype = ctypes.POINTER(Meta)
        lib.wooting_rgb_array_set_single.restype = ctypes.c_bool
        lib.wooting_rgb_array_set_single.argtypes = [ctypes.c_uint8] * 5
        lib.wooting_rgb_array_update_keyboard.restype = ctypes.c_bool
        lib.wooting_rgb_array_auto_update.argtypes = [ctypes.c_bool]
        lib.wooting_rgb_reset.restype = ctypes.c_bool
        return lib
    return None


# ── The picture, key by key ──────────────────────────────────────────────

def sample(image_path):
    """{(matrix row, col): (h, l, s)}: the mean colour of the picture under
    each key. The whole picture is fitted to the board, not cropped -- it is
    squeezed from 16:9 to the board's 3:1, which LEDs a key apart cannot
    tell from the original."""
    from PIL import Image
    cell = 24
    with Image.open(image_path) as im:
        im = im.convert("RGB")
        # A key-sized cell of this is still hundreds of pixels: enough for a
        # fair mean, cheap to cut up.
        im = im.resize((UNITS * cell, len(LAYOUT) * cell), Image.BOX)
    out = {}
    for r, row in enumerate(LAYOUT):
        x = 0.0
        for width, col in row:
            box = (int(x * cell), r * cell, int((x + width) * cell), (r + 1) * cell)
            rgb = im.crop(box).resize((1, 1), Image.BOX).getpixel((0, 0))
            out[(r + 1, col)] = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
            x += width
    return out


def for_leds(keys, brightness):
    """LEDs are not a screen. A dark part of the picture on a key looks like
    a key switched off, and a soft colour washes out to white. So the
    picture's lightness is stretched into the band LEDs show well --
    keeping which keys are lighter than which -- and colour is pushed up."""
    lo = min(c[1] for c in keys.values())
    hi = max(c[1] for c in keys.values())
    span = max(hi - lo, 0.12)
    k = brightness / 100
    out = {}
    for key, (h, l, s) in keys.items():
        l = 0.22 + (l - lo) / span * 0.38
        s = min(1.0, s * 1.35 + 0.08)
        r, g, b = colorsys.hls_to_rgb(h, l, s)
        out[key] = tuple(int(round(c * 255 * k)) for c in (r, g, b))
    return out


# ── Commands ─────────────────────────────────────────────────────────────

def connect():
    lib = load_sdk()
    if lib is None:
        return None, "the Wooting RGB SDK is not installed"
    if not lib.wooting_rgb_kbd_connected():
        return None, "no Wooting keyboard found"
    return lib, ""


def cmd_status():
    lib, err = connect()
    if not lib:
        return {"ok": True, "connected": False, "sdk": err != "the Wooting RGB SDK is not installed", "error": err}
    meta = lib.wooting_rgb_device_info().contents
    return {"ok": True, "connected": True, "sdk": True,
            "model": (meta.model or b"").decode(errors="replace")}


def describe(keys):
    # Full brightness, for the Settings page's picture of the board.
    return {"ok": True, "keys": {f"{r},{c}": "#%02x%02x%02x" % rgb for (r, c), rgb in keys.items()}}


def cmd_palette(image):
    return describe(for_leds(sample(image), 100))


def cmd_apply(image, brightness):
    if not os.path.isfile(image):
        return {"ok": False, "error": "no such image"}
    lib, err = connect()
    if not lib:
        return {"ok": False, "error": err}
    picture = sample(image)
    lib.wooting_rgb_array_auto_update(False)
    for (row, col), (r, g, b) in for_leds(picture, brightness).items():
        lib.wooting_rgb_array_set_single(row, col, r, g, b)
    if not lib.wooting_rgb_array_update_keyboard():
        return {"ok": False, "error": "the keyboard did not take the colours"}
    return describe(for_leds(picture, 100))


def cmd_reset():
    lib, err = connect()
    if not lib:
        return {"ok": False, "error": err}
    return {"ok": bool(lib.wooting_rgb_reset())}


def main():
    a = sys.argv[1:]
    try:
        if a[:1] == ["apply"] and len(a) >= 2:
            b = max(10, min(100, int(float(a[2])))) if len(a) > 2 else 100
            out = cmd_apply(os.path.expanduser(a[1]), b)
        elif a[:1] == ["palette"] and len(a) == 2:
            out = cmd_palette(os.path.expanduser(a[1]))
        elif a == ["reset"]:
            out = cmd_reset()
        elif a in ([], ["status"]):
            out = cmd_status()
        else:
            sys.exit(__doc__)
    except (OSError, ValueError) as e:
        out = {"ok": False, "error": str(e)}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
