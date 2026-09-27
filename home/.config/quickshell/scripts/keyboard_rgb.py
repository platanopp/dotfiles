#!/usr/bin/env python3
"""Colour a Wooting keyboard from the wallpaper: the letters in the picture's
dominant colour, every other key in its other tones, each key a shade apart
so the board reads as a mosaic rather than flat blocks.

Talks to the keyboard through Wooting's RGB SDK (libwooting-rgb-sdk.so, in
~/.local/lib or the system's lib). The SDK paints over the active profile
without changing it: the profile's own colours come back on `reset`, a
profile switch on the keyboard, or unplugging it. This script never calls
wooting_rgb_close(), which would reset the colours on the way out.

  apply IMAGE [BRIGHTNESS]   paint from IMAGE; BRIGHTNESS 10-100 (default 100)
  palette IMAGE              JSON: the colours apply would use, without
                             touching the keyboard
  reset                      back to the profile's colours
  status                     JSON: whether a keyboard is there, and which

Prints JSON: {"ok": true, ...} or {"ok": false, "error": ...}.
"""

import colorsys
import ctypes
import json
import os
import sys
import zlib

LIB_CANDIDATES = [
    os.path.expanduser("~/.local/lib/libwooting-rgb-sdk.so"),
    "/usr/local/lib/libwooting-rgb-sdk.so",
    "/usr/lib/libwooting-rgb-sdk.so",
    "libwooting-rgb-sdk.so.0",
]

ROWS, COLS = 6, 14

# The letters on a 60% board in Wooting's matrix: QWERTY row, home row
# (Ñ included on a Spanish layout -- it is a letter), and Z to M, which
# starts one column in on ISO boards, after the extra < key.
LETTERS = ({(2, c) for c in range(1, 11)}
           | {(3, c) for c in range(1, 11)}
           | {(4, c) for c in range(2, 9)})


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


# ── The palette ──────────────────────────────────────────────────────────

def hls(rgb):
    return colorsys.rgb_to_hls(*(c / 255 for c in rgb))


def hue_distance(a, b):
    d = abs(a - b) % 1.0
    return min(d, 1 - d)


def palette(image_path):
    """The dominant colour and the others, as HLS tuples. Dominant is the
    most common colour weighted by how colourful it is: a mostly grey
    picture with a pink subject gives pink, not grey."""
    from PIL import Image
    with Image.open(image_path) as im:
        im = im.convert("RGB")
        im.thumbnail((240, 240))
        q = im.quantize(colors=10, method=Image.Quantize.MEDIANCUT)
        pal = q.getpalette()
        counts = sorted(q.getcolors(), reverse=True)
    total = sum(n for n, _ in counts) or 1
    colours = []
    for n, idx in counts:
        rgb = tuple(pal[idx * 3: idx * 3 + 3])
        h, l, s = hls(rgb)
        # Near-black and near-white say little about a picture's colour.
        edge = 0.35 if l < 0.08 or l > 0.94 else 1.0
        colours.append({"hls": (h, l, s), "weight": n / total * (0.25 + s) * edge})
    colours.sort(key=lambda c: c["weight"], reverse=True)
    dominant = colours[0]["hls"]

    others = []
    for c in colours[1:]:
        h, l, s = c["hls"]
        # Skip what would look like the letters again.
        if hue_distance(h, dominant[0]) < 0.03 and abs(l - dominant[1]) < 0.08:
            continue
        others.append(c["hls"])
    # A picture of one colour: its neighbours, lighter and darker.
    while len(others) < 3:
        k = len(others)
        h, l, s = dominant
        others.append(((h + (0.04 if k % 2 else -0.04)) % 1.0,
                       min(0.8, max(0.15, l + (-0.12, 0.12, -0.2)[k])), s))
    return dominant, others[:4]


def for_leds(h, l, s, brightness):
    """LEDs wash out: what is a soft pink on screen is nearly white on a
    key. More saturation, lightness kept in the middle, then dimmed."""
    s = min(1.0, s * 1.4 + 0.12)
    l = min(0.58, max(0.28, l))
    r, g, b = colorsys.hls_to_rgb(h % 1.0, l, s)
    k = brightness / 100
    return tuple(int(round(c * 255 * k)) for c in (r, g, b))


def jitter(row, col, salt):
    """-1..1, the same for a key every time (so reapplying does not shuffle
    the board), different from key to key."""
    return (zlib.crc32(f"{row}:{col}:{salt}".encode()) % 2001) / 1000 - 1


def key_colours(dominant, others, brightness):
    out = {}
    for row in range(1, ROWS):
        for col in range(COLS):
            if (row, col) in LETTERS:
                h, l, s = dominant
            else:
                # The other tones spread across the board from left to right,
                # with a little of the row mixed in, so neighbours share one
                # and the board still moves from one to the next.
                pos = (col / (COLS - 1)) * 0.8 + (row / ROWS) * 0.2
                h, l, s = others[min(len(others) - 1, int(pos * len(others)))]
            h += jitter(row, col, "h") * 0.012
            l += jitter(row, col, "l") * 0.07
            s += jitter(row, col, "s") * 0.10
            out[(row, col)] = for_leds(h, l, max(0.0, min(1.0, s)), brightness)
    return out


def hex_of(h, l, s):
    return "#%02x%02x%02x" % for_leds(h, l, s, 100)


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


def cmd_palette(image):
    dominant, others = palette(image)
    return {"ok": True, "dominant": hex_of(*dominant), "others": [hex_of(*o) for o in others]}


def cmd_apply(image, brightness):
    if not os.path.isfile(image):
        return {"ok": False, "error": "no such image"}
    lib, err = connect()
    if not lib:
        return {"ok": False, "error": err}
    dominant, others = palette(image)
    lib.wooting_rgb_array_auto_update(False)
    for (row, col), (r, g, b) in key_colours(dominant, others, brightness).items():
        lib.wooting_rgb_array_set_single(row, col, r, g, b)
    if not lib.wooting_rgb_array_update_keyboard():
        return {"ok": False, "error": "the keyboard did not take the colours"}
    return {"ok": True, "dominant": hex_of(*dominant), "others": [hex_of(*o) for o in others]}


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
