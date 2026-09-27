#!/usr/bin/env python3
"""A backup of the desktop's configuration in a git repository -- for
whoever is logged in, not for one machine's owner.

The repository is a copy of the live configuration, not symlinks to it:
sync.sh copies every path listed in manifest.txt (relative to $HOME) into
<repo>/home/, and a commit records it. A repository made elsewhere with the
same two files works as it is; one made here gets them written.

  status [REPO]   JSON: where it is, whether it exists, its remote (and whether
                  that remote is public), the last commit, what is not yet
                  committed, what is not yet pushed, and whether GitHub is
                  reachable through `gh` for this user
  init [REPO]     make one: git init, a manifest of the configuration this user
                  actually has, sync.sh, a first commit. Local only.
  backup [REPO]   sync, then one commit of whatever changed. Local only.
  push [REPO]     git push, with gh's credentials for this one command when gh
                  is logged in; the git config is never touched.
  github [REPO]   no remote yet: create a PRIVATE GitHub repository with gh and
                  push to it.

REPO defaults to ~/dotfiles.
"""

import json
import os
import re
import subprocess
import sys
import urllib.request

HOME = os.path.expanduser("~")

# What a new backup keeps, if this user has it. An allowlist rather than
# "everything under ~/.config": most of that is caches, browser profiles and
# session tokens, and a backup can end up public.
DEFAULT_MANIFEST = [
    ".config/quickshell", ".config/hypr",
    ".zshrc", ".zprofile", ".profile", ".bashrc", ".bash_profile",
    ".config/fish", ".config/zsh", ".config/starship.toml",
    ".config/kitty", ".config/alacritty", ".config/foot",
    ".config/nvim", ".config/yazi", ".config/fastfetch",
    ".config/gtk-3.0/settings.ini", ".config/gtk-4.0/settings.ini",
    ".config/qt5ct", ".config/qt6ct", ".config/mimeapps.list",
]

SYNC_SH = r'''#!/usr/bin/env bash
# Pull the live configuration into this repository: every path in
# manifest.txt (relative to $HOME) is copied into home/. Written by the
# shell's Settings window; edit the manifest to change what is kept.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="$repo/home"
copied=0
while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs || true)"
    [ -z "$line" ] && continue
    src="$HOME/$line"
    [ -e "$src" ] || continue
    mkdir -p "$dest/$(dirname "$line")"
    if [ -d "$src" ]; then
        rsync -a --delete --exclude '.git/' --exclude '*.log' \
              --exclude 'Cache/' --exclude 'GPUCache/' --exclude '__pycache__/' \
              "$src/" "$dest/$line/"
    else
        cp -a "$src" "$dest/$line"
    fi
    copied=$((copied + 1))
done < "$repo/manifest.txt"
echo "synced $copied entries"
'''


def run(*args, timeout=30, **kw):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, **kw)
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(args, 1, "", str(e))


def repo_path(arg):
    return os.path.expanduser(arg) if arg else os.path.join(HOME, "dotfiles")


def git(repo, *args, **kw):
    return run("git", "-C", repo, *args, **kw)


def gh_ready():
    """gh installed and logged in for this user -- the only way this page
    pushes or creates repositories without asking for a password."""
    if not run("sh", "-c", "command -v gh").stdout.strip():
        return False
    return run("gh", "auth", "status", timeout=15).returncode == 0


def github_visibility(url):
    """'public', 'private' or None when it cannot be told. A public GitHub
    repository answers the API without credentials; a private one does not."""
    m = re.search(r"github\.com[:/]([^/]+)/([^/.]+?)(?:\.git)?$", url or "")
    if not m:
        return None
    try:
        with urllib.request.urlopen(
                f"https://api.github.com/repos/{m.group(1)}/{m.group(2)}", timeout=6) as r:
            return "private" if json.load(r).get("private") else "public"
    except Exception:
        return "private" if gh_ready() else None


def ensure_identity(repo):
    """git refuses to commit without a name and an email, and someone new on
    this machine may never have set them. Set here, for this repository only,
    and never globally: a GitHub noreply address when gh is logged in -- so a
    pushed backup carries no real address -- and user@localhost otherwise."""
    if git(repo, "config", "user.email").stdout.strip() and git(repo, "config", "user.name").stdout.strip():
        return
    user = os.environ.get("USER", "user")
    name, email = user, f"{user}@localhost"
    if gh_ready():
        try:
            me = json.loads(run("gh", "api", "user", timeout=20).stdout)
            name = me.get("name") or me.get("login") or user
            email = f"{me['id']}+{me['login']}@users.noreply.github.com"
        except (json.JSONDecodeError, KeyError, TypeError):
            pass
    else:
        gecos = run("getent", "passwd", user).stdout.split(":")
        if len(gecos) > 4 and gecos[4].split(",")[0].strip():
            name = gecos[4].split(",")[0].strip()
    if not git(repo, "config", "user.name").stdout.strip():
        git(repo, "config", "user.name", name)
    if not git(repo, "config", "user.email").stdout.strip():
        git(repo, "config", "user.email", email)


def sync(repo):
    script = os.path.join(repo, "sync.sh")
    if os.access(script, os.X_OK):
        run(script, timeout=180)


def status(repo):
    out = {"path": repo, "display": repo.replace(HOME, "~", 1), "exists": os.path.isdir(repo),
           "repo": os.path.isdir(os.path.join(repo, ".git")), "gh": gh_ready()}
    if not out["repo"]:
        return out
    out["sync"] = os.path.isfile(os.path.join(repo, "sync.sh"))
    sync(repo)
    log = git(repo, "log", "-1", "--format=%h%x09%cr%x09%s").stdout.strip().split("\t")
    out.update({"hash": log[0] if log and log[0] else "",
                "when": log[1] if len(log) > 1 else "",
                "subject": log[2] if len(log) > 2 else ""})
    out["pending"] = len([l for l in git(repo, "status", "--porcelain").stdout.splitlines() if l.strip()])
    remote = git(repo, "remote", "get-url", "origin").stdout.strip()
    out["remote"] = remote
    if remote:
        ahead = git(repo, "rev-list", "--count", "@{u}..HEAD").stdout.strip()
        out["unpushed"] = int(ahead) if ahead.isdigit() else int(
            git(repo, "rev-list", "--count", "HEAD").stdout.strip() or 0)
        out["visibility"] = github_visibility(remote)
    else:
        out["unpushed"] = 0
    return out


def init(repo):
    if os.path.isdir(os.path.join(repo, ".git")):
        return {"ok": True, "status": status(repo)}
    if os.path.exists(repo) and os.listdir(repo):
        return {"ok": False, "error": f"{repo} exists and is not empty"}
    os.makedirs(repo, exist_ok=True)
    present = [p for p in DEFAULT_MANIFEST if os.path.exists(os.path.join(HOME, p))]
    with open(os.path.join(repo, "manifest.txt"), "w") as fh:
        fh.write("# Paths under $HOME that sync.sh copies into home/. One per line.\n\n")
        fh.write("\n".join(present) + "\n")
    with open(os.path.join(repo, "sync.sh"), "w") as fh:
        fh.write(SYNC_SH)
    os.chmod(os.path.join(repo, "sync.sh"), 0o755)
    with open(os.path.join(repo, ".gitignore"), "w") as fh:
        fh.write("__pycache__/\n*.log\n")
    git(repo, "init", "-q", "-b", "main")
    ensure_identity(repo)
    sync(repo)
    git(repo, "add", "-A")
    c = git(repo, "commit", "-q", "-m", "chore: first backup of this desktop's configuration")
    if c.returncode != 0:
        return {"ok": False, "error": (c.stderr or c.stdout).strip() or "git commit failed -- is git's user.name set?"}
    return {"ok": True, "status": status(repo)}


def backup(repo):
    st = status(repo)
    if not st["repo"]:
        return {"ok": False, "error": "no backup repository yet"}
    if st["pending"] == 0:
        return {"ok": True, "committed": False, "status": st}
    ensure_identity(repo)
    git(repo, "add", "-A")
    names = git(repo, "diff", "--cached", "--name-only").stdout.split()
    tops = sorted({"/".join(n.split("/")[1:3]) for n in names if n.startswith("home/")}) or names[:10]
    body = "chore: backup from the Settings window\n\n" + "\n".join("- " + t for t in tops) + "\n"
    c = subprocess.run(["git", "-C", repo, "commit", "-q", "-F", "-"], input=body,
                       capture_output=True, text=True, timeout=60)
    if c.returncode != 0:
        return {"ok": False, "error": (c.stderr or c.stdout).strip()}
    return {"ok": True, "committed": True, "status": status(repo)}


def with_gh_credentials():
    if gh_ready():
        return ["-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential"]
    return []


def push(repo):
    r = run("git", "-C", repo, *with_gh_credentials(), "push", "--quiet", "-u", "origin", "HEAD",
            timeout=120, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    if r.returncode != 0:
        msg = (r.stderr or r.stdout).strip().split("\n")[-1]
        if "terminal prompts disabled" in msg or "could not read Username" in msg:
            msg = "needs credentials -- log in with `gh auth login`"
        return {"ok": False, "error": msg}
    return {"ok": True, "status": status(repo)}


def github(repo):
    if not gh_ready():
        return {"ok": False, "error": "log in with `gh auth login` first"}
    if git(repo, "remote", "get-url", "origin").stdout.strip():
        return {"ok": False, "error": "this backup already has a remote"}
    name = os.path.basename(repo.rstrip("/")) or "dotfiles"
    r = run("gh", "repo", "create", name, "--private", "--source", repo, "--remote", "origin",
            "--push", timeout=180)
    if r.returncode != 0:
        return {"ok": False, "error": (r.stderr or r.stdout).strip().split("\n")[-1]}
    return {"ok": True, "status": status(repo)}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    repo = repo_path(sys.argv[2] if len(sys.argv) > 2 else "")
    fn = {"status": status, "init": init, "backup": backup, "push": push, "github": github}.get(cmd)
    if not fn:
        sys.exit(__doc__)
    print(json.dumps(fn(repo)))


if __name__ == "__main__":
    main()
