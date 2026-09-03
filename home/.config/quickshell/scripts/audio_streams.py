#!/usr/bin/env python3
"""List playback streams as JSON, with a usable name and icon candidates.

A sink input often carries neither an app name nor an icon: those live on the
owning client, and for launcher-spawned processes (java, electron, wine) even
the client only says "java". So this merges the stream with its client and,
when the result is still generic, mines the process command line for a better
name.

Each stream also carries the MPRIS bus names of the player that owns it, so a
media widget showing one player can find that player's own slider rather than
guessing from names. The link is the process: an MPRIS name and a sink input
both resolve to a pid, and one is the other or its ancestor.
"""

import getpass
import json
import os
import re
import subprocess

# Names that identify a runtime rather than the application the user sees.
GENERIC = {"java", "python", "python3", "electron", "wine", "wine64",
           "node", "mono", "sh", "bash", "zsh", "chrome_crashpad_handler"}

# Path segments that never name an application.
NOISE = {"home", "usr", "bin", "sbin", "lib", "lib64", "libexec", "opt", "etc",
         "var", "tmp", "run", "srv", "local", "share", "games", "app", "apps",
         "current", "files", "data", "runtime", "jre", "jdk", "java", "bin64",
         "x86_64", "linux", "release", "debug", "target", "build", "dist"}

# The user's own name shows up in every $HOME path and never names an app.
NOISE.add(getpass.getuser().lower())
NOISE.add(os.path.basename(os.path.expanduser("~")).lower())

PROP = re.compile(r'^\s+([a-zA-Z0-9_.-]+) = "(.*)"$')
SEGMENT = re.compile(r"^[A-Za-z][A-Za-z0-9._+-]{2,}$")


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def parse_blocks(text, header_prefix):
    """Split pactl output into (header line, {property: value}) blocks."""
    blocks, header, props, body = [], None, {}, []
    for line in text.splitlines():
        if line.startswith(header_prefix):
            if header is not None:
                blocks.append((header, props, body))
            header, props, body = line, {}, []
            continue
        if header is None:
            continue
        body.append(line)
        match = PROP.match(line)
        if match:
            props[match.group(1)] = match.group(2)
    if header is not None:
        blocks.append((header, props, body))
    return blocks


def first_volume(body):
    for line in body:
        if line.strip().startswith("Volume:"):
            match = re.search(r"(\d+)%", line)
            if match:
                return int(match.group(1))
    return 0


def field(body, label):
    for line in body:
        stripped = line.strip()
        if stripped.startswith(label):
            return stripped[len(label):].strip()
    return ""


def cmdline_candidates(pid):
    """App-ish path segments from a process command line, best first."""
    if not pid:
        return []
    try:
        with open("/proc/%s/cmdline" % pid, "rb") as handle:
            raw = handle.read().decode("utf-8", "replace")
    except OSError:
        return []

    seen, out = set(), []
    for token in raw.split("\0"):
        if "/" not in token:
            continue
        for part in token.split("/"):
            key = part.lower()
            if key in NOISE or key in GENERIC or not SEGMENT.match(part):
                continue
            # Skip version-ish and dotfile-ish segments.
            if part.startswith(".") or re.fullmatch(r"[\d._-]+", part):
                continue
            if key in seen:
                continue
            seen.add(key)
            out.append(part)
    return out[:4]


def parent_pid(pid):
    """The ppid from /proc/<pid>/stat, or 0 when it cannot be read.

    The comm field is parenthesised and may itself contain spaces and
    parentheses, so the fields after it are found from the last ')' rather
    than by splitting the whole line.
    """
    try:
        with open("/proc/%d/stat" % pid, encoding="utf-8", errors="replace") as handle:
            stat = handle.read()
    except (OSError, ValueError):
        return 0
    tail = stat.rpartition(")")[2].split()
    if len(tail) < 2:
        return 0
    try:
        return int(tail[1])
    except ValueError:
        return 0


def mpris_owners():
    """Map a pid to the MPRIS bus names it answers on.

    Both the well-known name and the unique connection name are recorded: a
    client knows its player by one or the other, and which one depends on how
    it found the player.
    """
    try:
        listing = run("busctl", "--user", "list", "--no-legend", "--no-pager")
    except (subprocess.CalledProcessError, OSError):
        return {}

    owners = {}
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) < 2 or not fields[0].startswith("org.mpris.MediaPlayer2."):
            continue
        try:
            pid = int(fields[1])
        except ValueError:
            # Activatable but not running: it owns no stream either.
            continue
        names = owners.setdefault(pid, [])
        names.append(fields[0])
        # The unique name is the one field shaped like ":1.176".
        for token in fields[2:]:
            if token.startswith(":") and token not in names:
                names.append(token)
    return owners


def owning_player(pid, owners):
    """MPRIS names of the player a stream's pid belongs to.

    Spotify plays from the same process that owns its bus name, but a browser
    decodes in a child, so the stream's pid is walked up to its ancestors. The
    walk is bounded: a broken /proc read returns 0 and ends it, and the depth
    cap keeps a cycle from spinning.
    """
    try:
        current = int(pid)
    except (TypeError, ValueError):
        return []
    for _ in range(12):
        if current <= 1:
            return []
        if current in owners:
            return owners[current]
        current = parent_pid(current)
    return []


def desktop_icon_index():
    """Map an app-ish key to the Icon= of its .desktop entry.

    Icons are often named in reverse DNS (org.prismlauncher.PrismLauncher)
    while the process only knows "prismlauncher", so entries are indexed by
    their full id and by each dotted suffix of it.
    """
    index = {}
    roots = [os.path.expanduser("~/.local/share/applications"),
             "/usr/share/applications"]
    for root in roots:
        try:
            entries = sorted(os.listdir(root))
        except OSError:
            continue
        for entry in entries:
            if not entry.endswith(".desktop"):
                continue
            icon = name = ""
            try:
                with open(os.path.join(root, entry), encoding="utf-8", errors="replace") as handle:
                    for line in handle:
                        if line.startswith("Icon=") and not icon:
                            icon = line[5:].strip()
                        elif line.startswith("Name=") and not name:
                            name = line[5:].strip()
                        if icon and name:
                            break
            except OSError:
                continue
            if not icon:
                continue
            app_id = entry[:-len(".desktop")]
            keys = [app_id] + app_id.split(".") + ([name] if name else [])
            for key in keys:
                if len(key) > 2:
                    index.setdefault(key.lower(), icon)
    return index


def main():
    desktop_icons = desktop_icon_index()
    players = mpris_owners()
    clients = {}
    for header, props, _ in parse_blocks(run("pactl", "list", "clients"), "Client #"):
        clients[header.split("#", 1)[1].strip()] = props
        object_id = props.get("object.id")
        if object_id:
            clients.setdefault(object_id, props)

    streams = []
    for header, props, body in parse_blocks(run("pactl", "list", "sink-inputs"), "Sink Input #"):
        stream_id = header.split("#", 1)[1].strip()
        client = clients.get(field(body, "Client:"), {}) or clients.get(props.get("client.id", ""), {})

        def prop(key):
            return props.get(key) or client.get(key) or ""

        name = prop("application.name") or props.get("node.name") or ""
        binary = prop("application.process.binary")
        pid = prop("application.process.id") or client.get("pipewire.sec.pid", "")

        extra = []
        if not name or name.lower() in GENERIC:
            extra = cmdline_candidates(pid)
            if extra:
                name = extra[0]
        if not name:
            name = props.get("media.name") or "Unknown"

        # Ordered icon guesses; the shell takes the first the theme resolves.
        stem = re.sub(r"-(bin|git|stable|beta|nightly)$", "", binary) if binary else ""
        icons = [prop("application.icon_name"), binary, stem,
                 stem + "-browser" if stem else "",
                 name.lower(), name.lower() + "-browser"]
        icons += extra
        icons += [seg.lower() for seg in extra]

        # Whatever the .desktop entries say wins: it is the name the icon
        # theme actually ships.
        icons = [desktop_icons.get(c.lower()) for c in icons if c] + icons

        seen, ordered = set(), []
        for candidate in icons:
            if candidate and candidate not in seen:
                seen.add(candidate)
                ordered.append(candidate)

        streams.append({
            "id": stream_id,
            "name": name,
            "volume": first_volume(body),
            "icons": ordered,
            "mpris": owning_player(pid, players),
        })

    print(json.dumps(streams))


main()
