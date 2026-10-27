-- Written by the shell's Settings window (Hyprland page), through
-- ~/.config/quickshell/scripts/hypr_settings.py. Not meant to be
-- edited by hand: the next change made in the window rewrites it from
-- gui-settings.json. hyprland.lua runs this last, so these values win.

hl.config({
    decoration = {
        active_opacity = 0.88,
        blur = {
            enabled = true,
        },
        inactive_opacity = 0.76,
    },
    general = {
        border_size = 0,
        gaps_in = 13,
        gaps_out = { top = 13, bottom = 13, left = 13, right = 13 },
    },
    input = {
        follow_mouse = 1,
        float_switch_override_focus = 1,
    },
    cursor = {
        hide_on_key_press = false,
    },
    misc = {
        mouse_move_focuses_monitor = true,
    },
})
