#!/usr/bin/env python3
"""Quick-capture note in the Obsidian vault, for the shell's notes widget.

Obsidian has no API of its own. The community Local REST API plugin only
answers while the app is running, which is the wrong half of the time for a
capture box you hit on the way past -- so this reads and writes the vault's
Markdown directly. That is what Obsidian is built on top of, so a note
written here is just a note; Obsidian picks up the change when it opens, and
LiveSync treats it like any other edit.

Usage:
    obsidian_capture.py                 read the note, print JSON
    obsidian_capture.py --add "text"    append an entry, then print JSON
"""

import argparse
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime

# The note the widget owns. Kept at the vault root, with a name that reads
# like something a person made, because in Obsidian that is what it is.
NOTE_NAME = "captura-rapida.md"
TITLE = "# Captura rápida"

# "- 10:45 comprar café" under a "## 2026-09-02" heading. One bullet per
# entry so the note stays a normal Obsidian list rather than a log format
# only this script understands.
ENTRY_RE = re.compile(r"^-\s+(\d{2}:\d{2})\s+(.*)$")
DATE_RE = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})\s*$")

MAX_ENTRIES = 12


def find_vault():
    """Vault path from Obsidian's own registry, preferring the open one.

    Read rather than hardcoded so the widget follows the vault if it is
    moved or renamed from inside Obsidian.
    """
    override = os.environ.get("QS_OBSIDIAN_VAULT")
    if override:
        return override

    config = os.path.expanduser("~/.config/obsidian/obsidian.json")
    try:
        with open(config, encoding="utf-8") as f:
            vaults = json.load(f).get("vaults", {})
    except (OSError, ValueError):
        return None

    if not vaults:
        return None

    for entry in vaults.values():
        if entry.get("open") and os.path.isdir(entry.get("path", "")):
            return entry["path"]

    # Nothing flagged open -- most recently touched vault that still exists.
    known = [v for v in vaults.values() if os.path.isdir(v.get("path", ""))]
    if not known:
        return None
    return max(known, key=lambda v: v.get("ts", 0))["path"]


def read_entries(path):
    """Every entry in the note, newest first."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return []
    except OSError:
        return []

    entries = []
    date = ""
    for line in lines:
        heading = DATE_RE.match(line)
        if heading:
            date = heading.group(1)
            continue
        entry = ENTRY_RE.match(line)
        if entry:
            entries.append({
                "date": date,
                "time": entry.group(1),
                "text": entry.group(2).strip(),
            })

    entries.reverse()
    return entries


def lock_path_for(path):
    """Lock file for *path*, outside the vault.

    Kept in the runtime dir rather than next to the note: a stray lock file
    in the vault is one more thing for Obsidian to list and LiveSync to
    carry around.
    """
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    digest = hashlib.sha1(path.encode("utf-8")).hexdigest()[:16]
    return os.path.join(runtime, f"quickshell-obsidian-{digest}.lock")


def add_entry(path, text):
    """Append *text* under today's heading, creating what is missing.

    The new line goes at the end of today's section rather than the end of
    the file, so a note that has been reordered or annotated by hand in
    Obsidian keeps its shape.

    Read-modify-write under an exclusive lock. Two of these racing used to
    lose entries -- last writer won and wrote a file built from a copy read
    before the other's entry existed.
    """
    text = " ".join(text.split())
    if not text:
        return

    lock_file = lock_path_for(path)
    try:
        lock = open(lock_file, "w")
    except OSError:
        lock = None

    try:
        if lock is not None:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        _add_entry_locked(path, text)
    finally:
        if lock is not None:
            lock.close()


def _add_entry_locked(path, text):
    now = datetime.now()
    today = now.strftime("%Y-%m-%d")
    stamp = now.strftime("%H:%M")
    entry = f"- {stamp} {text}"

    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        lines = [TITLE, ""]
    except OSError:
        return

    if not any(line.strip() for line in lines):
        lines = [TITLE, ""]

    start = None
    for i, line in enumerate(lines):
        match = DATE_RE.match(line)
        if match and match.group(1) == today:
            start = i
            break

    if start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend([f"## {today}", "", entry])
    else:
        # End of today's section: the line before the next heading, or the
        # end of the file.
        end = len(lines)
        for i in range(start + 1, len(lines)):
            if lines[i].startswith("## "):
                end = i
                break
        while end > start + 1 and not lines[end - 1].strip():
            end -= 1
        lines.insert(end, entry)

    # A unique temp name, in the note's own directory so the replace is a
    # rename rather than a copy. A fixed name here was the real corruption:
    # two adds at once wrote their whole files into the same scratch path,
    # interleaved, and whichever renamed last published the mixture.
    directory = os.path.dirname(path) or "."
    try:
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".captura-", suffix=".tmp")
    except OSError:
        return

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(lines).rstrip("\n") + "\n")
        # Replaced rather than written in place: Obsidian and LiveSync both
        # watch this file, and a half-written note is one they would read.
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--add", metavar="TEXT")
    args = parser.parse_args()

    vault = find_vault()
    if not vault:
        json.dump({"error": "No Obsidian vault found"}, sys.stdout)
        sys.stdout.write("\n")
        return

    path = os.path.join(vault, NOTE_NAME)

    if args.add:
        add_entry(path, args.add)

    entries = read_entries(path)
    json.dump({
        "vault": vault,
        "vaultName": os.path.basename(vault.rstrip("/")),
        "note": NOTE_NAME,
        "path": path,
        "exists": os.path.exists(path),
        "total": len(entries),
        "entries": entries[:MAX_ENTRIES],
    }, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
