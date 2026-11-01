#!/usr/bin/env python3
"""Publishes osu!lazer's current song as an MPRIS player.

A bridge rather than a special case in the widget: shell.qml already picks between MPRIS players
(activePlayer, playerRank, pinnedPlayer, cycling), so as one more player osu gets all of it.

lazer registers no MPRIS and keeps the song out of its window title; only its log names it, on
every map change:

    Invalidating working beatmap cache for <artist> - <title> (<mapper>) [<difficulty>]

That is a log, not an API, and may change in any release: if osu stops showing in the bar, look
at that line first. Gio rather than dbus-next or pydbus, since PyGObject is already installed.
"""

import glob
import os
import pathlib
import re
import subprocess
import sys
import unicodedata

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "org.mpris.MediaPlayer2.osu"
OBJECT_PATH = "/org/mpris/MediaPlayer2"
MARKER = "working beatmap cache for"

# Where the background images come from. The log names only artist/title/mapper/difficulty, and
# lazer stores files by content hash with Realm as the only index, impractical from Python. osu!
# stable's song folders have readable names and cover what gets played (141 of 142 maps in a real
# session); without it only covers are lost.
SONGS_DIR = os.environ.get(
    "OSU_SONGS_DIR", "/mnt/ssd/Juegos/osu!/Songs")


def normalise(text):
    """Search key: no accents, no punctuation, all run together in lower case."""
    text = unicodedata.normalize("NFKD", text).lower()
    return re.sub(r"[^a-z0-9]", "", text)

# The minimum quickshell needs to treat it as a player. Every control is false: this mirrors what
# osu is doing and cannot ask it to change songs.
INTROSPECTION = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <method name="Raise"/>
    <method name="Quit"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""


def strip_trailing(text, opening, closing):
    """Drops a trailing (...) or [...] group, counting depth.

    Not a regex: osu difficulty names nest brackets ("[Maddy's Boss Stage [Adjusted Offset]]"
    is real, 140 such lines in the history); counting from the right parses them all.
    """
    text = text.rstrip()
    if not text.endswith(closing):
        return text
    depth = 0
    for i in range(len(text) - 1, -1, -1):
        if text[i] == closing:
            depth += 1
        elif text[i] == opening:
            depth -= 1
            if depth == 0:
                return text[:i].rstrip()
    return text


def parse_beatmap(payload):
    """'<artist> - <title> (<mapper>) [<difficulty>]' -> (artist, title)."""
    rest = strip_trailing(payload, "[", "]")
    rest = strip_trailing(rest, "(", ")")
    if " - " not in rest:
        return None
    artist, title = rest.split(" - ", 1)
    artist, title = artist.strip(), title.strip()
    return (artist, title) if title else None


def log_directory():
    """The log folder, following storage.ini if it moves the data."""
    local = os.path.expanduser("~/.local/share/osu")
    ini = os.path.join(local, "storage.ini")
    try:
        with open(ini, encoding="utf-8") as handle:
            for line in handle:
                # osu-framework's IniConfigManager: 'Key = Value', no sections, and any
                # line without '=' is skipped.
                if line.lstrip().startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key.strip() == "FullPath" and value.strip():
                    return os.path.join(value.strip(), "logs")
    except OSError:
        pass
    return os.path.join(local, "logs")


def osu_running():
    return subprocess.run(["pgrep", "-x", "osu!"],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


class OsuPlayer:
    def __init__(self):
        self.artist = ""
        self.title = ""
        self.connection = None
        self.owner_id = None
        self.registrations = []
        self.art = ""
        self.handle = None
        self.path = None
        self.position = 0
        self.index = None
        self.index_stamp = None
        self.art_cache = {}

    # Map background

    def song_index(self):
        """{normalised(artist+title): folder}, rebuilt when Songs changes.

        Folders are named "<id> <artist> - <title>": the leading id is dropped and the rest
        split at the first " - ".
        """
        try:
            stamp = os.path.getmtime(SONGS_DIR)
        except OSError:
            return {}
        if self.index is not None and stamp == self.index_stamp:
            return self.index

        index = {}
        try:
            entries = os.listdir(SONGS_DIR)
        except OSError:
            self.index, self.index_stamp = {}, stamp
            return self.index

        for entry in entries:
            name = re.sub(r"^\d+\s+", "", entry)
            if " - " not in name:
                continue
            artist, title = name.split(" - ", 1)
            index.setdefault(normalise(artist + title), entry)

        self.index, self.index_stamp = index, stamp
        return index

    def background_in(self, folder):
        """The background image declared in the [Events] of some .osu file."""
        for chart in glob.glob(os.path.join(folder, "*.osu")):
            try:
                with open(chart, encoding="utf-8", errors="replace") as handle:
                    in_events = False
                    for line in handle:
                        line = line.strip()
                        if line.startswith("["):
                            in_events = line.lower().startswith("[events]")
                            continue
                        if not in_events or not line or line.startswith("//"):
                            continue
                        # "0,0,"file.jpg",0,0": the first 0 is the type (background),
                        # the second the start time.
                        match = re.match(r'^0\s*,\s*0\s*,\s*"?([^",]+)"?', line)
                        if match:
                            # Paths come with Windows separators.
                            path = os.path.join(
                                folder, match.group(1).replace("\\", "/"))
                            if os.path.isfile(path):
                                return path
            except OSError:
                continue
        return None

    def art_for(self, artist, title):
        key = normalise(artist + title)
        if key in self.art_cache:
            return self.art_cache[key]

        folder = self.song_index().get(key)
        found = ""
        if folder:
            path = self.background_in(os.path.join(SONGS_DIR, folder))
            if path:
                # as_uri escapes spaces and everything else; a hand-built URL
                # broke on half the map names.
                found = pathlib.Path(path).as_uri()
        self.art_cache[key] = found
        return found

    # D-Bus

    def metadata(self):
        # mpris:trackid is required: clients use it as the track identity, and
        # some drop the metadata without it.
        items = {
            "mpris:trackid": GLib.Variant("o", "/org/mpris/MediaPlayer2/osu/track"),
            "xesam:title": GLib.Variant("s", self.title),
            "xesam:artist": GLib.Variant("as", [self.artist] if self.artist else []),
        }
        # Only when there is one: an empty artUrl makes some clients show a broken
        # gap instead of their placeholder.
        if self.art:
            items["mpris:artUrl"] = GLib.Variant("s", self.art)
        return GLib.Variant("a{sv}", items)

    def get_property(self, _conn, _sender, _path, interface, prop):
        values = {
            "Identity": GLib.Variant("s", "osu!"),
            "DesktopEntry": GLib.Variant("s", "osu"),
            "CanQuit": GLib.Variant("b", False),
            "CanRaise": GLib.Variant("b", False),
            "HasTrackList": GLib.Variant("b", False),
            "PlaybackStatus": GLib.Variant("s", "Playing"),
            "Metadata": self.metadata(),
            "CanPlay": GLib.Variant("b", False),
            "CanPause": GLib.Variant("b", False),
            "CanGoNext": GLib.Variant("b", False),
            "CanGoPrevious": GLib.Variant("b", False),
            "CanSeek": GLib.Variant("b", False),
            "CanControl": GLib.Variant("b", False),
        }
        del interface
        return values.get(prop)

    def on_method(self, _conn, _sender, _path, _iface, _method, _params, invocation):
        invocation.return_value(None)

    def announce(self):
        if self.connection is None:
            return
        # The a{sv} goes as a Python dict, not a built Variant: nesting a Variant in another makes
        # GLib iterate it as a dict and raise KeyError. The inner values are Variants.
        self.connection.emit_signal(
            None, OBJECT_PATH, "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)",
                         ("org.mpris.MediaPlayer2.Player",
                          {"Metadata": self.metadata()}, [])))

    def publish(self):
        if self.owner_id is not None:
            return
        self.connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
        for iface in info.interfaces:
            self.registrations.append(self.connection.register_object(
                OBJECT_PATH, iface, self.on_method, self.get_property, None))
        self.owner_id = Gio.bus_own_name_on_connection(
            self.connection, BUS_NAME, Gio.BusNameOwnerFlags.NONE, None, None)
        print("osu-mpris: publicado", flush=True)

    def unpublish(self):
        if self.owner_id is None:
            return
        Gio.bus_unown_name(self.owner_id)
        for reg in self.registrations:
            self.connection.unregister_object(reg)
        self.registrations = []
        self.owner_id = None
        self.artist = self.title = self.art = ""
        print("osu-mpris: retirado", flush=True)

    # Reading the log

    def newest_log(self):
        logs = glob.glob(os.path.join(log_directory(), "*.runtime.log"))
        return max(logs, key=os.path.getmtime) if logs else None

    def read_new_lines(self):
        newest = self.newest_log()
        if newest is None:
            return
        # Every osu session opens a new log; on a switch read it from the start, so
        # the current map is not missed.
        if newest != self.path:
            self.path = newest
            self.position = 0
        try:
            size = os.path.getsize(self.path)
            if size < self.position:  # truncated
                self.position = 0
            with open(self.path, encoding="utf-8", errors="replace") as handle:
                handle.seek(self.position)
                chunk = handle.read()
                self.position = handle.tell()
        except OSError:
            return

        # Only the last map in the chunk read matters: at startup the chunk is the whole log, and
        # announcing every line replayed the previous session as a burst of PropertiesChanged.
        latest = None
        for line in chunk.splitlines():
            if MARKER not in line:
                continue
            parsed = parse_beatmap(line.split(MARKER, 1)[1].strip())
            if parsed is not None:
                latest = parsed

        if latest is not None and latest != (self.artist, self.title):
            self.artist, self.title = latest
            self.art = self.art_for(self.artist, self.title)
            self.announce()

    def tick(self):
        if osu_running():
            self.publish()
            self.read_new_lines()
        else:
            self.unpublish()
            self.path = None
        return GLib.SOURCE_CONTINUE


def main():
    player = OsuPlayer()
    # 1s: a map change in song select lasts longer than that, and reading new
    # bytes of an open file is free.
    GLib.timeout_add_seconds(1, player.tick)
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        player.unpublish()


if __name__ == "__main__":
    sys.exit(main())
