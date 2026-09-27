#!/usr/bin/env python3
"""The logged-in user's picture: ~/.face, the file greeters, lock screens and
this shell look for first.

~/.face is a square crop. So that it can be framed again later -- zoomed
back out, moved -- the picture it was cut from is kept beside the shell's
data (a copy: the original is never touched), with the framing used.

  set PATH [ZOOM X Y]   frame PATH and write ~/.face (512 px PNG). ZOOM 1 is
                        the largest square the picture holds, 2 half that
                        side; X, Y the square's centre as fractions of the
                        picture's width and height. Default: 1, centred.
  adjust ZOOM X Y       frame the kept picture again
  source                JSON: the picture to frame and the framing in use
                        -- the kept copy, or ~/.face itself when there is
                        none (a picture set elsewhere)
  remove                delete ~/.face and the kept copy; the shell falls
                        back to the user's initial

Prints {"ok": true, ...} or {"ok": false, "error": ...}.
"""

import json
import os
import sys

HOME = os.path.expanduser("~")
FACE = os.path.join(HOME, ".face")
DATA = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.join(HOME, ".local/share")), "quickshell")
SOURCE = os.path.join(DATA, "avatar-source.png")
FRAMING = os.path.join(DATA, "avatar-framing.json")
SIZE = 512
# The kept copy is only ever cropped to a 512 px square, so a 12 MP photo
# need not be kept whole.
SOURCE_MAX = 2048


def pil():
    try:
        from PIL import Image, ImageOps
        return Image, ImageOps
    except ImportError:
        return None, None


def frame(im, zoom, x, y):
    """The square of `im` for this framing, kept inside the picture."""
    w, h = im.size
    side = min(w, h) / max(1.0, zoom)
    cx = min(max(x * w, side / 2), w - side / 2)
    cy = min(max(y * h, side / 2), h - side / 2)
    return (round(cx - side / 2), round(cy - side / 2), round(cx + side / 2), round(cy + side / 2))


def write_face(im, zoom, x, y):
    Image, _ = pil()
    face = im.crop(frame(im, zoom, x, y)).resize((SIZE, SIZE), Image.LANCZOS)
    tmp = FACE + ".tmp"
    face.save(tmp, "PNG")
    os.replace(tmp, FACE)
    os.makedirs(DATA, exist_ok=True)
    with open(FRAMING, "w") as fh:
        json.dump({"zoom": zoom, "x": x, "y": y}, fh)


def set_face(src, zoom=1.0, x=0.5, y=0.5):
    Image, ImageOps = pil()
    if Image is None:
        return {"ok": False, "error": "python-pillow is not installed"}
    try:
        with Image.open(src) as im:
            im = ImageOps.exif_transpose(im).convert("RGBA")
        im.thumbnail((SOURCE_MAX, SOURCE_MAX), Image.LANCZOS)
        os.makedirs(DATA, exist_ok=True)
        tmp = SOURCE + ".tmp"
        im.save(tmp, "PNG")
        os.replace(tmp, SOURCE)
        write_face(im, zoom, x, y)
    except OSError as e:
        return {"ok": False, "error": f"cannot read that image ({e.__class__.__name__})"}
    return {"ok": True, "path": FACE}


def adjust(zoom, x, y):
    Image, _ = pil()
    if Image is None:
        return {"ok": False, "error": "python-pillow is not installed"}
    path = SOURCE if os.path.isfile(SOURCE) else FACE
    try:
        with Image.open(path) as im:
            im = im.convert("RGBA")
        if path == FACE:
            # No kept picture: the current one becomes it, so this and the
            # next adjustment start from the same thing.
            os.makedirs(DATA, exist_ok=True)
            im.save(SOURCE, "PNG")
        write_face(im, zoom, x, y)
    except OSError as e:
        return {"ok": False, "error": f"cannot read the picture ({e.__class__.__name__})"}
    return {"ok": True, "path": FACE}


def source():
    framing = {"zoom": 1.0, "x": 0.5, "y": 0.5}
    if os.path.isfile(SOURCE):
        try:
            with open(FRAMING) as fh:
                framing.update(json.load(fh))
        except (OSError, ValueError):
            pass
        return {"ok": True, "path": SOURCE, **framing}
    if os.path.isfile(FACE):
        return {"ok": True, "path": FACE, **framing}
    return {"ok": True, "path": ""}


def remove_face():
    for p in (FACE, SOURCE, FRAMING):
        try:
            os.unlink(p)
        except FileNotFoundError:
            pass
        except OSError as e:
            return {"ok": False, "error": str(e)}
    return {"ok": True, "path": ""}


def numbers(args):
    zoom, x, y = (float(a) for a in args)
    return max(1.0, min(8.0, zoom)), max(0.0, min(1.0, x)), max(0.0, min(1.0, y))


def main():
    a = sys.argv[1:]
    try:
        if len(a) in (2, 5) and a[0] == "set":
            out = set_face(os.path.expanduser(a[1]), *(numbers(a[2:]) if len(a) == 5 else ()))
        elif len(a) == 4 and a[0] == "adjust":
            out = adjust(*numbers(a[1:]))
        elif a == ["source"]:
            out = source()
        elif a == ["remove"]:
            out = remove_face()
        else:
            sys.exit(__doc__)
    except ValueError as e:
        out = {"ok": False, "error": str(e)}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
