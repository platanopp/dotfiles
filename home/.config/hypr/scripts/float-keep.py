#!/usr/bin/env python3
"""Keep a monitor's floating windows where they were across its unplugging.

  float-keep.py save MONITOR FILE      where they are, relative to MONITOR
  float-keep.py restore MONITOR FILE   put them back once MONITOR is back

The Xiaomi drops its HDMI link when idle-screens.sh switches it off, so
Hyprland removes it -- its workspaces move to the other monitor -- and adds
it again on waking. Its floating windows (the desktop widgets on workspace
11) came back 119 px lower every time: Hyprland carries them over by the
difference in the two monitors' positions, and back by something else. After
a few nights, btop was off the bottom of the screen. So their place is noted
before the monitor goes and set again when it is back.
"""
import json
import subprocess
import sys
import time


def hypr(what):
    return json.loads(subprocess.run(['hyprctl', '-j', what], capture_output=True, text=True).stdout or '[]')


def monitor(name):
    return next((m for m in hypr('monitors') if m['name'] == name), None)


def save(name, path):
    m = monitor(name)
    wins = []
    if m is not None:
        for c in hypr('clients'):
            if c.get('floating') and c.get('monitor') == m['id'] and c.get('mapped', True):
                wins.append({'address': c['address'], 'workspace': c['workspace']['id'],
                             'rx': c['at'][0] - m['x'], 'ry': c['at'][1] - m['y']})
    with open(path, 'w') as f:
        json.dump(wins, f)


def misplaced(m, wins):
    clients = {c['address']: c for c in hypr('clients')}
    out = []
    for w in wins:
        c = clients.get(w['address'])
        if c is None:
            continue  # closed meanwhile
        if c['workspace']['id'] != w['workspace']:
            continue  # moved away by hand meanwhile
        if c['at'] != [m['x'] + w['rx'], m['y'] + w['ry']]:
            out.append(w)
    return out


def restore(name, path):
    try:
        wins = json.load(open(path))
    except (OSError, ValueError):
        return
    # Hyprland adds the monitor a moment after its link is up, and only then
    # brings its workspaces back -- and the windows' wrong move with them.
    # Set them after that, and again should anything still move them.
    deadline = time.monotonic() + 10
    settled = 0
    while time.monotonic() < deadline:
        time.sleep(0.2)
        m = monitor(name)
        if m is None:
            continue
        todo = misplaced(m, wins)
        if not todo:
            settled += 1
            if settled >= 3:  # 0.6 s with nothing moving them
                return
            continue
        settled = 0
        for w in todo:
            x, y = m['x'] + w['rx'], m['y'] + w['ry']
            lua = f"hl.dispatch(hl.dsp.window.move({{ x = {x}, y = {y}, window = 'address:{w['address']}' }}))"
            subprocess.run(['hyprctl', 'eval', lua], capture_output=True)


def main():
    cmd, name, path = sys.argv[1:4]
    if cmd == 'save':
        save(name, path)
    elif cmd == 'restore':
        restore(name, path)


if __name__ == '__main__':
    main()
