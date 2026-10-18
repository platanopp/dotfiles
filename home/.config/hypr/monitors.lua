-- Written by the shell's Settings window (Displays page), through
-- ~/.config/quickshell/scripts/display_control.py. Not meant to be
-- edited by hand: the next change made there rewrites it. hyprland.lua
-- runs this after its own monitor rules, so these win.

hl.monitor({
    output = "DP-2",
    disabled = false,
    mode = "1920x1080@239.76Hz",
    position = "-1920x360",
    scale = 1,
    cm = "srgb",
})
hl.monitor({
    output = "HDMI-A-1",
    disabled = false,
    mode = "2560x1440@120Hz",
    position = "0x0",
    scale = 1,
    cm = "srgb",
})
