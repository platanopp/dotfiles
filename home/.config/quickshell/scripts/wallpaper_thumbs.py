#!/usr/bin/env python3
"""Thumbnail cache for the wallpaper carousel.

The carousel keeps about a dozen panels alive at once, and every one of them
was decoding its full-size original: a 7680x4320 PNG costs ~380ms on its own,
and the whole folder is two seconds of decoding. Qt's sourceSize caps the
*output*, not the work -- the file is still read and decoded in full before it
is scaled down. So the panels sat on their placeholder long enough to read as
a black gap.

These are small JPEGs at carousel height. Decoding one is a few milliseconds.

Only the carousel uses them; the framing editor still opens the original,
because that view is for judging a crop and wants every pixel it can get.

  build [DIR]   generate what is missing, print JSON {original: thumbnail}
  clean         drop thumbnails whose source is gone
"""

import hashlib
import json
import os
import sys

from PIL import Image

CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "quickshell", "wallpaper-thumbs",
)
WALLPAPERS = os.path.expanduser("~/Pictures/Wallpapers")
# panelHeight caps at 520; 560 leaves a little headroom without paying for
# pixels nothing samples. The parallax widens the image, it does not raise it,
# so height is the only dimension that has to cover the panel.
HEIGHT = 560
QUALITY = 88
EXTS = (".jpg", ".jpeg", ".png", ".webp")


def key_for(path):
    """Keyed on identity *and* mtime+size, so replacing a file in place gets a
    fresh thumbnail instead of the stale one under the same name."""
    st = os.stat(path)
    h = hashlib.sha1(f"{path}:{st.st_mtime_ns}:{st.st_size}:{HEIGHT}".encode())
    return h.hexdigest() + ".jpg"


def build(directory):
    os.makedirs(CACHE, exist_ok=True)
    out = {}
    for name in sorted(os.listdir(directory)):
        src = os.path.join(directory, name)
        if not name.lower().endswith(EXTS) or not os.path.isfile(src):
            continue
        try:
            dst = os.path.join(CACHE, key_for(src))
        except OSError:
            continue
        if not os.path.exists(dst):
            try:
                im = Image.open(src)
                # draft() lets the JPEG decoder skip straight to a smaller
                # scale instead of unpacking full resolution first. A no-op on
                # PNG, which is why PNGs stay the slow case even here -- but
                # this runs once per file, not on every open.
                im.draft("RGB", (HEIGHT * 4, HEIGHT * 4))
                im = im.convert("RGB")
                w = max(1, round(im.width * HEIGHT / im.height))
                im = im.resize((w, HEIGHT), Image.LANCZOS)
                im.save(dst, "JPEG", quality=QUALITY, optimize=True)
            except Exception:
                continue          # unreadable file: fall back to the original
        out[src] = dst
    return out


def clean(valid):
    if not os.path.isdir(CACHE):
        return 0
    keep = set(os.path.basename(v) for v in valid.values())
    n = 0
    for f in os.listdir(CACHE):
        if f not in keep:
            try:
                os.unlink(os.path.join(CACHE, f)); n += 1
            except OSError:
                pass
    return n


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "build"
    directory = sys.argv[2] if len(sys.argv) > 2 else WALLPAPERS
    if cmd == "build":
        m = build(directory)
        clean(m)                  # keyed on mtime, so old entries pile up
        print(json.dumps(m))
    elif cmd == "clean":
        print(clean(build(directory)))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
