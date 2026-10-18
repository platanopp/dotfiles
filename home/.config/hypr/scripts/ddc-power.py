#!/usr/bin/env python3
"""DDC/CI power for the Xiaomi, spoken straight over its I2C bus.

  ddc-power.py BUS off      switch the monitor off (VCP D6 = 05)
  ddc-power.py BUS on [CONNECTOR]
                            switch it on (D6 = 01), and wait for its link
                            (CONNECTOR: Hyprland's name for it, HDMI-A-1)
  ddc-power.py BUS get CODE read a VCP feature: "current max"
  ddc-power.py find         the bus of the monitor made by XMI

What ddcutil does for these, minus what made it slow. Asked to switch on a
monitor that is off, ddcutil first identifies it -- probes the VCP version,
retries when it gets no answer -- and only then writes: 4.4 s on 2026-10-18,
before the monitor had even been told. A Set VCP Feature is one 7-byte
message to I2C address 0x37 (VESA DDC/CI), so it is sent here at once, and
again every 0.3 s until the monitor's HDMI link comes back: the monitor's
controller (MStar) wakes on the first one it hears; the repeats cover one
sent while it was not listening.

The bus is found while the monitor is on (`find`, by the manufacturer ID in
the EDID at 0x50) and kept by idle-screens.sh: switched off, the monitor
drops its HDMI link and Hyprland forgets it, but its I2C bus still answers.
"""
import fcntl
import os
import sys
import time

I2C_SLAVE = 0x0703
DDC_ADDR = 0x37
EDID_ADDR = 0x50
HOST = 0x51          # source address byte of host messages
DEST = 0x6E          # the display's write address (0x37 << 1), seeds the checksum


def checksum(data, seed=DEST):
    c = seed
    for b in data:
        c ^= b
    return c


def open_bus(bus, addr):
    fd = os.open(f'/dev/i2c-{bus}', os.O_RDWR)
    fcntl.ioctl(fd, I2C_SLAVE, addr)
    return fd


def set_vcp(bus, code, value):
    msg = [HOST, 0x84, 0x03, code, (value >> 8) & 0xFF, value & 0xFF]
    fd = open_bus(bus, DDC_ADDR)
    try:
        os.write(fd, bytes(msg + [checksum(msg)]))
    finally:
        os.close(fd)


def get_vcp(bus, code):
    msg = [HOST, 0x82, 0x01, code]
    fd = open_bus(bus, DDC_ADDR)
    try:
        os.write(fd, bytes(msg + [checksum(msg)]))
        time.sleep(0.05)  # DDC/CI: 40 ms before the reply may be read
        r = os.read(fd, 11)
    finally:
        os.close(fd)
    # 6E 88 02 result code type maxH maxL curH curL chk
    if len(r) < 11 or r[2] != 0x02 or r[3] != 0x00 or r[4] != code:
        raise OSError(f'bad reply {r.hex()}')
    if checksum(r[:10], 0x50) != r[10]:
        raise OSError(f'bad checksum {r.hex()}')
    return r[8] << 8 | r[9], r[6] << 8 | r[7]


def find(mfg='XMI'):
    for name in sorted(os.listdir('/dev')):
        if not name.startswith('i2c-'):
            continue
        bus = int(name[4:])
        try:
            fd = open_bus(bus, EDID_ADDR)
            try:
                os.write(fd, b'\x00')
                edid = os.read(fd, 16)
            finally:
                os.close(fd)
        except OSError:
            continue
        if edid[:8] != b'\x00\xff\xff\xff\xff\xff\xff\x00':
            continue
        word = edid[8] << 8 | edid[9]
        code = ''.join(chr(((word >> s) & 0x1F) + 64) for s in (10, 5, 0))
        if code == mfg:
            return bus
    return None


def link_up(connector):
    """True once the monitor's connector (any HDMI one, if not named) is up."""
    base = '/sys/class/drm'
    for c in os.listdir(base):
        if c.endswith('-' + connector) if connector else 'HDMI' in c:
            try:
                if open(f'{base}/{c}/status').read().strip() == 'connected':
                    return True
            except OSError:
                pass
    return False


def main():
    a = sys.argv[1:]
    if a == ['find']:
        bus = find()
        if bus is None:
            sys.exit(1)
        print(bus)
        return
    bus = int(a[0])
    if a[1] == 'off':
        set_vcp(bus, 0xD6, 0x05)
    elif a[1] == 'on':
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            try:
                set_vcp(bus, 0xD6, 0x01)
            except OSError:
                pass  # not listening yet: NACK
            time.sleep(0.3)
            if link_up(a[2] if len(a) > 2 else None):
                return
        sys.exit(1)
    elif a[1] == 'get':
        cur, mx = get_vcp(bus, int(a[2], 16))
        print(cur, mx)


if __name__ == '__main__':
    main()
