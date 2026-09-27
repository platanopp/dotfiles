#!/usr/bin/env python3
"""Colour a Wooting keyboard from the wallpaper, as a mosaic: every key its
own shade. The letters draw from the picture's dominant colour and its
nearest neighbours, every other key from the picture's other tones, and each
key is mixed between two of them and moved in lightness and saturation --
from pale to deep, the way a picture's one colour actually varies. Accents
-- a vivid colour on a small part of the picture, like red eyes on a blue
portrait -- are found apart (see accents()) and laid in as soft patches. The
arrangement is fixed for a given wallpaper and different for the next.

Talks to the keyboard through Wooting's RGB SDK (libwooting-rgb-sdk.so, in
~/.local/lib or the system's lib). The SDK paints over the active profile
without changing it: the profile's own colours come back on `reset`, a
profile switch on the keyboard, or unplugging it. This script never calls
wooting_rgb_close(), which would reset the colours on the way out.

  apply IMAGE [BRIGHTNESS]   paint from IMAGE; BRIGHTNESS 10-100 (default 100)
  palette IMAGE              JSON: the colours apply would use, per key,
                             without touching the keyboard
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
    """(letters, others, accents): pools of HLS colours. Letters get the dominant
    colour -- the most common, weighted by how colourful it is, so a grey
    picture with a pink subject gives pink -- and the colours nearest it in
    hue; others get the rest. Close colours are kept, not merged: they are
    the variety the mosaic is made of."""
    from PIL import Image
    with Image.open(image_path) as im:
        im = im.convert("RGB")
        im.thumbnail((240, 240))
        q = im.quantize(colors=16, method=Image.Quantize.MEDIANCUT)
        pal = q.getpalette()
        counts = q.getcolors()
    total = sum(n for n, _ in counts) or 1
    colours = []
    for n, idx in counts:
        h, l, s = hls(tuple(pal[idx * 3: idx * 3 + 3]))
        # Near-black and near-white say little about a picture's colour.
        edge = 0.3 if l < 0.08 or l > 0.94 else 1.0
        colours.append(((h, l, s), n / total * (0.2 + s) * edge))
    colours.sort(key=lambda c: c[1], reverse=True)
    dominant = colours[0][0]

    # The picture's main colours only: the long tail of a quantized palette
    # is edges and noise. Nearest the dominant hue go to the letters.
    main = [c for c, w in colours[1:9] if w > 0.004]
    rest = sorted(main, key=lambda c: hue_distance(c[0], dominant[0]))
    letters = [dominant] + rest[:3]
    others = rest[3:8] or rest[:]
    found = accents(image_path, dominant[0])
    # A picture of one colour: its own neighbours, lighter and darker.
    k = 0
    while len(others) < 4:
        h, l, s = dominant
        others.append(((h + (0.035, -0.035, 0.07, -0.07)[k]) % 1.0,
                       min(0.8, max(0.15, l + (-0.15, 0.15, -0.25, 0.1)[k])), s))
        k += 1
    return letters, others, found


def accents(image_path, dominant_hue):
    """Vivid colours that cover little of the picture. Quantizing by area
    folds them into whatever surrounds them, so they are looked for on
    their own: a histogram of hue over the saturated pixels of a large
    thumbnail (a small one averages a pair of eyes away), runs of adjacent
    hues merged, and every run far enough from the dominant hue and big
    enough not to be noise kept -- by how many vivid pixels it has, up to
    three. The colour of each is the mean of its most saturated pixels."""
    from PIL import Image
    with Image.open(image_path) as im:
        im = im.convert("RGB")
        im.thumbnail((900, 900))
        hsv = im.convert("HSV").tobytes()
        rgb = im.tobytes()
    bins = 36
    vivid = [[0, 0, 0, 0] for _ in range(bins)]     # r, g, b sums and count
    for i in range(0, len(hsv), 3):
        h, s, v = hsv[i], hsv[i + 1], hsv[i + 2]
        if s < 64 or v < 64:
            continue
        b = h * bins // 256
        if s > 140:
            acc = vivid[b]
            acc[0] += rgb[i]; acc[1] += rgb[i + 1]; acc[2] += rgb[i + 2]; acc[3] += 1

    # Only hues well away from the dominant one can be accents; among
    # those, adjacent hues with vivid pixels form a group, split where the
    # count dips to a valley -- the lavender of a shadow and the red of an
    # eye can sit next to each other on the circle and are not one colour.
    def far(i):
        return hue_distance((i + 0.5) / bins, dominant_hue) >= 40 / 360
    alive = [far(i) and vivid[i][3] >= 12 for i in range(bins)]
    start = next((i for i in range(bins) if not alive[i]), None)
    if start is None:
        return []
    groups, current = [], []
    for k in range(1, bins + 1):
        i = (start + k) % bins
        if alive[i]:
            current.append(i)
        elif current:
            groups.append(current)
            current = []
    if current:
        groups.append(current)

    def split(group):
        v = [vivid[i][3] for i in group]
        for j in range(1, len(group) - 1):
            if v[j] < 0.5 * min(max(v[:j]), max(v[j + 1:])):
                return split(group[:j]) + split(group[j + 1:])
        return [group]

    found = []
    for group in (g for grp in groups for g in split(grp)):
        m = sum(vivid[i][3] for i in group)
        if m < 20:
            continue
        r = sum(vivid[i][0] for i in group) / m
        g = sum(vivid[i][1] for i in group) / m
        bl = sum(vivid[i][2] for i in group) / m
        found.append((m, hls((r, g, bl))))
    found.sort(reverse=True)
    return [c for _, c in found[:3]]


def mix(a, b, t):
    """Between two HLS colours, the short way round the hue circle."""
    dh = ((b[0] - a[0] + 0.5) % 1.0) - 0.5
    return ((a[0] + dh * t) % 1.0, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def for_leds(h, l, s, brightness):
    """LEDs wash out: what is a soft pink on screen is nearly white on a
    key. More saturation, lightness kept in the middle, then dimmed."""
    s = min(1.0, s * 1.3 + 0.1)
    l = min(0.62, max(0.18, l))
    r, g, b = colorsys.hls_to_rgb(h % 1.0, l, s)
    k = brightness / 100
    return tuple(int(round(c * 255 * k)) for c in (r, g, b))


def jitter(row, col, salt, seed=""):
    """-1..1, the same for a key and a wallpaper every time (so reapplying
    does not shuffle the board), different from key to key."""
    return (zlib.crc32(f"{seed}:{row}:{col}:{salt}".encode()) % 2001) / 1000 - 1


def noise(row, col, salt, seed, scale=3.5):
    """Smooth value noise over the board, 0..1: random values on a coarse
    grid (a point every `scale` keys), eased between. Keys side by side get
    close values, so whatever it drives changes gradually across the board
    instead of key to key."""
    x, y = col / scale, row / (scale * 0.6)
    x0, y0 = int(x), int(y)
    fx, fy = x - x0, y - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)

    def at(i, j):
        return (jitter(j, i, salt, seed) + 1) / 2

    top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * fx
    bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * fx
    return top + (bottom - top) * fy


def ramp(pool, t):
    """A colour at t (0..1) along a pool laid out as a gradient, from
    darkest to lightest -- so a smooth t gives a smooth run of colours."""
    ordered = sorted(pool, key=lambda c: c[1])
    if len(ordered) == 1:
        return ordered[0]
    x = max(0.0, min(1.0, t)) * (len(ordered) - 1)
    i = min(int(x), len(ordered) - 2)
    a, b = ordered[i], ordered[i + 1]
    # Two colours far apart in hue are not blended: halfway between orange
    # and blue is a green the picture never had. The ramp steps instead.
    if hue_distance(a[0], b[0]) > 45 / 360 and min(a[2], b[2]) > 0.2:
        return a if x - i < 0.5 else b
    return mix(a, b, x - i)


def harmonise(accent, pool):
    """An accent keeps its hue and meets the board halfway on lightness and
    saturation, so it reads as part of the same picture."""
    l = sum(c[1] for c in pool) / len(pool)
    s = sum(c[2] for c in pool) / len(pool)
    return (accent[0], accent[1] + (l - accent[1]) * 0.5, accent[2] + (s - accent[2]) * 0.35)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def key_colours(letters, others, found, brightness, seed=""):
    """The board as flowing gradients: a smooth field chooses where along
    each pool's ramp a key sits, so neighbours are near each other. Accents
    come as one or two soft patches -- where their own field runs high --
    blending into what surrounds them, the letters taking them more lightly.
    A little per-key variation on top keeps it a mosaic."""
    # A dark picture gives dark colours, and a dark colour on an LED is a
    # key that looks switched off. The palette's lightness is stretched into
    # the band LEDs show well, keeping which colours are lighter than which.
    everything = letters + others + found
    lo = min(c[1] for c in everything)
    hi = max(c[1] for c in everything)
    span = max(hi - lo, 0.12)

    def lit(c):
        return (c[0], 0.3 + (c[1] - lo) / span * 0.3, c[2])

    letters = [lit(c) for c in letters]
    others = [lit(c) for c in others]
    found = [lit(c) for c in found]
    pool = letters + others
    found = [harmonise(a, pool) for a in found]
    # Where the patches sit: one per accent, the first larger, apart from
    # each other -- chosen by the wallpaper, so the same picture gives the
    # same board.
    centres = []
    for k in range(len(found[:2])):
        for attempt in range(8):
            cr = 1 + int((jitter(k, attempt, "cr", seed) + 1) / 2 * 4.99)
            cc = int((jitter(k, attempt, "cc", seed) + 1) / 2 * 13.99)
            if all(abs(cc - c) + abs(cr - r) * 2 > 6 for r, c, _ in centres):
                break
        centres.append((cr, cc, 3.2 if k == 0 else 2.4))
    out = {}
    for row in range(1, ROWS):
        for col in range(COLS):
            letter = (row, col) in LETTERS
            t = noise(row, col, "base", seed)
            if letter:
                colour = ramp(letters, t)
            else:
                colour = ramp(others + letters[:1], t)

            for (cr, cc, radius), accent in zip(centres, found[:2]):
                # Rows are closer together than columns are wide in the
                # picture this makes, so distance counts them a bit more.
                d = ((col - cc) ** 2 + ((row - cr) * 1.3) ** 2) ** 0.5
                d += jitter(row, col, "edge", seed) * 0.6      # a ragged edge
                w = 1 - smoothstep(radius * 0.35, radius, d)
                colour = mix(colour, accent, w * (0.65 if letter else 0.95))

            h, l, s = colour
            h += jitter(row, col, "h", seed) * 0.01
            l += jitter(row, col, "l", seed) * 0.08
            s += jitter(row, col, "s", seed) * 0.12
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


def describe(letters, others, found, keys):
    return {"ok": True, "dominant": hex_of(*letters[0]),
            "others": [hex_of(*o) for o in others],
            "accents": [hex_of(*a) for a in found],
            # Full brightness, for the Settings page's picture of the board.
            "keys": {f"{r},{c}": "#%02x%02x%02x" % rgb for (r, c), rgb in keys.items()}}


def cmd_palette(image):
    letters, others, found = palette(image)
    return describe(letters, others, found, key_colours(letters, others, found, 100, image))


def cmd_apply(image, brightness):
    if not os.path.isfile(image):
        return {"ok": False, "error": "no such image"}
    lib, err = connect()
    if not lib:
        return {"ok": False, "error": err}
    letters, others, found = palette(image)
    lib.wooting_rgb_array_auto_update(False)
    for (row, col), (r, g, b) in key_colours(letters, others, found, brightness, image).items():
        lib.wooting_rgb_array_set_single(row, col, r, g, b)
    if not lib.wooting_rgb_array_update_keyboard():
        return {"ok": False, "error": "the keyboard did not take the colours"}
    return describe(letters, others, found, key_colours(letters, others, found, 100, image))


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
