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

  apply IMAGE [BRIGHTNESS] [--animate]
                             paint from IMAGE; BRIGHTNESS 10-100 (default
                             100). --animate sweeps from the colours last
                             sent to the new ones instead of switching.
  palette IMAGE              JSON: the colour of every key, without touching
                             the keyboard
  reset                      back to the profile's colours
  status                     JSON: whether a keyboard is there, and which
  serve                      stay connected and take commands on stdin, one
                             JSON object a line -- {"cmd": "apply", "image",
                             "brightness", "animate"}, {"cmd": "reset"},
                             {"cmd": "status"} -- answering each on stdout.
                             What the shell runs: finding the keyboard costs
                             two seconds (the SDK probes every model it
                             knows), paid once here instead of per change.
                             Also {"cmd": "target", "profile": N}: paint only
                             while the keyboard is on profile N (0-3; -1 for
                             any), the profile's own colours on the others.
                             The active profile is watched, and reported as
                             {"cmd": "profile", "active": N} when it changes.
  profile                    JSON: the keyboard's active profile (0-3)

Prints JSON: {"ok": true, ...} or {"ok": false, "error": ...}.
"""

import colorsys
import ctypes
import fcntl
import glob
import json
import os
import select
import sys
import time

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

# The colours last sent (sRGB, full brightness), for the next sweep to start
# from. A cache, not a setting: without it the sweep starts from dark.
LAST = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                    "quickshell", "keyboard-rgb.json")


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
    """{(matrix row, col): (h, l, s)}: the colour of the picture under each
    key. The whole picture is fitted to the board, not cropped -- squeezed
    from 16:9 to the board's 3:1, which LEDs a key apart cannot tell.

    Not the mean of what is under a key: half white hair and half blue sky
    average to a grey-blue that is nowhere in the picture. The patch is
    split into its few main colours and the one that dominates it is used,
    a vivid one counting for more -- so a key over a red eye can be red."""
    from PIL import Image
    cell = 24
    with Image.open(image_path) as im:
        im = im.convert("RGB")
        im = im.resize((UNITS * cell, len(LAYOUT) * cell), Image.LANCZOS)
    out = {}
    for r, row in enumerate(LAYOUT):
        x = 0.0
        for width, col in row:
            box = (int(x * cell), r * cell, int((x + width) * cell), (r + 1) * cell)
            patch = im.crop(box)
            q = patch.quantize(colors=4, method=Image.Quantize.MEDIANCUT)
            pal = q.getpalette()
            best, best_score = None, -1.0
            total = patch.width * patch.height
            for count, idx in q.getcolors():
                rgb = tuple(pal[idx * 3: idx * 3 + 3])
                h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
                # Share of the patch, then vividness: a colour needs about a
                # fifth of a key to win over a duller one covering the rest.
                score = (count / total) * (0.35 + s * (1 - abs(l - 0.5) * 1.2))
                if score > best_score:
                    best, best_score = (h, l, s), score
            out[(r + 1, col)] = best
            x += width
    return out


def percentile(values, p):
    v = sorted(values)
    return v[min(len(v) - 1, int(p * len(v)))]


def for_screen(keys):
    """The colours as they should look -- in sRGB, like the screen. A dark
    part of the picture on a key reads as a key switched off, so lightness
    is lifted into the band LEDs show well; only gently stretched, and by
    percentiles, so one bright key does not dim all the others."""
    ls = [c[1] for c in keys.values()]
    lo, hi = percentile(ls, 0.05), percentile(ls, 0.95)
    span = max(hi - lo, 0.2)
    out = {}
    for key, (h, l, s) in keys.items():
        n = max(0.0, min(1.0, (l - lo) / span))
        # Halfway between the picture's own lightness and the stretched one.
        l = max(0.3, min(0.78, (l + (0.36 + n * 0.44)) / 2))
        s = min(1.0, s * 1.12 + 0.02)
        out[key] = tuple(int(round(c * 255)) for c in colorsys.hls_to_rgb(h, l, s))
    return out


def for_leds(rgb, brightness):
    """sRGB to what an LED needs to look the same. A screen's values are
    gamma-encoded; an LED's are plain light output. Sent as they are, every
    mid tone comes out far too bright and the colours wash out to pastel --
    so they are decoded towards linear light first, then dimmed. Not all
    the way (a power of 1.8, not sRGB's 2.2): fully decoded, the keys read
    as too dark beside the screen, which a room's light washes out more
    than it does an LED."""
    k = brightness / 100

    def lin(v):
        return (v / 255) ** 1.8

    return tuple(int(round(lin(v) * 255 * k)) for v in rgb)


def linear(rgb):
    return tuple(v / 255 for v in for_leds(rgb, 100))


def centres():
    """{key: (x, row)}: where each key's middle is, in key units."""
    out = {}
    for r, row in enumerate(LAYOUT):
        x = 0.0
        for width, col in row:
            out[(r + 1, col)] = (x + width / 2, r)
            x += width
    return out


def sweep(lib, old, new, brightness, duration=1.4):
    """A slanted front crosses the board left to right. Behind it keys have
    turned to the new colours; on it they flare, lit brighter in the new
    colour; ahead of it they keep the old ones. Mixed in linear light, the
    way two lights actually add."""
    at = centres()
    k = brightness / 100
    old_l = {key: linear(old.get(key, (0, 0, 0))) for key in new}
    new_l = {key: linear(rgb) for key, rgb in new.items()}
    width = 2.2                      # how many keys the change takes to pass
    start, end = -width - 3, UNITS + width + 1
    # Driven by the clock, not a frame count: a frame costs about 32 ms to
    # send to a 60HE, so the board shows as many as it can take and the
    # sweep lasts `duration` either way.
    t0 = time.monotonic()
    while True:
        p = min(1.0, (time.monotonic() - t0) / duration)
        p = p * p * (3 - 2 * p) * 0.35 + p * 0.65      # eases in and out a little
        front = start + (end - start) * p
        for key, (x, row) in at.items():
            if key not in new_l:
                continue
            pos = x + row * 0.7          # the slant
            u = max(0.0, min(1.0, (front - pos) / width))
            u = u * u * (3 - 2 * u)
            flare = max(0.0, 1 - abs(front - pos - width * 0.5) / 1.4)
            a, b = old_l[key], new_l[key]
            c = [a[i] + (b[i] - a[i]) * u for i in range(3)]
            # The flare: the new colour, brighter, towards white at its peak.
            c = [min(1.0, v + flare * (0.55 * b[i] + 0.25)) for i, v in enumerate(c)]
            lib.wooting_rgb_array_set_single(key[0], key[1], *(int(round(v * 255 * k)) for v in c))
        lib.wooting_rgb_array_update_keyboard()
        if front >= end:
            break


def load_last():
    try:
        with open(LAST) as fh:
            return {tuple(int(p) for p in key.split(",")): tuple(rgb) for key, rgb in json.load(fh).items()}
    except (OSError, ValueError):
        return {}


def save_last(colours):
    try:
        os.makedirs(os.path.dirname(LAST), exist_ok=True)
        with open(LAST, "w") as fh:
            json.dump({f"{r},{c}": list(rgb) for (r, c), rgb in colours.items()}, fh)
    except OSError:
        pass


# ── The active profile ───────────────────────────────────────────────────
#
# Read over hidraw, not the SDK: the SDK waits for a 2046-byte answer and a
# 60HE (ARM) sends 33, so it gives up and drops the connection. The request
# is Wooting's command 11 (GetCurrentKeyboardProfileIndex) as a feature
# report on the configuration interface (usage page 0xFF55); the answer is
# an input report [id, D1, DA, 11, status, length, data...] whose second data
# byte is the profile, 0-3.

WOOTING_VENDOR = "31E3"
PROFILE_COMMAND = 11


def HIDIOCSFEATURE(n):
    return (3 << 30) | (n << 16) | (ord("H") << 8) | 0x06


class ProfileReader:
    def __init__(self):
        self.fd = None

    def open(self):
        for d in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
            try:
                with open(d + "/device/uevent") as fh:
                    if WOOTING_VENDOR not in fh.read().upper():
                        continue
                with open(d + "/device/report_descriptor", "rb") as fh:
                    if b"\x06\x55\xff" not in fh.read():
                        continue
                self.fd = os.open("/dev/" + os.path.basename(d), os.O_RDWR | os.O_NONBLOCK)
                return True
            except OSError:
                continue
        return False

    def close(self):
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
        self.fd = None

    def active(self):
        """0-3, or None when it cannot be read (unplugged: reopened next time)."""
        if self.fd is None and not self.open():
            return None
        try:
            # Whatever is queued is someone else's -- the SDK's writes, or
            # Wootility's own questions when it is open.
            while select.select([self.fd], [], [], 0)[0]:
                os.read(self.fd, 4096)
            fcntl.ioctl(self.fd, HIDIOCSFEATURE(8), bytearray([1, 0xD1, 0xDA, PROFILE_COMMAND, 0, 0, 0, 0]))
            end = time.monotonic() + 0.5
            while time.monotonic() < end:
                if select.select([self.fd], [], [], 0.05)[0]:
                    r = os.read(self.fd, 4096)
                    if len(r) >= 8 and r[1] == 0xD1 and r[2] == 0xDA and r[3] == PROFILE_COMMAND:
                        return r[7]
        except OSError:
            self.close()
        return None


# ── Commands ─────────────────────────────────────────────────────────────

def connect():
    lib = load_sdk()
    if lib is None:
        return None, "the Wooting RGB SDK is not installed"
    if not lib.wooting_rgb_kbd_connected():
        return None, "no Wooting keyboard found"
    return lib, ""


def cmd_status(lib=None):
    lib, err = (lib, "") if lib else connect()
    if not lib:
        return {"ok": True, "connected": False, "sdk": err != "the Wooting RGB SDK is not installed", "error": err}
    meta = lib.wooting_rgb_device_info().contents
    return {"ok": True, "connected": True, "sdk": True,
            "model": (meta.model or b"").decode(errors="replace")}


def describe(keys):
    # As they should look (sRGB), for the Settings page's picture of the
    # board -- a screen shows them the way the LEDs, gamma-corrected, do.
    return {"ok": True, "keys": {f"{r},{c}": "#%02x%02x%02x" % rgb for (r, c), rgb in keys.items()}}


def cmd_palette(image):
    return describe(for_screen(sample(image)))


def cmd_apply(image, brightness, animate=False, lib=None):
    if not os.path.isfile(image):
        return {"ok": False, "error": "no such image"}
    lib, err = (lib, "") if lib else connect()
    if not lib:
        return {"ok": False, "error": err}
    colours = for_screen(sample(image))
    lib.wooting_rgb_array_auto_update(False)
    if animate:
        sweep(lib, load_last(), colours, brightness)
    for (row, col), rgb in colours.items():
        lib.wooting_rgb_array_set_single(row, col, *for_leds(rgb, brightness))
    if not lib.wooting_rgb_array_update_keyboard():
        return {"ok": False, "error": "the keyboard did not take the colours"}
    save_last(colours)
    return describe(colours)


def cmd_reset(lib=None):
    lib, err = (lib, "") if lib else connect()
    if not lib:
        return {"ok": False, "error": err}
    try:
        os.unlink(LAST)
    except OSError:
        pass
    return {"ok": bool(lib.wooting_rgb_reset_rgb())}


def serve():
    """The long-running form (see `serve` above). Commands that pile up
    while a sweep runs are not played one after another: only the last
    apply is, the wallpaper actually up by then. Between commands, the
    active profile is checked once a second. Leaving on end of input keeps
    the colours on the keys."""
    sdk = load_sdk()
    if sdk is None:
        print(json.dumps({"ok": False, "error": "the Wooting RGB SDK is not installed"}), flush=True)
        return
    fd = sys.stdin.fileno()
    pending = b""
    reader = ProfileReader()
    target = -1                  # the profile to paint on; -1: any
    active = None                # the keyboard's, as last read
    wanted = None                # (image, brightness): what to paint
    painted = False              # whether the keys show it now

    def say(out):
        print(json.dumps(out), flush=True)

    def keyboard():
        # Cheap once connected; after an unplug, finds it again.
        return sdk if sdk.wooting_rgb_kbd_connected() else None

    def ours():
        return target < 0 or active is None or active == target

    def settle(animate):
        """Paint or give the keys back, whichever the profile calls for."""
        nonlocal painted
        lib = keyboard()
        if not lib:
            return {"ok": False, "error": "no Wooting keyboard found"}
        if ours():
            if not wanted:
                return {"ok": True}
            out = cmd_apply(wanted[0], wanted[1], animate, lib)
            painted = out.get("ok", False)
            return out
        if painted:
            lib.wooting_rgb_reset_rgb()
            painted = False
        return {"ok": True, "skipped": "profile"}

    def lines(timeout):
        nonlocal pending
        while b"\n" not in pending:
            ready, _, _ = select.select([fd], [], [], timeout)
            if not ready:
                return None
            chunk = os.read(fd, 65536)
            if not chunk:
                raise EOFError
            pending += chunk
        line, pending = pending.split(b"\n", 1)
        return line

    while True:
        try:
            first = lines(1.0)
            batch = [first] if first is not None else []
            while batch:
                more = lines(0)
                if more is None:
                    break
                batch.append(more)
        except EOFError:
            reader.close()
            return

        # Once a second (or after commands): has the profile changed?
        now = reader.active()
        if now is not None and now != active:
            before = ours()
            active = now
            say({"cmd": "profile", "active": active})
            if ours() != before or (ours() and not painted):
                settle(animate=True)

        commands = []
        for raw in batch:
            try:
                commands.append(json.loads(raw))
            except ValueError:
                continue
        last_apply = max((i for i, c in enumerate(commands) if c.get("cmd") == "apply"), default=-1)
        for i, c in enumerate(commands):
            cmd = c.get("cmd")
            if cmd == "apply" and i != last_apply:
                continue
            try:
                if cmd == "status":
                    lib = keyboard()
                    out = cmd_status(lib) if lib else {"ok": True, "connected": False, "sdk": True,
                                                       "error": "no Wooting keyboard found"}
                    out["active"] = active
                elif cmd == "apply":
                    b = max(10, min(100, int(c.get("brightness", 100))))
                    wanted = (os.path.expanduser(c.get("image", "")), b)
                    out = settle(bool(c.get("animate")))
                elif cmd == "target":
                    target = int(c.get("profile", -1))
                    out = settle(animate=True)
                elif cmd == "reset":
                    wanted = None
                    lib = keyboard()
                    out = cmd_reset(lib) if lib else {"ok": False, "error": "no Wooting keyboard found"}
                    painted = False
                else:
                    out = {"ok": False, "error": f"unknown command {cmd}"}
            except (OSError, ValueError) as e:
                out = {"ok": False, "error": str(e)}
            out["cmd"] = cmd
            say(out)


def main():
    a = sys.argv[1:]
    try:
        if a[:1] == ["apply"] and len(a) >= 2:
            animate = "--animate" in a
            a = [x for x in a if x != "--animate"]
            b = max(10, min(100, int(float(a[2])))) if len(a) > 2 else 100
            out = cmd_apply(os.path.expanduser(a[1]), b, animate)
        elif a[:1] == ["palette"] and len(a) == 2:
            out = cmd_palette(os.path.expanduser(a[1]))
        elif a == ["reset"]:
            out = cmd_reset()
        elif a in ([], ["status"]):
            out = cmd_status()
        elif a == ["profile"]:
            n = ProfileReader().active()
            out = {"ok": n is not None, "active": n}
        elif a == ["serve"]:
            serve()
            return
        else:
            sys.exit(__doc__)
    except (OSError, ValueError) as e:
        out = {"ok": False, "error": str(e)}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
