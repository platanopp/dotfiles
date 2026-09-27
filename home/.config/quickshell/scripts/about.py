#!/usr/bin/env python3
"""The Settings window's About page: what this machine is, and how current
its backup in ~/dotfiles is.

  info     JSON: os, kernel, host, cpu, gpu, memory, hyprland, quickshell, uptime
  status   JSON: the repo's last commit, changes not yet committed, commits
           not yet pushed. Runs sync.sh first, so "not yet committed" means
           the live configuration, not the last copy of it.
  backup   sync.sh, then one commit of everything it brought in. Local only.
  push     git push, with gh's credentials for this one command -- the git
           config is not touched. The repo is public: the page asks twice.
"""

import json
import os
import platform
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
REPO = os.path.join(HOME, "dotfiles")


def run(*args, timeout=20, **kw):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, **kw)
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(args, 1, "", str(e))


def first_line(path, pattern):
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(pattern, line)
                if m:
                    return m.group(1).strip().strip('"')
    except OSError:
        pass
    return ""


def info():
    mem_kb = first_line("/proc/meminfo", r"MemTotal:\s+(\d+)")
    up = float(open("/proc/uptime").read().split()[0])
    d, h, m = int(up // 86400), int(up % 86400 // 3600), int(up % 3600 // 60)
    hypr = ""
    try:
        hypr = json.loads(run("hyprctl", "version", "-j").stdout).get("tag", "")
    except json.JSONDecodeError:
        pass
    qs = run("qs", "--version").stdout.strip().split("\n")[0]
    return {
        "os": first_line("/etc/os-release", r'PRETTY_NAME=(.*)') or platform.system(),
        "kernel": platform.release(),
        "host": platform.node(),
        "cpu": re.sub(r"\s+", " ", first_line("/proc/cpuinfo", r"model name\s*:\s*(.*)")),
        "gpu": run("nvidia-smi", "--query-gpu=name", "--format=csv,noheader").stdout.strip().split("\n")[0],
        "memory": f"{round(int(mem_kb) / 1048576)} GB" if mem_kb else "",
        "hyprland": hypr.lstrip("v"),
        "quickshell": re.sub(r"^quickshell\s*", "", qs, flags=re.I),
        "uptime": (f"{d}d " if d else "") + f"{h}h {m}m",
    }


def git(*args, **kw):
    return run("git", "-C", REPO, *args, **kw)


def status():
    if not os.path.isdir(os.path.join(REPO, ".git")):
        return {"repo": False}
    sync = os.path.join(REPO, "sync.sh")
    if os.access(sync, os.X_OK):
        run(sync, timeout=120)
    log = git("log", "-1", "--format=%h%x09%cr%x09%s").stdout.strip().split("\t")
    pending = [l for l in git("status", "--porcelain", "--", "home", "manifest.txt", "packages").stdout.splitlines() if l.strip()]
    ahead = git("rev-list", "--count", "@{u}..HEAD").stdout.strip()
    return {
        "repo": True,
        "hash": log[0] if log else "",
        "when": log[1] if len(log) > 1 else "",
        "subject": log[2] if len(log) > 2 else "",
        "pending": len(pending),
        "unpushed": int(ahead) if ahead.isdigit() else 0,
        "remote": git("remote", "get-url", "origin").stdout.strip(),
    }


def backup():
    st = status()
    if not st.get("repo"):
        return {"ok": False, "error": "no ~/dotfiles repository"}
    if st["pending"] == 0:
        return {"ok": True, "committed": False, "status": st}
    git("add", "-A", "home", "manifest.txt", "packages")
    names = git("diff", "--cached", "--name-only").stdout.split()
    tops = sorted({"/".join(n.split("/")[1:3]) for n in names if n.startswith("home/")})
    body = "chore: backup from the Settings window\n\n" + "\n".join("- " + t for t in tops) + "\n"
    c = subprocess.run(["git", "-C", REPO, "commit", "-q", "-F", "-"], input=body,
                       capture_output=True, text=True, timeout=60)
    if c.returncode != 0:
        return {"ok": False, "error": c.stderr.strip()}
    return {"ok": True, "committed": True, "status": status()}


def push():
    r = run("git", "-C", REPO, "-c", "credential.helper=", "-c",
            "credential.helper=!gh auth git-credential", "push", "--quiet",
            timeout=90, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    if r.returncode != 0:
        return {"ok": False, "error": (r.stderr or r.stdout).strip().split("\n")[-1]}
    return {"ok": True, "status": status()}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "info"
    out = {"info": info, "status": status, "backup": backup, "push": push}.get(cmd)
    if not out:
        sys.exit(__doc__)
    print(json.dumps(out()))


if __name__ == "__main__":
    main()
