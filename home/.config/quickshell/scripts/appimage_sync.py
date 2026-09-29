#!/usr/bin/env python3
"""Puts every AppImage in ~/Applications in the launcher, and takes it out
again when the file goes.

Run by appimage-sync.path whenever ~/Applications changes, and once at
login. For each AppImage it reads the .desktop file and icon the image
carries inside itself, and writes

  ~/.local/share/applications/appimage-<name>.desktop
  ~/.local/share/icons/hicolor/.../appimage-<name>.png

The launcher (Quickshell's DesktopEntries) notices a new .desktop file by
itself, in a second or two; so does every other menu.

An AppImage that already has a .desktop of its own -- written by hand, like
osu!'s with its environment variable -- is left to it: matched by the
program its Exec runs (through symlinks) or by name. Only files this script
wrote carry X-AppImage-Sync, and only those are ever changed or removed.

Nothing is renamed. A new version dropped in next to the old one replaces
it in the launcher (the highest version of a name wins), and deleting the
old file cleans up after it.
"""
import configparser
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

HOME = os.path.expanduser("~")
APPS_DIR = os.path.join(HOME, "Applications")
DESKTOP_DIR = os.path.join(HOME, ".local/share/applications")
ICON_DIR = os.path.join(HOME, ".local/share/icons/hicolor")
STATE_DIR = os.path.join(HOME, ".local/state/appimage-sync")
# AppImages found to have a .desktop of their own by name, with the stamp of
# the file then: looking inside one costs a second, and it would otherwise
# be paid on every change to the folder.
SKIP_FILE = os.path.join(STATE_DIR, "covered.json")
MARK = "X-AppImage-Sync"
PREFIX = "appimage-"


def natural(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def slug_of(filename):
    """ "Wooting.Background.Service_0.5.0_amd64.AppImage" -> "wooting-background-service"."""
    base = re.sub(r"\.appimage$", "", filename, flags=re.I)
    # Cut at the first separator followed by a version, a "v" and digits, or
    # an architecture: what follows is not the app's name.
    base = re.split(r"[-_ .](?=v?\d)|[-_ .](?:x86[-_]64|amd64|linux(?:64)?|appimage)\b", base, flags=re.I)[0]
    return re.sub(r"[^a-z0-9]+", "-", base.lower()).strip("-") or "app"


def read_desktop(path):
    cp = configparser.RawConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            cp.read_string(f.read())
    except (OSError, configparser.Error):
        return None
    return dict(cp["Desktop Entry"]) if cp.has_section("Desktop Entry") else None


def exec_program(exec_line):
    """The program an Exec line runs, past any `env VAR=value` in front."""
    try:
        words = shlex.split(exec_line or "")
    except ValueError:
        return ""
    while words and (words[0] == "env" or "=" in words[0]):
        words.pop(0)
    return words[0] if words else ""


def resolve(prog):
    if not prog:
        return ""
    if "/" not in prog:
        prog = shutil.which(prog) or prog
    return os.path.realpath(os.path.expanduser(prog))


# ── Reading an AppImage ──────────────────────────────────────────────────


def extract(image, patterns, into):
    for p in patterns:
        subprocess.run([image, "--appimage-extract", p], cwd=into, timeout=60,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def follow(image, root, rel, into, depth=0):
    """The real file behind rel, extracting symlink targets as needed."""
    path = os.path.join(root, rel)
    if depth > 6 or not os.path.lexists(path):
        return None
    if os.path.islink(path):
        target = os.readlink(path)
        target_rel = os.path.normpath(os.path.join(os.path.dirname(rel), target)).lstrip("/")
        if not os.path.exists(os.path.join(root, target_rel)):
            extract(image, [target_rel], into)
        return follow(image, root, target_rel, into, depth + 1)
    return path if os.path.isfile(path) else None


def png_size(path):
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            return int.from_bytes(head[16:20], "big")
    except OSError:
        pass
    return 0


def inspect(image):
    """(desktop entry dict, icon file path, tmpdir) -- or None if unreadable,
    as a file still being copied in is."""
    tmp = tempfile.mkdtemp(prefix="appimage-sync-")
    try:
        extract(image, ["*.desktop", ".DirIcon"], tmp)
        roots = [d for d in os.listdir(tmp) if os.path.isdir(os.path.join(tmp, d))]
        if not roots:
            shutil.rmtree(tmp, ignore_errors=True)
            return None
        root = os.path.join(tmp, roots[0])
        entry = None
        for name in sorted(os.listdir(root)):
            if name.endswith(".desktop"):
                real = follow(image, root, name, tmp)
                entry = read_desktop(real) if real else None
                if entry:
                    break
        entry = entry or {}
        icon_name = entry.get("Icon", "")
        icons = []
        if icon_name:
            extract(image, [f"{icon_name}.svg", f"{icon_name}.png",
                            f"usr/share/icons/hicolor/*/apps/{icon_name}.*"], tmp)
            for dp, _, files in os.walk(root):
                for f in files:
                    if os.path.splitext(f)[0] == icon_name:
                        rel = os.path.relpath(os.path.join(dp, f), root)
                        real = follow(image, root, rel, tmp)
                        if real:
                            icons.append(real)
        diricon = follow(image, root, ".DirIcon", tmp)
        if diricon:
            icons.append(diricon)
        best = None
        svgs = [i for i in icons if i.endswith(".svg")]
        if svgs:
            best = svgs[0]
        else:
            pngs = [i for i in icons if png_size(i) > 0]
            if pngs:
                best = max(pngs, key=png_size)
        return entry, best, tmp
    except (OSError, subprocess.SubprocessError):
        shutil.rmtree(tmp, ignore_errors=True)
        return None


# ── The sync ─────────────────────────────────────────────────────────────


def current_images():
    """slug -> path, the highest version where one name has several."""
    by_slug = {}
    if not os.path.isdir(APPS_DIR):
        return by_slug
    for f in os.listdir(APPS_DIR):
        path = os.path.join(APPS_DIR, f)
        if f.lower().endswith(".appimage") and os.path.isfile(path):
            by_slug.setdefault(slug_of(f), []).append(path)
    return {s: sorted(ps, key=lambda p: natural(os.path.basename(p)))[-1] for s, ps in by_slug.items()}


def own_desktops():
    """Every .desktop there: (path, entry, ours)."""
    out = []
    if not os.path.isdir(DESKTOP_DIR):
        return out
    for f in os.listdir(DESKTOP_DIR):
        if f.endswith(".desktop"):
            p = os.path.join(DESKTOP_DIR, f)
            e = read_desktop(p)
            if e is not None:
                out.append((p, e, MARK in e))
    return out


def stamp(path):
    st = os.stat(path)
    return f"{st.st_size}:{int(st.st_mtime)}"


def remove_icons(slug):
    for size in os.listdir(ICON_DIR) if os.path.isdir(ICON_DIR) else []:
        for ext in (".png", ".svg"):
            p = os.path.join(ICON_DIR, size, "apps", PREFIX + slug + ext)
            if os.path.exists(p):
                os.remove(p)


def notify(title, body, icon=""):
    try:
        subprocess.Popen(["notify-send", "-a", "Applications", "-i", icon or "application-x-executable",
                          title, body], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def write_desktop(path, fields):
    lines = ["[Desktop Entry]"] + [f"{k}={v}" for k, v in fields.items() if v not in (None, "")]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, path)


def main():
    images = current_images()
    desktops = own_desktops()
    ours = {os.path.basename(p)[len(PREFIX):-len(".desktop")]: (p, e) for p, e, mine in desktops
            if mine and os.path.basename(p).startswith(PREFIX)}

    # Covered by a .desktop someone else wrote: by what it runs, or by name.
    covered_progs = set()
    covered_names = set()
    for p, e, mine in desktops:
        if mine:
            continue
        covered_progs.add(resolve(exec_program(e.get("Exec", ""))))
        covered_names.add(e.get("Name", "").strip().lower())

    added, removed, mime = [], [], False
    listed = []
    try:
        with open(SKIP_FILE, encoding="utf-8") as f:
            skip = json.load(f)
    except (OSError, ValueError):
        skip = {}
    new_skip = {}

    for slug, image in sorted(images.items()):
        real = os.path.realpath(image)
        if real in covered_progs:
            continue
        if skip.get(image) == stamp(image):
            new_skip[image] = skip[image]
            continue
        have = ours.get(slug)
        if have and have[1].get(MARK) == image and have[1].get(MARK + "-Stamp") == stamp(image):
            entry = have[1]
        else:
            if not os.access(image, os.X_OK):
                os.chmod(image, os.stat(image).st_mode | 0o111)
            got = inspect(image)
            if got is None:
                continue  # not readable yet: a copy in progress; the next change retries
            inner, icon_file, tmp = got
            name = inner.get("Name") or re.sub(r"[-_]+", " ", slug).title()
            if not have and name.strip().lower() in covered_names:
                shutil.rmtree(tmp, ignore_errors=True)
                new_skip[image] = stamp(image)
                continue
            remove_icons(slug)
            icon = ""
            if icon_file:
                ext = os.path.splitext(icon_file)[1] if icon_file.endswith(".svg") else ".png"
                sub = "scalable" if ext == ".svg" else "256x256"
                dest = os.path.join(ICON_DIR, sub, "apps", PREFIX + slug + ext)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copyfile(icon_file, dest)
                icon = PREFIX + slug
            shutil.rmtree(tmp, ignore_errors=True)
            try:
                args = shlex.split(inner.get("Exec", ""))[1:]
            except ValueError:
                args = []
            exec_line = " ".join([shlex.quote(image)] + args)
            entry = {
                "Type": "Application",
                "Name": name,
                "GenericName": inner.get("GenericName"),
                "Comment": inner.get("Comment"),
                "Exec": exec_line,
                "Icon": icon,
                "Terminal": "false",
                "Categories": inner.get("Categories") or "Utility;",
                "Keywords": inner.get("Keywords"),
                "MimeType": inner.get("MimeType"),
                "StartupWMClass": inner.get("StartupWMClass"),
                MARK: image,
                MARK + "-Stamp": stamp(image),
            }
            write_desktop(os.path.join(DESKTOP_DIR, PREFIX + slug + ".desktop"), entry)
            if not have:
                added.append((entry["Name"], icon))
        mime = mime or bool(entry.get("MimeType"))
        listed.append(slug)

    # Ours, whose AppImage is gone (or now has a .desktop of its own).
    keep = set(listed)
    for slug, (p, e) in ours.items():
        if slug not in keep:
            os.remove(p)
            remove_icons(slug)
            removed.append(e.get("Name", slug))

    # Icons left behind by an AppImage that is gone, or by a run cut short.
    for size in os.listdir(ICON_DIR) if os.path.isdir(ICON_DIR) else []:
        apps = os.path.join(ICON_DIR, size, "apps")
        for f in os.listdir(apps) if os.path.isdir(apps) else []:
            if f.startswith(PREFIX) and os.path.splitext(f)[0][len(PREFIX):] not in keep:
                os.remove(os.path.join(apps, f))

    os.makedirs(STATE_DIR, exist_ok=True)
    if new_skip != skip:
        with open(SKIP_FILE, "w", encoding="utf-8") as f:
            json.dump(new_skip, f)
    if (added or removed) and mime and shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", DESKTOP_DIR], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    for name, icon in added:
        notify(f"{name} is in the launcher", "Super+Space, then type its name", icon)
    for name in removed:
        notify(f"{name} was removed", "Its AppImage left ~/Applications")
    return 0


if __name__ == "__main__":
    sys.exit(main())
