-- Written by the shell's Settings window (Hyprland page), through
-- ~/.config/quickshell/scripts/hypr_settings.py. Not meant to be
-- edited by hand: the next change made in the window rewrites it from
-- gui-settings.json. hyprland.lua runs this last, so these values win.

hl.config({
    general = {
        border_size = 0,
        gaps_in = 16,
        gaps_out = { top = 20, bottom = 22, left = 22, right = 22 },
    },
    input = {
        follow_mouse = 1,
    },
})
