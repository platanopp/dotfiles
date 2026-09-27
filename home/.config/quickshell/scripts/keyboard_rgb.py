#!/usr/bin/env python3
"""Light RGB keyboards with the wallpaper itself: the whole picture laid over
each board, every LED lit with the colour of the part of the picture under it.

Two ways to a keyboard:

  Wooting    through Wooting's RGB SDK (libwooting-rgb-sdk.so, in ~/.local/lib
             or the system's lib), with the 60% board's real key sizes, and
             the keyboard's profiles: it can be painted on one profile only.
             The SDK paints over the active profile without changing it; the
             profile's own colours come back on `reset`, a profile switch, or
             unplugging it. wooting_rgb_close() is never called: it would
             reset the colours on the way out.

  OpenRGB    any keyboard OpenRGB supports (Razer, Corsair, Logitech,
             SteelSeries, HyperX, ASUS, ...), through a running OpenRGB server
             (`openrgb --server`, port 6742), spoken to directly over its SDK
             protocol -- no Python package needed. A keyboard's zones become
             places on the picture: a per-key matrix is laid over it like the
             Wooting, a strip of LEDs runs across it left to right, a
             single-colour zone takes the picture's dominant colour. A Wooting
             that OpenRGB also lists is left to its own SDK.

  apply IMAGE [BRIGHTNESS] [--animate]
                             paint from IMAGE; BRIGHTNESS 10-100 (default
                             100). --animate sweeps from the colours last
                             sent to the new ones instead of switching.
  palette IMAGE              JSON: the colour of every key of the 60% board,
                             without touching any keyboard (Settings' preview)
  reset                      back to each keyboard's own colours
  status                     JSON: the keyboards found, and how each is lit
  profile                    JSON: the Wooting's active profile (0-3)
  serve                      stay connected and take commands on stdin, one
                             JSON object a line -- {"cmd": "apply", "image",
                             "brightness", "animate"}, {"cmd": "reset"},
                             {"cmd": "status"}, {"cmd": "target", "profile":
                             N} (paint the Wooting only on profile N; -1 any)
                             -- answering each on stdout. What the shell runs:
                             finding a Wooting costs two seconds, paid once.
                             The Wooting's profile is watched and reported as
                             {"cmd": "profile", "active": N}; keyboards coming
                             and going are picked up, and reported as
                             {"cmd": "devices", "devices": [...]}.

Prints JSON: {"ok": true, ...} or {"ok": false, "error": ...}.
"""

import colorsys
import ctypes
import fcntl
import glob
import json
import os
import select
import socket
import struct
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

# The colours last sent (sRGB, full brightness), per keyboard, for the next
# sweep to start from. A cache, not a setting: without it a sweep starts
# from dark.
LAST = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                    "quickshell", "keyboard-rgb.json")


# ── The picture, place by place ──────────────────────────────────────────
#
# Every keyboard describes its LEDs the same way: {led id: (x0, y0, x1, y1)},
# a rectangle on the picture in fractions of its width and height. What
# follows does not care which keyboard it is.

def sample(image_path, spots):
    """{led: (h, l, s)}: the colour of the picture under each place. The
    whole picture is fitted to a board, not cropped -- squeezed from 16:9 to
    about 3:1, which LEDs a key apart cannot tell.

    Not the mean of what is under a key: half white hair and half blue sky
    average to a grey-blue that is nowhere in the picture. The patch is
    split into its few main colours and the one that dominates it is used,
    a vivid one counting for more -- so a key over a red eye can be red."""
    from PIL import Image
    W, H = 480, 160
    with Image.open(image_path) as im:
        im = im.convert("RGB")
        im = im.resize((W, H), Image.LANCZOS)
    out = {}
    for led, (x0, y0, x1, y1) in spots.items():
        box = (int(x0 * W), int(y0 * H), max(int(x0 * W) + 1, int(x1 * W)), max(int(y0 * H) + 1, int(y1 * H)))
        patch = im.crop(box)
        q = patch.quantize(colors=4, method=Image.Quantize.MEDIANCUT)
        pal = q.getpalette()
        best, best_score = (0.0, 0.5, 0.0), -1.0
        total = patch.width * patch.height
        for count, idx in q.getcolors():
            rgb = tuple(pal[idx * 3: idx * 3 + 3])
            h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
            # Share of the patch, then vividness: a colour needs about a
            # fifth of a key to win over a duller one covering the rest.
            score = (count / total) * (0.35 + s * (1 - abs(l - 0.5) * 1.2))
            if score > best_score:
                best, best_score = (h, l, s), score
        out[led] = best
    return out


def percentile(values, p):
    v = sorted(values)
    return v[min(len(v) - 1, int(p * len(v)))]


def for_screen(keys):
    """The colours as they should look -- in sRGB, like the screen. A dark
    part of the picture on a key reads as a key switched off, so lightness
    is lifted into the band LEDs show well; only gently stretched, and by
    percentiles, so one bright key does not dim all the others."""
    if not keys:
        return {}
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
    return tuple(int(round(((v / 255) ** 1.8) * 255 * k)) for v in rgb)


def linear(rgb):
    return tuple(v / 255 for v in for_leds(rgb, 100))


def sweep(devices, old, new, brightness, duration=1.4):
    """A slanted front crosses every board left to right at once. Behind it
    keys have turned to the new colours; on it they flare, lit brighter in
    the new colour; ahead of it they keep the old ones. Mixed in linear
    light, the way two lights actually add. Driven by the clock, not a frame
    count: a frame costs about 32 ms on a 60HE, so each board shows as many
    as it can take and the sweep lasts `duration` either way."""
    k = brightness / 100
    plan = []
    for dev in devices:
        spots = dev.spots()
        colours = new.get(dev.key, {})
        before = old.get(dev.key, {})
        leds = []
        for led, (x0, y0, x1, y1) in spots.items():
            if led not in colours:
                continue
            # In key units, like the 60% board: 15 across, 5 down.
            pos = (x0 + x1) / 2 * UNITS + (y0 + y1) / 2 * 5 * 0.7
            leds.append((led, pos, linear(before.get(led, (0, 0, 0))), linear(colours[led])))
        plan.append((dev, leds))
    width = 2.2
    start, end = -width - 3, UNITS + 3.5 + width + 1
    t0 = time.monotonic()
    while True:
        p = min(1.0, (time.monotonic() - t0) / duration)
        p = p * p * (3 - 2 * p) * 0.35 + p * 0.65      # eases in and out a little
        front = start + (end - start) * p
        for dev, leds in plan:
            frame = {}
            for led, pos, a, b in leds:
                u = max(0.0, min(1.0, (front - pos) / width))
                u = u * u * (3 - 2 * u)
                flare = max(0.0, 1 - abs(front - pos - width * 0.5) / 1.4)
                c = [a[i] + (b[i] - a[i]) * u for i in range(3)]
                c = [min(1.0, v + flare * (0.55 * b[i] + 0.25)) for i, v in enumerate(c)]
                frame[led] = tuple(int(round(v * 255 * k)) for v in c)
            try:
                dev.show(frame)
            except OSError:
                pass
        if front >= end:
            break


def load_last():
    try:
        with open(LAST) as fh:
            data = json.load(fh)
        if not isinstance(data, dict) or not all(isinstance(v, dict) for v in data.values()):
            return {}          # the old, Wooting-only format: start from dark
        return {dev: {Device.parse_id(k): tuple(v) for k, v in leds.items()} for dev, leds in data.items()}
    except (OSError, ValueError):
        return {}


def save_last(colours):
    try:
        os.makedirs(os.path.dirname(LAST), exist_ok=True)
        with open(LAST, "w") as fh:
            json.dump({dev: {Device.format_id(k): list(v) for k, v in leds.items()}
                       for dev, leds in colours.items()}, fh)
    except OSError:
        pass


class Device:
    """One keyboard. `spots()` says where its LEDs sit on the picture;
    `show()` sends {led: (r, g, b)} ready for the LEDs; `restore()` gives
    the keyboard its own lighting back."""
    key = ""
    name = ""
    kind = ""
    shape = ""

    @staticmethod
    def format_id(led):
        return ",".join(str(p) for p in led) if isinstance(led, tuple) else str(led)

    @staticmethod
    def parse_id(text):
        parts = text.split(",")
        return tuple(int(p) for p in parts) if len(parts) > 1 else int(parts[0])

    def info(self):
        return {"key": self.key, "name": self.name, "kind": self.kind, "shape": self.shape,
                "leds": len(self.spots())}


# ── Wooting ──────────────────────────────────────────────────────────────

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


def wooting_spots():
    out = {}
    for r, row in enumerate(LAYOUT):
        x = 0.0
        for width, col in row:
            out[(r + 1, col)] = (x / UNITS, r / len(LAYOUT), (x + width) / UNITS, (r + 1) / len(LAYOUT))
            x += width
    return out


class Wooting(Device):
    kind = "wooting"
    shape = "per-key"

    def __init__(self, lib):
        self.lib = lib
        meta = lib.wooting_rgb_device_info().contents
        self.name = (meta.model or b"Wooting").decode(errors="replace")
        self.key = "wooting"
        self._spots = wooting_spots()
        lib.wooting_rgb_array_auto_update(False)

    def spots(self):
        return self._spots

    def show(self, frame):
        for (row, col), (r, g, b) in frame.items():
            self.lib.wooting_rgb_array_set_single(row, col, r, g, b)
        if not self.lib.wooting_rgb_array_update_keyboard():
            raise OSError("the Wooting did not take the colours")

    def restore(self):
        self.lib.wooting_rgb_reset_rgb()


# ── OpenRGB ──────────────────────────────────────────────────────────────
#
# The SDK protocol, the few packets used here: a 16-byte header ("ORGB",
# device index, packet id, data size -- little-endian) and a body. Protocol
# version 3 is asked for: every server since 0.6 speaks it, and its device
# description has no segments or later extras to parse.

ORGB_PORT = 6742
ORGB_PROTOCOL = 3
PKT_CONTROLLER_COUNT = 0
PKT_CONTROLLER_DATA = 1
PKT_PROTOCOL_VERSION = 40
PKT_CLIENT_NAME = 50
PKT_DEVICE_LIST_UPDATED = 100
PKT_UPDATE_LEDS = 1050
PKT_SET_CUSTOM_MODE = 1100
DEVICE_KEYBOARD = 5
ZONE_SINGLE, ZONE_LINEAR, ZONE_MATRIX = 0, 1, 2
NO_LED = 0xFFFFFFFF


class Reader:
    def __init__(self, data):
        self.d, self.i = data, 0

    def take(self, fmt):
        v = struct.unpack_from("<" + fmt, self.d, self.i)
        self.i += struct.calcsize("<" + fmt)
        return v if len(v) > 1 else v[0]

    def string(self):
        n = self.take("H")
        s = self.d[self.i:self.i + n].rstrip(b"\0").decode(errors="replace")
        self.i += n
        return s


class OpenRGB:
    def __init__(self, host="127.0.0.1", port=ORGB_PORT):
        self.sock = socket.create_connection((host, port), timeout=2)
        self.buffer = b""
        self.list_changed = False
        self.send(0, PKT_CLIENT_NAME, b"quickshell keyboard_rgb\0")
        self.send(0, PKT_PROTOCOL_VERSION, struct.pack("<I", ORGB_PROTOCOL))
        server = struct.unpack("<I", self.receive(PKT_PROTOCOL_VERSION)[:4])[0]
        self.protocol = min(ORGB_PROTOCOL, server)

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def send(self, dev, pkt, data=b""):
        self.sock.sendall(b"ORGB" + struct.pack("<III", dev, pkt, len(data)) + data)

    def receive(self, want):
        """The body of the next packet `want`; the server's unprompted
        "device list updated" notes are remembered on the way."""
        while True:
            while len(self.buffer) < 16:
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise OSError("the OpenRGB server went away")
                self.buffer += chunk
            magic, dev, pkt, size = struct.unpack("<4sIII", self.buffer[:16])
            if magic != b"ORGB":
                raise OSError("not an OpenRGB server")
            while len(self.buffer) < 16 + size:
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise OSError("the OpenRGB server went away")
                self.buffer += chunk
            body, self.buffer = self.buffer[16:16 + size], self.buffer[16 + size:]
            if pkt == PKT_DEVICE_LIST_UPDATED:
                self.list_changed = True
                continue
            if pkt == want:
                return body

    def count(self):
        self.send(0, PKT_CONTROLLER_COUNT)
        return struct.unpack("<I", self.receive(PKT_CONTROLLER_COUNT)[:4])[0]

    def controller(self, index):
        """(type, name, vendor, [zones], led count); each zone is
        (name, type, leds, matrix (h, w, [map]) or None)."""
        self.send(index, PKT_CONTROLLER_DATA, struct.pack("<I", self.protocol))
        r = Reader(self.receive(PKT_CONTROLLER_DATA))
        r.take("I")                                    # data size
        dev_type = r.take("i")
        name = r.string()
        vendor = r.string() if self.protocol >= 1 else ""
        for _ in range(4):                             # description, version, serial, location
            r.string()
        modes = r.take("H")
        r.take("i")                                    # active mode
        for _ in range(modes):
            r.string()
            r.take("i"); r.take("I")                   # value, flags
            r.take("I"); r.take("I")                   # speed min, max
            if self.protocol >= 3:
                r.take("I"); r.take("I")               # brightness min, max
            r.take("I"); r.take("I")                   # colours min, max
            r.take("I")                                # speed
            if self.protocol >= 3:
                r.take("I")                            # brightness
            r.take("I"); r.take("I")                   # direction, colour mode
            n = r.take("H")                            # its colours: skipped. Read
            r.i += 4 * n                               # first -- `r.i += 4 * take()`
                                                       # would add to the old r.i
        zones = []
        for _ in range(r.take("H")):
            zname = r.string()
            ztype = r.take("i")
            r.take("I"); r.take("I")                   # leds min, max
            leds = r.take("I")
            matrix = None
            if r.take("H") > 0:
                h, w = r.take("I"), r.take("I")
                cells = list(struct.unpack_from("<%dI" % (h * w), r.d, r.i))
                r.i += 4 * h * w
                matrix = (h, w, cells)
            if self.protocol >= 4:
                for _ in range(r.take("H")):           # segments (not asked for)
                    r.string(); r.take("i"); r.take("I"); r.take("I")
            zones.append((zname, ztype, leds, matrix))
        total = r.take("H")
        return dev_type, name, vendor, zones, total

    def custom_mode(self, index):
        self.send(index, PKT_SET_CUSTOM_MODE)

    def update(self, index, colours):
        body = struct.pack("<H", len(colours)) + b"".join(struct.pack("<BBBx", *c) for c in colours)
        self.send(index, PKT_UPDATE_LEDS, struct.pack("<I", len(body) + 4) + body)


class OpenRGBKeyboard(Device):
    kind = "openrgb"

    def __init__(self, client, index, name, vendor, zones, total):
        self.client, self.index = client, index
        self.name = name
        self.key = "openrgb:" + name
        self.total = total
        self._spots = {}
        start = 0
        shapes = set()
        for zname, ztype, leds, matrix in zones:
            if matrix:
                h, w, cells = matrix
                shapes.add("per-key")
                for r in range(h):
                    for c in range(w):
                        led = cells[r * w + c]
                        if led != NO_LED and led < leds:
                            self._spots.setdefault(start + led, (c / w, r / h, (c + 1) / w, (r + 1) / h))
            elif ztype == ZONE_LINEAR and leds > 1:
                shapes.add("zones")
                for i in range(leds):
                    self._spots[start + i] = (i / leds, 0.3, (i + 1) / leds, 0.7)
            else:
                shapes.add("single" if leds <= 1 else "zones")
                for i in range(leds):
                    # A zone that cannot say where its LEDs are: the picture's
                    # colour as a whole.
                    self._spots[start + i] = (0.0, 0.0, 1.0, 1.0)
            start += leds
        self.shape = "per-key" if "per-key" in shapes else "zones" if "zones" in shapes else "single"
        self.frame = [(0, 0, 0)] * total
        client.custom_mode(index)

    def spots(self):
        return self._spots

    def show(self, frame):
        for led, rgb in frame.items():
            if 0 <= led < self.total:
                self.frame[led] = rgb
        self.client.update(self.index, self.frame)

    def restore(self):
        # OpenRGB has no "give it back": the keyboard keeps the last colours
        # until its own software or a profile sets it again. Dark is the
        # honest thing to leave rather than a stale wallpaper.
        self.frame = [(0, 0, 0)] * self.total
        self.client.update(self.index, self.frame)


# ── Finding keyboards ────────────────────────────────────────────────────

class Keyboards:
    """Every keyboard that can be lit right now, found again when one comes
    or goes. The Wooting through its SDK; the rest through OpenRGB when a
    server is running."""

    def __init__(self):
        self.sdk = load_sdk()
        self.wooting = None
        self.orgb = None
        self.orgb_devices = []
        self.last_scan = 0.0

    def devices(self):
        return ([self.wooting] if self.wooting else []) + self.orgb_devices

    def scan(self, force=False):
        """Returns True when the set of keyboards changed."""
        before = [d.key for d in self.devices()]
        # Wooting: cheap once connected; after an unplug, finds it again.
        if self.sdk and self.sdk.wooting_rgb_kbd_connected():
            if not self.wooting:
                self.wooting = Wooting(self.sdk)
        else:
            self.wooting = None
        # OpenRGB: every few seconds, or when the server says the list moved.
        now = time.monotonic()
        if force or now - self.last_scan > 5 or (self.orgb and self.orgb.list_changed):
            self.last_scan = now
            self.scan_openrgb()
        return before != [d.key for d in self.devices()]

    def scan_openrgb(self):
        try:
            if not self.orgb:
                self.orgb = OpenRGB()
            self.orgb.list_changed = False
            found = []
            for i in range(self.orgb.count()):
                dev_type, name, vendor, zones, total = self.orgb.controller(i)
                if dev_type != DEVICE_KEYBOARD or total == 0:
                    continue
                if self.wooting and "wooting" in (name + " " + vendor).lower():
                    continue               # its own SDK has it
                found.append(OpenRGBKeyboard(self.orgb, i, name, vendor, zones, total))
            self.orgb_devices = found
        except (OSError, struct.error):
            if self.orgb:
                self.orgb.close()
            self.orgb = None
            self.orgb_devices = []

    def status(self):
        return {"ok": True, "connected": bool(self.devices()),
                "sdk": self.sdk is not None,
                "openrgb": self.orgb is not None,
                "model": self.wooting.name if self.wooting else (self.orgb_devices[0].name if self.orgb_devices else ""),
                "devices": [d.info() for d in self.devices()]}


# ── The active profile (Wooting) ─────────────────────────────────────────
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


# ── Painting ─────────────────────────────────────────────────────────────

def paint(devices, image, brightness, animate=False):
    """Every keyboard in `devices` from `image`. Returns the 60% board's
    colours (Settings' preview) and the per-keyboard errors, if any."""
    if not os.path.isfile(image):
        return {"ok": False, "error": "no such image"}
    if not devices:
        return {"ok": False, "error": "no RGB keyboard found"}
    colours = {d.key: for_screen(sample(image, d.spots())) for d in devices}
    if animate:
        sweep(devices, load_last(), colours, brightness)
    errors = []
    for d in devices:
        try:
            d.show({led: for_leds(rgb, brightness) for led, rgb in colours[d.key].items()})
        except OSError as e:
            errors.append(f"{d.name}: {e}")
    last = load_last()
    last.update(colours)
    save_last(last)
    out = describe(for_screen(sample(image, wooting_spots())))
    if errors:
        out["ok"] = len(errors) < len(devices)
        out["error"] = "; ".join(errors)
    return out


def describe(keys):
    # As they should look (sRGB), for the Settings page's picture of the
    # board -- a screen shows them the way the LEDs, gamma-corrected, do.
    return {"ok": True, "keys": {f"{r},{c}": "#%02x%02x%02x" % rgb for (r, c), rgb in keys.items()}}


def serve():
    """The long-running form (see `serve` above). Commands that pile up
    while a sweep runs are not played one after another: only the last
    apply is, the wallpaper actually up by then. Between commands, once a
    second, the Wooting's profile is read and the keyboards are recounted.
    Leaving on end of input keeps the colours on the keys."""
    boards = Keyboards()
    fd = sys.stdin.fileno()
    pending = b""
    reader = ProfileReader()
    target = -1                  # the Wooting profile to paint on; -1: any
    active = None                # the Wooting's, as last read
    wanted = None                # (image, brightness): what to paint
    painted = set()              # keys of the keyboards showing it now

    def say(out):
        print(json.dumps(out), flush=True)

    def wooting_ours():
        return target < 0 or active is None or active == target

    def eligible():
        return [d for d in boards.devices() if d.kind != "wooting" or wooting_ours()]

    def settle(animate, only=None):
        """Paint what should show the wallpaper, give the rest back."""
        out = {"ok": True}
        todo = [d for d in eligible() if only is None or d.key in only]
        if wanted and todo:
            out = paint(todo, wanted[0], wanted[1], animate)
            if out.get("ok"):
                painted.update(d.key for d in todo)
        elif not boards.devices():
            out = {"ok": False, "error": "no RGB keyboard found"}
        # A Wooting on another profile gets its profile's colours back.
        if boards.wooting and not wooting_ours() and "wooting" in painted:
            boards.wooting.restore()
            painted.discard("wooting")
            out.setdefault("skipped", "profile")
        return out

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

    boards.scan(force=True)
    say({"cmd": "devices", "devices": [d.info() for d in boards.devices()]})

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

        # Keyboards plugged in or out: the new ones get the wallpaper.
        before = {d.key for d in boards.devices()}
        if boards.scan():
            now_keys = {d.key for d in boards.devices()}
            painted.intersection_update(now_keys)
            say({"cmd": "devices", "devices": [d.info() for d in boards.devices()]})
            if wanted and now_keys - before:
                settle(animate=True, only=now_keys - before)

        # The Wooting's profile: has it changed?
        if boards.wooting:
            now = reader.active()
            if now is not None and now != active:
                was = wooting_ours()
                active = now
                say({"cmd": "profile", "active": active})
                if wooting_ours() != was or (wooting_ours() and "wooting" not in painted):
                    settle(animate=True, only={"wooting"})

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
                    boards.scan(force=True)
                    out = boards.status()
                    out["active"] = active
                elif cmd == "apply":
                    b = max(10, min(100, int(c.get("brightness", 100))))
                    wanted = (os.path.expanduser(c.get("image", "")), b)
                    out = settle(bool(c.get("animate")))
                elif cmd == "target":
                    target = int(c.get("profile", -1))
                    out = settle(animate=True, only={"wooting"})
                elif cmd == "reset":
                    wanted = None
                    for d in boards.devices():
                        d.restore()
                    painted.clear()
                    try:
                        os.unlink(LAST)
                    except OSError:
                        pass
                    out = {"ok": True}
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
            boards = Keyboards()
            boards.scan(force=True)
            out = paint(boards.devices(), os.path.expanduser(a[1]), b, animate)
        elif a[:1] == ["palette"] and len(a) == 2:
            out = describe(for_screen(sample(os.path.expanduser(a[1]), wooting_spots())))
        elif a == ["reset"]:
            boards = Keyboards()
            boards.scan(force=True)
            for d in boards.devices():
                d.restore()
            out = {"ok": True, "devices": [d.info() for d in boards.devices()]}
        elif a in ([], ["status"]):
            boards = Keyboards()
            boards.scan(force=True)
            out = boards.status()
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
