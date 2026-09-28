#!/usr/bin/env python3
"""The Steam games on this machine, as JSON, for the launcher.

Read straight off Steam's own files, so nothing needs Steam to answer and no
account key is involved:

  steamapps/libraryfolders.vdf        where the libraries are
  <library>/steamapps/appmanifest_*   one per installed app: id, name, state
  userdata/<user>/config/shortcuts.vdf   the non-Steam games added to Steam

Steam's tools install the same way as games -- Proton, the Linux runtimes,
the redistributables -- and are left out by name. Only what is installed is
listed: which games an account owns is not kept on disk in any readable form.

Each entry: {"id", "name", "icon", "run", "kind", "update"}, where `run` is
the steam:// URL that starts it and `icon` a path or "".
"""

import glob
import json
import os
import re
import struct

STEAM = os.path.expanduser("~/.local/share/Steam")

# Installed like games, but not games.
TOOLS = re.compile(r"^(Proton\b|Steam Linux Runtime|Steamworks Common|Steam Audio|"
                   r"SteamVR|Proton (EasyAntiCheat|BattlEye) Runtime)", re.I)

# appmanifest StateFlags: 4 is "fully installed". 2 on top of it means an
# update is waiting, which does not stop the game from starting.
INSTALLED = 4
UPDATE_REQUIRED = 2


def vdf_text(path):
    """The key/value pairs of a text VDF, flattened: enough for manifests
    and libraryfolders, which are all this reads."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return re.findall(r'"([^"]*)"\s+"([^"]*)"', fh.read())
    except OSError:
        return []


def libraries():
    paths = [v for k, v in vdf_text(os.path.join(STEAM, "steamapps/libraryfolders.vdf")) if k == "path"]
    seen = []
    for p in [STEAM] + paths:
        real = os.path.realpath(p)
        if real not in seen and os.path.isdir(os.path.join(real, "steamapps")):
            seen.append(real)
    return seen


def icon_for(appid):
    """The best small picture Steam keeps for a game: the icon it installs
    with a desktop shortcut, else the icon in its library cache."""
    best = None
    for f in glob.glob(os.path.expanduser(f"~/.local/share/icons/hicolor/*/apps/steam_icon_{appid}.png")):
        size = int(re.search(r"/(\d+)x\d+/", f).group(1)) if re.search(r"/(\d+)x\d+/", f) else 0
        if best is None or size > best[0]:
            best = (size, f)
    if best:
        return best[1]
    for f in glob.glob(os.path.join(STEAM, "appcache/librarycache", str(appid), "*.jpg")):
        # The icon is the one named by its hash; the rest are banners.
        if re.fullmatch(r"[0-9a-f]{40}\.jpg", os.path.basename(f)):
            return f
    return ""


def steam_games():
    games = {}
    for lib in libraries():
        for manifest in glob.glob(os.path.join(lib, "steamapps/appmanifest_*.acf")):
            kv = dict(vdf_text(manifest))
            try:
                appid = int(kv.get("appid", ""))
                flags = int(kv.get("StateFlags", "0"))
            except ValueError:
                continue
            name = kv.get("name", "")
            if not name or TOOLS.search(name) or not flags & INSTALLED:
                continue
            games[appid] = {
                "id": str(appid),
                "name": name,
                "icon": icon_for(appid),
                "run": f"steam://rungameid/{appid}",
                "kind": "steam",
                "update": bool(flags & UPDATE_REQUIRED),
            }
    return list(games.values())


def binary_vdf(data):
    """shortcuts.vdf: a binary VDF -- 0x00 opens a map, 0x01 a string, 0x02 a
    32-bit integer, 0x08 closes the map -- read into nested dicts."""
    pos = 0

    def cstring():
        nonlocal pos
        end = data.index(b"\0", pos)
        s = data[pos:end].decode("utf-8", errors="replace")
        pos = end + 1
        return s

    def mapping():
        nonlocal pos
        out = {}
        while pos < len(data):
            kind = data[pos]
            pos += 1
            if kind == 0x08:
                return out
            key = cstring()
            if kind == 0x00:
                out[key] = mapping()
            elif kind == 0x01:
                out[key] = cstring()
            elif kind == 0x02:
                out[key] = struct.unpack_from("<i", data, pos)[0]
                pos += 4
            else:
                raise ValueError(f"unknown VDF type {kind}")
        return out

    return mapping()


def shortcuts():
    out = []
    for path in glob.glob(os.path.join(STEAM, "userdata/*/config/shortcuts.vdf")):
        try:
            with open(path, "rb") as fh:
                tree = binary_vdf(fh.read())
        except (OSError, ValueError, IndexError, struct.error):
            continue
        for sc in (tree.get("shortcuts") or {}).values():
            name = sc.get("AppName") or sc.get("appname") or ""
            appid = sc.get("appid")
            if not name or appid is None:
                continue
            # A shortcut is started by its 64-bit game id: its 32-bit app id
            # in the high half, and the "shortcut" flag in the low.
            gameid = ((appid & 0xFFFFFFFF) << 32) | 0x02000000
            icon = sc.get("icon", "").strip('"')
            out.append({
                "id": f"shortcut-{appid & 0xFFFFFFFF}",
                "name": name,
                "icon": icon if icon and os.path.isfile(icon) else "",
                "run": f"steam://rungameid/{gameid}",
                "kind": "shortcut",
                "update": False,
            })
    return out


def main():
    games = steam_games() + shortcuts()
    games.sort(key=lambda g: g["name"].lower())
    print(json.dumps(games))


if __name__ == "__main__":
    main()
