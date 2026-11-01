#!/usr/bin/env python3
"""Fast Notes / Sticky Notes capture for Quickshell desktop widget, synced with Obsidian.

Directly reads and writes Markdown in the Obsidian vault without requiring
Obsidian to be running or any third-party plugins. Thread-safe and atomic with
exclusive file locking and tempfile renaming.

Usage:
    obsidian_notes.py                      read entries, print JSON
    obsidian_notes.py --add "text"         append entry under today's date
    obsidian_notes.py --delete "entry_id"  delete entry by id
    obsidian_notes.py --toggle "entry_id"  check / uncheck entry by id
    obsidian_notes.py --edit ID "text"     replace an entry's text (time, check kept)
    obsidian_notes.py --clear-done         delete every checked entry
    obsidian_notes.py --clear              clear all notes
    obsidian_notes.py --open               open note in Obsidian via URI
"""

import argparse
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime

NOTE_NAME = "notas-rápidas.md"
FALLBACK_NOTE_NAME = "captura-rapida.md"
TITLE = "# Notas Rápidas"

# Matches:
# - 10:45 comprar pan
# - [ ] 10:45 comprar pan
# - [x] 10:45 comprar pan
ENTRY_RE = re.compile(r"^-\s+(?:\[([ xX])\]\s+)?(\d{2}:\d{2})\s+(.*)$")
DATE_RE = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})\s*$")


def find_vault():
    """Locate Obsidian vault path from Obsidian's official registry."""
    override = os.environ.get("QS_OBSIDIAN_VAULT")
    if override and os.path.isdir(override):
        return override

    config = os.path.expanduser("~/.config/obsidian/obsidian.json")
    try:
        with open(config, encoding="utf-8") as f:
            vaults = json.load(f).get("vaults", {})
    except (OSError, ValueError):
        vaults = {}

    for entry in vaults.values():
        if entry.get("open") and os.path.isdir(entry.get("path", "")):
            return entry["path"]

    known = [v for v in vaults.values() if os.path.isdir(v.get("path", ""))]
    if known:
        return max(known, key=lambda v: v.get("ts", 0))["path"]

    # Fallback to standard path
    default_path = os.path.expanduser("~/Documents/Obsidian")
    if os.path.isdir(default_path):
        return default_path

    return None


def get_note_path(vault):
    """Determine the file path for fast notes, preferring notas-rápidas.md."""
    path_primary = os.path.join(vault, NOTE_NAME)
    if os.path.exists(path_primary):
        return path_primary
    path_fallback = os.path.join(vault, FALLBACK_NOTE_NAME)
    if os.path.exists(path_fallback):
        return path_fallback
    return path_primary


def make_entry_id(date_str, time_str, text_str):
    """Generate a stable, unique hash identifier for a note entry."""
    raw = f"{date_str}_{time_str}_{text_str.strip()}"
    digest = hashlib.md5(raw.encode("utf-8")).hexdigest()[:8]
    clean_date = date_str.replace("-", "")
    clean_time = time_str.replace(":", "")
    return f"{clean_date}_{clean_time}_{digest}"


def format_date_display(date_str):
    """Format YYYY-MM-DD into friendly string: 'Hoy', 'Ayer', or 'DD Mon'."""
    try:
        dt = datetime.strptime(date_str, "%Y-%m-%d").date()
        today = datetime.now().date()
        diff = (today - dt).days
        if diff == 0:
            return "Hoy"
        elif diff == 1:
            return "Ayer"
        months = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
        return f"{dt.day} {months[dt.month - 1]}"
    except Exception:
        return date_str


def read_entries(path):
    """Read all entries from markdown file, newest first."""
    if not os.path.exists(path):
        return []

    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return []

    entries = []
    current_date = ""

    for line in lines:
        heading = DATE_RE.match(line)
        if heading:
            current_date = heading.group(1)
            continue
        entry = ENTRY_RE.match(line)
        if entry:
            checked = entry.group(1) in ("x", "X") if entry.group(1) else False
            time_str = entry.group(2)
            text_str = entry.group(3).strip()
            entry_id = make_entry_id(current_date, time_str, text_str)
            entries.append({
                "id": entry_id,
                "date": current_date,
                "dateDisplay": format_date_display(current_date),
                "time": time_str,
                "text": text_str,
                "checked": checked
            })

    entries.reverse()
    return entries


def lock_path_for(path):
    """Path for the exclusive runtime lock."""
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    digest = hashlib.sha1(path.encode("utf-8")).hexdigest()[:16]
    return os.path.join(runtime, f"quickshell-obsidian-notes-{digest}.lock")


def add_entry(path, text):
    """Append text under today's date heading with atomic file write."""
    text = " ".join(text.split())
    if not text:
        return

    now = datetime.now()
    today = now.strftime("%Y-%m-%d")
    stamp = now.strftime("%H:%M")
    entry_line = f"- [ ] {stamp} {text}"

    lock_file = lock_path_for(path)
    try:
        lock = open(lock_file, "w")
    except OSError:
        lock = None

    try:
        if lock is not None:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)

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
            lines.extend([f"## {today}", "", entry_line])
        else:
            end = len(lines)
            for i in range(start + 1, len(lines)):
                if lines[i].startswith("## "):
                    end = i
                    break
            while end > start + 1 and not lines[end - 1].strip():
                end -= 1
            lines.insert(end, entry_line)

        write_lines_atomic(path, lines)
    finally:
        if lock is not None:
            lock.close()


def edit_entries(path, change):
    """Rewrite the note, passing each entry to change(id, checked, time, text);
    it returns the line to keep (possibly new) or None to drop it. Date
    sections left without entries are removed."""
    if not os.path.exists(path):
        return

    lock_file = lock_path_for(path)
    try:
        lock = open(lock_file, "w")
    except OSError:
        lock = None

    try:
        if lock is not None:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)

        try:
            with open(path, encoding="utf-8") as f:
                lines = f.read().splitlines()
        except OSError:
            return

        new_lines = []
        current_date = ""
        for line in lines:
            heading = DATE_RE.match(line)
            if heading:
                current_date = heading.group(1)
            entry = ENTRY_RE.match(line)
            if entry:
                checked = entry.group(1) in ("x", "X")
                time_str, text_str = entry.group(2), entry.group(3).strip()
                line = change(make_entry_id(current_date, time_str, text_str), checked, time_str, text_str)
                if line is None:
                    continue
            new_lines.append(line)

        # Clean up empty date sections
        cleaned_lines = []
        j = 0
        while j < len(new_lines):
            if DATE_RE.match(new_lines[j]):
                k = j + 1
                has_entries = False
                while k < len(new_lines) and not new_lines[k].startswith("## "):
                    if ENTRY_RE.match(new_lines[k]):
                        has_entries = True
                        break
                    k += 1
                if not has_entries:
                    j = k
                    continue
            cleaned_lines.append(new_lines[j])
            j += 1

        write_lines_atomic(path, cleaned_lines)
    finally:
        if lock is not None:
            lock.close()


def task_line(checked, time_str, text_str):
    return f"- [{'x' if checked else ' '}] {time_str} {text_str}"


def delete_entry(path, target_id):
    edit_entries(path, lambda eid, c, t, x: None if eid == target_id else task_line(c, t, x))


def toggle_entry(path, target_id):
    edit_entries(path, lambda eid, c, t, x: task_line(c != (eid == target_id), t, x))


def edit_entry(path, target_id, text):
    text = " ".join(text.split())
    if text:
        edit_entries(path, lambda eid, c, t, x: task_line(c, t, text if eid == target_id else x))


def clear_done(path):
    edit_entries(path, lambda eid, c, t, x: None if c else task_line(c, t, x))


def clear_all(path):
    """Clear all notes, leaving only title."""
    write_lines_atomic(path, [TITLE, ""])


def write_lines_atomic(path, lines):
    """Safely write lines using a temp file rename."""
    directory = os.path.dirname(path) or "."
    try:
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".fastnotes-", suffix=".tmp")
    except OSError:
        return

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            content = "\n".join(lines).rstrip("\n")
            if content:
                content += "\n"
            f.write(content)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def open_obsidian(vault_name, note_name):
    """Open the note in Obsidian application via xdg-open."""
    file_stem = os.path.splitext(note_name)[0]
    uri = f"obsidian://open?vault={vault_name}&file={file_stem}"
    subprocess.Popen(["xdg-open", uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description="Quickshell Fast Notes Obsidian Sync")
    parser.add_argument("--add", metavar="TEXT", help="Add a new note")
    parser.add_argument("--delete", metavar="ID", help="Delete note by ID")
    parser.add_argument("--toggle", metavar="ID", help="Check / uncheck note by ID")
    parser.add_argument("--edit", nargs=2, metavar=("ID", "TEXT"), help="Replace note text")
    parser.add_argument("--clear", action="store_true", help="Clear all notes")
    parser.add_argument("--clear-done", action="store_true", help="Delete checked notes")
    parser.add_argument("--open", action="store_true", help="Open note in Obsidian")
    args = parser.parse_args()

    vault = find_vault()
    if not vault:
        json.dump({"error": "No se encontró ningún vault de Obsidian", "entries": [], "total": 0}, sys.stdout)
        sys.stdout.write("\n")
        return

    path = get_note_path(vault)
    note_name = os.path.basename(path)
    vault_name = os.path.basename(vault.rstrip("/"))

    if args.open:
        open_obsidian(vault_name, note_name)

    if args.clear:
        clear_all(path)
    elif args.clear_done:
        clear_done(path)
    elif args.delete:
        delete_entry(path, args.delete)
    elif args.edit:
        edit_entry(path, *args.edit)
    elif args.toggle:
        toggle_entry(path, args.toggle)
    elif args.add:
        add_entry(path, args.add)

    entries = read_entries(path)
    json.dump({
        "vault": vault,
        "vaultName": vault_name,
        "note": note_name,
        "path": path,
        "exists": os.path.exists(path),
        "total": len(entries),
        "entries": entries,
    }, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
