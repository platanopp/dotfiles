#!/usr/bin/env python3
"""Updates for the shell, from the repository it is published in.

Whoever installed the shell from that repository (install.sh copies it into
$HOME) can bring ~/.config/quickshell up to the latest published version from
Settings -> About. Only the shell: Hyprland, the terminal and everything else
the dotfiles carry are left as this user has them -- their monitors, binds and
programs are theirs, and an update that rewrote them would undo that.

The published version is read from a copy of the repository of its own, in
~/.cache/quickshell-updates, cloned without file contents (--filter=blob:none)
and checked out only under home/.config/quickshell. It is not the user's
backup repository (scripts/backup.py), which holds their own configuration
and may point somewhere else entirely.

  status SOURCE BRANCH [BACKUP_REPO]
      JSON: the published head, and how this shell compares to it --
        current  the same files
        behind   an update is there; `files` differ, `commits` say what changed
        ahead    this user can push to SOURCE: they publish the shell, and
                 their copy being different means newer, not older
        error    `error` says why (offline, no git, ...)
  update SOURCE BRANCH [BACKUP_REPO]
      copy the shell as it is now into ~/.local/share/dotfiles-backups/<time>/,
      then replace it with the published one. Settings, the widget layout and
      anything git ignores (logs, caches) are this user's and are kept.
  restart
      restart Quickshell, detached, so the shell that asked can be replaced.
"""

import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
LIVE = os.path.join(HOME, ".config/quickshell")
IN_REPO = "home/.config/quickshell"
CACHE = os.path.join(HOME, ".cache/quickshell-updates/source")
STATE = os.path.join(HOME, ".local/state/quickshell-update.json")
BACKUPS = os.path.join(HOME, ".local/share/dotfiles-backups")

# This user's, not the shell's: never replaced, never deleted.
KEEP = {"shell-settings.json", "desktop-widgets.json"}
KEEP_DIRS = {"__pycache__", "logs", ".git"}

# Never ask for credentials: a public repository needs none, and a prompt
# would hang the process Settings is waiting on.
GIT_ENV = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="true", LC_ALL="C")


def git(*args, cwd=CACHE, timeout=60):
    return subprocess.run(["git", *args], cwd=cwd, env=GIT_ENV, capture_output=True,
                          text=True, timeout=timeout)


def out(data):
    print(json.dumps(data))
    sys.exit(0)


def ago(ts):
    s = max(0, int(time.time() - ts))
    if s < 3600:
        return "%d min ago" % max(1, s // 60)
    if s < 86400:
        return "%d h ago" % (s // 3600)
    d = s // 86400
    return "yesterday" if d == 1 else "%d days ago" % d


def display(url):
    return re.sub(r"^https?://|\.git$", "", url)


# ── The published copy ─────────────────────────────────────────────────

def fetch(source, branch):
    """Bring the cache to the published head; return its full hash."""
    if not os.path.isdir(os.path.join(CACHE, ".git")):
        shutil.rmtree(CACHE, ignore_errors=True)
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        r = git("clone", "--quiet", "--filter=blob:none", "--no-checkout", "--single-branch",
                "--branch", branch, source, CACHE, cwd=HOME, timeout=180)
        if r.returncode != 0:
            raise RuntimeError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "clone failed")
        git("sparse-checkout", "set", IN_REPO)
    else:
        # The source or the branch may have been changed in the settings.
        git("remote", "set-url", "origin", source)
        git("config", "remote.origin.fetch", "+refs/heads/%s:refs/remotes/origin/%s" % (branch, branch))
        r = git("fetch", "--quiet", "--filter=blob:none", "origin", timeout=120)
        if r.returncode != 0:
            raise RuntimeError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "fetch failed")
    r = git("checkout", "--quiet", "--force", "origin/" + branch, timeout=180)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "checkout failed")
    return git("rev-parse", "HEAD").stdout.strip()


def files_under(root):
    found = set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in KEEP_DIRS]
        for f in filenames:
            rel = os.path.relpath(os.path.join(dirpath, f), root)
            if rel in KEEP or f.endswith(".pyc"):
                continue
            found.add(rel)
    return found


def ignored(paths):
    """Of these shell paths, the ones the repository ignores: local, kept."""
    if not paths:
        return set()
    r = subprocess.run(["git", "check-ignore", "--no-index", "--stdin"], cwd=CACHE, env=GIT_ENV,
                       input="\n".join(IN_REPO + "/" + p for p in paths), capture_output=True, text=True)
    return {line[len(IN_REPO) + 1:] for line in r.stdout.splitlines()}


# What the repository keeps wherever a path into the publisher's home folder
# was (its sync.sh puts it there). Spelled in two pieces: whole, it would be
# filled in here too, by install.sh and by this very updater.
HOME_TOKEN = ("@" + "HOME@").encode()


def published(rel):
    """A published file as it reads on this machine: this user's home put
    back where the repository keeps HOME_TOKEN."""
    with open(os.path.join(CACHE, IN_REPO, rel), "rb") as f:
        return f.read().replace(HOME_TOKEN, HOME.encode())


def live(rel):
    with open(os.path.join(LIVE, rel), "rb") as f:
        return f.read()


def compare(base):
    """(changed or new upstream, removed upstream since BASE)

    A file only this shell has is deleted only if the published shell had it
    at BASE and has since dropped it. Anything else there is the user's own,
    and stays -- with no BASE to tell the two apart, all of it stays."""
    up = files_under(os.path.join(CACHE, IN_REPO))
    here = files_under(LIVE)
    changed = sorted(p for p in up if p not in here or published(p) != live(p))
    extra = here - up
    if not base or not extra:
        return changed, []
    r = git("ls-tree", "-r", "--name-only", base, "--", IN_REPO)
    before = {line[len(IN_REPO) + 1:] for line in r.stdout.splitlines()}
    dropped = extra & before
    return changed, sorted(dropped - ignored(sorted(dropped)))


# ── Who publishes ───────────────────────────────────────────────────────

def can_push(source):
    """Whether this user can push to SOURCE, by gh: then they are its author,
    and a shell different from the published one is ahead of it, not behind."""
    m = re.search(r"github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/?$", source)
    if not m or not shutil.which("gh"):
        return False
    try:
        r = subprocess.run(["gh", "api", "repos/%s/%s" % m.groups(), "--jq", ".permissions.push"],
                           capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.returncode == 0 and r.stdout.strip() == "true"


# ── What changed ────────────────────────────────────────────────────────

def baseline(backup_repo):
    """The published commit this shell was installed from: the one recorded by
    the last update, or else the newest commit of the user's own clone that the
    published history also has (install.sh ran from a clone).

    Looked up in the published history listed once, not commit by commit: the
    cache is a partial clone, and asking it for a commit it lacks makes git go
    and fetch it -- a round trip to GitHub for every local commit there is."""
    history = set(git("rev-list", "HEAD").stdout.split())
    try:
        with open(STATE) as f:
            c = json.load(f).get("commit", "")
        if c in history:
            return c
    except (OSError, ValueError):
        pass
    repo = os.path.expanduser(backup_repo or "")
    if repo and os.path.isdir(os.path.join(repo, ".git")):
        r = subprocess.run(["git", "rev-list", "--max-count=300", "HEAD"], cwd=repo, env=GIT_ENV,
                           capture_output=True, text=True)
        for c in r.stdout.split():
            if c in history:
                return c
    return ""


def commits_since(base):
    rng = [base + "..HEAD"] if base else ["--max-count=5", "HEAD"]
    r = git("log", "--format=%h%x1f%s%x1f%ct", *rng, "--", IN_REPO)
    rows = []
    for line in r.stdout.splitlines():
        h, s, t = line.split("\x1f")
        rows.append({"hash": h, "subject": s, "when": ago(int(t))})
    return rows


def record(commit):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE + ".tmp", "w") as f:
        json.dump({"commit": commit, "at": int(time.time())}, f)
    os.replace(STATE + ".tmp", STATE)


# ── Commands ────────────────────────────────────────────────────────────

def status(source, branch, backup_repo):
    base = {"source": display(source), "branch": branch}
    if not shutil.which("git"):
        out(dict(base, state="error", error="git is not installed"))
    try:
        head = fetch(source, branch)
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
        out(dict(base, state="error", error=str(e) or "could not reach the repository"))

    when = int(git("log", "-1", "--format=%ct", "HEAD").stdout.strip() or 0)
    base.update(head=head[:7], when=ago(when) if when else "")
    since = baseline(backup_repo)
    changed, gone = compare(since)
    if not changed and not gone:
        record(head)
        out(dict(base, state="current"))
    if can_push(source):
        out(dict(base, state="ahead", files=len(changed) + len(gone)))

    rows = commits_since(since)
    out(dict(base, state="behind", files=len(changed) + len(gone),
             commits=rows[:8], more=max(0, len(rows) - 8)))


def update(source, branch, backup_repo):
    try:
        head = fetch(source, branch)
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
        out({"ok": False, "error": str(e) or "could not reach the repository"})
    if can_push(source):
        out({"ok": False, "error": "this machine publishes the shell; upload from Backup instead"})

    changed, gone = compare(baseline(backup_repo))
    if not changed and not gone:
        record(head)
        out({"ok": True, "files": 0})

    # The whole shell as it was, kept the way install.sh keeps what it moves
    # aside: under the same path, in a folder named for the moment.
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    saved = os.path.join(BACKUPS, stamp, ".config/quickshell")
    shutil.copytree(LIVE, saved, symlinks=True,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "logs"))

    for rel in changed:
        dst = os.path.join(LIVE, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        # Written beside and renamed over, so the running shell never reads a
        # half-copied file when it reloads. The mode comes along: the scripts
        # are run as programs.
        with open(dst + ".update-tmp", "wb") as f:
            f.write(published(rel))
        shutil.copymode(os.path.join(CACHE, IN_REPO, rel), dst + ".update-tmp")
        os.replace(dst + ".update-tmp", dst)
    for rel in gone:
        os.remove(os.path.join(LIVE, rel))
        d = os.path.dirname(os.path.join(LIVE, rel))
        while d != LIVE and os.path.isdir(d) and not os.listdir(d):
            os.rmdir(d)
            d = os.path.dirname(d)

    record(head)
    out({"ok": True, "files": len(changed) + len(gone), "saved": saved.replace(HOME, "~", 1)})


def restart():
    # Detached into a session of its own: the shell that ran this is about to
    # be stopped, and takes its children with it. A file-by-file reload is not
    # enough after an update -- widgets loaded by URL keep their old code.
    subprocess.Popen(["sh", "-c", "sleep 1; pkill -x quickshell; pkill -x qs; "
                      "while pgrep -x quickshell >/dev/null || pgrep -x qs >/dev/null; do sleep 0.2; done; "
                      "setsid -f quickshell >/dev/null 2>&1"],
                     start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out({"ok": True})


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ("status", "update", "restart"):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    if args[0] == "restart":
        restart()
    if len(args) < 3:
        out({"ok": False, "state": "error", "error": "no source configured"})
    source, branch = args[1], args[2]
    backup_repo = args[3] if len(args) > 3 else ""
    (status if args[0] == "status" else update)(source, branch, backup_repo)


if __name__ == "__main__":
    main()
