#!/usr/bin/env python3
"""The Settings window's About page: what this machine is, read fresh from
the system for whoever is logged in -- nothing about it is written in.
The backup the page also shows is scripts/backup.py's.

Prints JSON: os, kernel, host, cpu, gpu, memory, hyprland, quickshell, uptime.
"""

import json
import os
import platform
import re
import subprocess
import sys

HOME = os.path.expanduser("~")


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


def main():
    print(json.dumps(info()))


if __name__ == "__main__":
    main()
