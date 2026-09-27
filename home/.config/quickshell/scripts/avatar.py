#!/usr/bin/env python3
"""The logged-in user's picture: ~/.face, the file greeters, lock screens and
this shell look for first.

  set PATH   crop PATH to a centred square, scale it to 512 px and write it
             as ~/.face (PNG). The original is never touched.
  remove     delete ~/.face; the shell falls back to the user's initial.

Prints {"ok": true, "path": ...} or {"ok": false, "error": ...}.
"""

import json
import os
import sys

HOME = os.path.expanduser("~")
FACE = os.path.join(HOME, ".face")
SIZE = 512


def set_face(src):
    try:
        from PIL import Image, ImageOps
    except ImportError:
        return {"ok": False, "error": "python-pillow is not installed"}
    try:
        with Image.open(src) as im:
            im = ImageOps.exif_transpose(im)
            im = ImageOps.fit(im.convert("RGBA"), (SIZE, SIZE), Image.LANCZOS)
            tmp = FACE + ".tmp"
            im.save(tmp, "PNG")
        os.replace(tmp, FACE)
    except OSError as e:
        return {"ok": False, "error": f"cannot read that image ({e.__class__.__name__})"}
    return {"ok": True, "path": FACE}


def remove_face():
    try:
        os.unlink(FACE)
    except FileNotFoundError:
        pass
    except OSError as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "path": ""}


def main():
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "set":
        out = set_face(os.path.expanduser(a[1]))
    elif a == ["remove"]:
        out = remove_face()
    else:
        sys.exit(__doc__)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
