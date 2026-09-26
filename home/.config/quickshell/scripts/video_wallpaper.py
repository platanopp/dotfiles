#!/usr/bin/env python3
"""Video wallpapers: the list, the thumbnails, and the mpvpaper behind them.

Videos live in the same folder as the images, ~/Pictures/Wallpapers, and the
picker shows them in their own section. Playing one is mpvpaper's job; this
script owns starting and stopping it, and remembering which video is up so a
new session comes back to it.

  list      JSON {"videos": [{path, thumb, poster}], "current": path or ""}
  apply P   play video P on every screen, and remember it
  stop      stop the video wallpaper, and forget it
  restore   start the remembered video if it is not already playing
  current   the remembered video, or nothing

Two frames are cut from each video, once, keyed on path, mtime and size:

  thumb     carousel height, for the picker -- decoding a video to show a
            still in a panel is wasted work, and ffmpeg is too slow to run
            every time the picker opens
  poster    full size, for the lock screen, which draws a blurred still of
            the wallpaper and has no business playing a video behind a
            password field
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
WALLPAPERS = os.path.join(HOME, "Pictures", "Wallpapers")
CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")),
    "quickshell", "video-thumbs",
)
STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")),
    "quickshell",
)
STATE = os.path.join(STATE_DIR, "video-wallpaper")
LOG = os.path.join(STATE_DIR, "mpvpaper.log")

EXTS = (".mp4", ".webm", ".mkv", ".mov")
# Same as the image thumbnails in wallpaper_thumbs.py, so a video panel and a
# picture panel decode at the same cost.
THUMB_HEIGHT = 560

# What mpv is told, and why each one is there:
#
#   no-audio         a wallpaper that makes noise is a bug
#   loop-file=inf    wallpaper videos are short loops; stopping on the last
#                    frame would leave a still that looks like a hang
#   hwdec=auto-safe  decode on the GPU (NVDEC here) instead of the CPU
#   panscan=1.0      cover the screen, cropping what does not fit, the same
#                    way the image wallpapers are framed -- no black bars
#   quiet            no status line. mpv redraws "V: 00:00:02 / 00:00:10"
#                    several times a second, and with nobody at a terminal
#                    that lands in the log file and grows it for as long as
#                    the wallpaper plays. Warnings and errors still get there.
MPV_OPTIONS = "no-audio loop-file=inf hwdec=auto-safe panscan=1.0 quiet"

# And mpvpaper itself:
#
#   --auto-pause --auto-mode FULL
#       pause while any window is fullscreen. A game covering the screen has
#       no use for a video being decoded behind it, and osu! wants every frame
#       of GPU time it can get.
#   --layer bottom
#       above hyprpaper's background layer and below every window. hyprpaper
#       keeps running for the image wallpapers, and on the same layer the two
#       would be stacked in whatever order they happened to start.
MPVPAPER_ARGS = ["--auto-pause", "--auto-mode", "FULL", "--layer", "bottom"]


# ── Frames ───────────────────────────────────────────────────────────────

def key_for(path, kind):
    st = os.stat(path)
    h = hashlib.sha1(f"{path}:{st.st_mtime_ns}:{st.st_size}:{kind}".encode())
    return h.hexdigest() + ".jpg"


def duration(path):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", path],
        capture_output=True, text=True,
    )
    try:
        return float(r.stdout.strip())
    except ValueError:
        return 0.0


def cut_frame(src, dst, at, height=None):
    """One frame at `at` seconds. A second in rather than the first frame:
    plenty of loops open on a fade or on black, and a black panel in the
    picker reads as a file that failed to load."""
    vf = ["-vf", f"scale=-2:{height}"] if height else []
    tmp = dst + ".part.jpg"
    r = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-ss", f"{at:.2f}", "-i", src,
         "-frames:v", "1", *vf, "-q:v", "3", tmp],
        capture_output=True,
    )
    if r.returncode == 0 and os.path.exists(tmp):
        os.replace(tmp, dst)
        return True
    try:
        os.unlink(tmp)
    except OSError:
        pass
    return False


def frames_for(src):
    thumb = os.path.join(CACHE, key_for(src, f"thumb{THUMB_HEIGHT}"))
    poster = os.path.join(CACHE, key_for(src, "poster"))
    if not (os.path.exists(thumb) and os.path.exists(poster)):
        at = min(1.0, duration(src) * 0.1)
        if not os.path.exists(thumb):
            cut_frame(src, thumb, at, THUMB_HEIGHT)
        if not os.path.exists(poster):
            cut_frame(src, poster, at)
    return (thumb if os.path.exists(thumb) else "",
            poster if os.path.exists(poster) else "")


def videos(directory):
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        return []
    return [os.path.join(directory, n) for n in names
            if n.lower().endswith(EXTS) and os.path.isfile(os.path.join(directory, n))]


def clean(keep):
    """Frames are keyed on mtime, so every edited or replaced video leaves
    its old pair behind. Anything no current video points at goes."""
    keep = {os.path.basename(p) for p in keep if p}
    for f in os.listdir(CACHE):
        if f not in keep:
            try:
                os.unlink(os.path.join(CACHE, f))
            except OSError:
                pass


# ── State ────────────────────────────────────────────────────────────────

def remembered():
    try:
        with open(STATE) as fh:
            path = fh.read().strip()
    except OSError:
        return ""
    return path if os.path.isfile(path) else ""


def remember(path):
    os.makedirs(STATE_DIR, exist_ok=True)
    if path:
        with open(STATE, "w") as fh:
            fh.write(path + "\n")
    else:
        try:
            os.unlink(STATE)
        except OSError:
            pass


# ── mpvpaper ─────────────────────────────────────────────────────────────

def running_video():
    """The file the running mpvpaper is playing, read off its command line,
    or "" when none is running."""
    r = subprocess.run(["pgrep", "-x", "mpvpaper"], capture_output=True, text=True)
    for pid in r.stdout.split():
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as fh:
                args = fh.read().split(b"\0")
        except OSError:
            continue
        args = [a.decode(errors="replace") for a in args if a]
        if args:
            return args[-1]
    return ""


def kill():
    subprocess.run(["pkill", "-x", "mpvpaper"], capture_output=True)
    # Give it a moment to let go of its layer surfaces, so a new one starting
    # straight after does not briefly draw on top of the old.
    for _ in range(20):
        if not running_video():
            return
        time.sleep(0.05)
    subprocess.run(["pkill", "-9", "-x", "mpvpaper"], capture_output=True)


def start(path):
    os.makedirs(STATE_DIR, exist_ok=True)
    # Truncated on every start: it only has to explain the current run.
    log = open(LOG, "wb")
    # Its own session, so it outlives this script and is not taken down with
    # whatever process asked for it -- quickshell restarts on every save.
    subprocess.Popen(
        ["mpvpaper", *MPVPAPER_ARGS, "-o", MPV_OPTIONS, "ALL", path],
        stdin=subprocess.DEVNULL, stdout=log, stderr=log,
        start_new_session=True,
    )


# ── Commands ─────────────────────────────────────────────────────────────

def cmd_list(directory):
    os.makedirs(CACHE, exist_ok=True)
    out, keep = [], []
    for src in videos(directory):
        try:
            thumb, poster = frames_for(src)
        except OSError:
            continue
        keep += [thumb, poster]
        out.append({"path": src, "thumb": thumb, "poster": poster})
    clean(keep)
    print(json.dumps({"videos": out, "current": remembered()}))


def cmd_apply(path):
    if not os.path.isfile(path):
        sys.exit(f"no such video: {path}")
    if shutil.which("mpvpaper") is None:
        sys.exit("mpvpaper is not installed")
    kill()
    start(path)
    remember(path)
    print(json.dumps({"current": path}))


def cmd_stop():
    kill()
    remember("")


def cmd_restore():
    path = remembered()
    if not path:
        return
    # quickshell runs this every time it starts, and it restarts on every
    # saved QML file. A video already playing is left alone rather than
    # restarted from the top on each save.
    if running_video() == path:
        return
    kill()
    start(path)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        cmd_list(sys.argv[2] if len(sys.argv) > 2 else WALLPAPERS)
    elif cmd == "apply" and len(sys.argv) > 2:
        cmd_apply(sys.argv[2])
    elif cmd == "stop":
        cmd_stop()
    elif cmd == "restore":
        cmd_restore()
    elif cmd == "current":
        print(remembered())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
