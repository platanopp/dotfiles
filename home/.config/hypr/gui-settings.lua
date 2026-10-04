-- Written by the shell's Settings window (Hyprland page), through
-- ~/.config/quickshell/scripts/hypr_settings.py. Not meant to be
-- edited by hand: the next change made in the window rewrites it from
-- gui-settings.json. hyprland.lua runs this last, so these values win.

hl.config({
    input = {
        accel_profile = "adaptive",
        follow_mouse = 1,
    },
    decoration = {
        active_opacity = 0.88,
        inactive_opacity = 0.76,
    },
    general = {
        border_size = 0,
        gaps_in = 13,
        gaps_out = { top = 13, bottom = 13, left = 13, right = 13 },
    },
})
