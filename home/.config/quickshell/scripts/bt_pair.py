#!/usr/bin/env python3
"""Pair, trust and connect a Bluetooth device -- with an agent.

`bluetoothctl pair MAC` on its own has no agent to answer the device's
pairing request, and this session runs none (no blueman, no GNOME): bluetoothd
logs "No agent available", the pairing fails, and a device that needs an
encrypted link -- an Xbox Series controller over Bluetooth LE, say -- connects
and is dropped two seconds later. So this holds one bluetoothctl session open
with a NoInputNoOutput agent (the "just works" kind, right for controllers,
headphones and mice), makes the adapter pairable only for as long as it
pairs, and closes everything when done.

  bt_pair.py MAC

Prints the outcome on its last line: "Paired and connected" or "error: ...".
"""

import re
import subprocess
import sys
import threading
import time

TIMEOUT = 25


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", sys.argv[1]):
        sys.exit(__doc__)
    mac = sys.argv[1].upper()
    p = subprocess.Popen(["bluetoothctl", "--agent", "NoInputNoOutput"], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    log = []

    def reader():
        for line in p.stdout:
            line = re.sub(r"\x1b\[[0-9;]*[A-Za-z]|\x01|\x02", "", line).strip()
            if line:
                log.append(line)
    threading.Thread(target=reader, daemon=True).start()

    def send(cmd, pause=0.5):
        p.stdin.write(cmd + "\n")
        p.stdin.flush()
        time.sleep(pause)

    def wait_for(patterns, since):
        end = time.monotonic() + TIMEOUT
        while time.monotonic() < end:
            for line in log[since:]:
                for pat in patterns:
                    if pat in line:
                        return pat
            time.sleep(0.2)
        return None

    result = "error: timed out"
    try:
        send("default-agent")
        send("pairable on")
        mark = len(log)
        send(f"pair {mac}", 0)
        got = wait_for(["Pairing successful", "Failed to pair", "not available", "AlreadyExists"], mark)
        if got in ("Failed to pair", "not available"):
            detail = next((l for l in log[mark:] if got in l), got)
            result = "error: " + detail
        else:
            send(f"trust {mac}")
            mark = len(log)
            send(f"connect {mac}", 0)
            got = wait_for(["Connection successful", "Failed to connect"], mark)
            result = "Paired and connected" if got == "Connection successful" else \
                "error: paired, but " + (next((l for l in log[mark:] if "Failed" in l), "the connection timed out"))
    finally:
        try:
            send("pairable off")
            send("quit", 0.3)
        except (BrokenPipeError, OSError):
            pass
        p.terminate()
    print(result)


if __name__ == "__main__":
    main()
