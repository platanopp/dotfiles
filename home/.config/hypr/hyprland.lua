hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

local terminal = "kitty"
local fileManager = "kitty --class yazi -e yazi"
local mainMod = "SUPER"

hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("GTK_THEME", "Adwaita-dark")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.on("hyprland.start", function()
    hl.exec_cmd("veilad")
    hl.exec_cmd("systemctl --user start graphical-session.target")
    hl.timer(function()
     hl.exec_cmd("nvibrant 300 0 0 600")
      end, { timeout = 2000, type = "oneshot" })
    hl.exec_cmd("kitty")
    -- Chat and the game client, parked on workspace 2 by the rules further
    -- down so they come up behind the terminal instead of over it.
    hl.exec_cmd("discord")
    hl.exec_cmd("steam")
    hl.exec_cmd("quickshell")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    -- Take the virtual display back out of the layout once the real panels
    -- have enumerated. The monitor rule below has to bring DP-1 up enabled --
    -- a login with every panel switched off has nowhere else to draw -- but
    -- with panels attached it is just a phantom screen the pointer can wander
    -- onto. detach only fires when something else is enabled, so the headless
    -- case keeps it. Delayed for the same reason nvibrant is: at this point
    -- the outputs are not necessarily up yet.
    hl.timer(function()
        hl.exec_cmd("$HOME/.config/quickshell/scripts/virtual-display.sh detach")
    end, { timeout = 3000, type = "oneshot" })
end)

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 50,
        border_size = 2,
        col = {
            active_border   = { colors = {"rgba(33ccffee)", "rgba(00ff99ee)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding       = 10,
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
        blur = {
            enabled           = true,
            size              = 6,
            passes            = 3,
            new_optimizations = true,
            vibrancy          = 0.1696,
        },
    },
    animations = {
        enabled = true,
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

hl.config({
    dwindle = {
        preserve_split = true,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})

hl.config({
    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo   = false,
    },
})

hl.config({
    input = {
        kb_layout  = "latam",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})

hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
-- Handled inside the shell, which registers the name over Hyprland's
-- global-shortcuts protocol -- see the GlobalShortcut in shell.qml.
-- Locking is in there too so the screen can fade out before veila's lock
-- surface arrives and fade back in once it lets go.
hl.bind(mainMod .. " + L", hl.dsp.global("quickshell:lock"))
hl.bind(mainMod .. " + space", hl.dsp.global("quickshell:launcher"))
hl.bind(mainMod .. " + F", hl.dsp.global("quickshell:keybinds"))
hl.bind(mainMod .. " + W", hl.dsp.global("quickshell:wallpapers"))
hl.bind(mainMod .. " + ALT + Z", hl.dsp.global("quickshell:micmute"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume",   hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",   hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),      { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.global("quickshell:micmute"),                                { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                   { locked = true, repeating = true })

hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(
    "grimblast --notify copysave area " ..
    os.getenv("HOME") .. "/Pictures/Screenshots/screenshot_" ..
    os.date("%Y-%m-%d_%H-%M-%S") .. ".png"
))

local suppressMaximizeRule = hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "yazi-floating",
    match = { class = "^yazi$" },
    float = true,
    size  = "60% 70%",
    center = true,
})

hl.window_rule({
    name  = "kitty-float",
    match = { class = "^kitty$" },
    float = true,
    size  = "901 478",
    center = true,
})
hl.layer_rule({
    name  = "quickshell-xray",
    match = { namespace = "quickshell" },
    xray  = true,
})
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- ── Chat and games keep to workspace 2 ─────────────────────────────
--
-- By rule and not by an argument on the exec above: both take long enough to
-- start that the workspace focused at launch is not necessarily the one still
-- focused when their window finally maps, and Steam maps a splash first and
-- its real window second. `silent` places them without dragging focus along,
-- so a login that starts on workspace 1 stays there.
hl.window_rule({
    name      = "discord-on-2",
    match     = { class = "^discord$" },
    workspace = "2 silent",
})
hl.window_rule({
    name      = "steam-on-2",
    -- Anything launched from Steam gets its own class (steam_app_...), so
    -- this catches the client and its dialogs and no actual game.
    match     = { class = "^steam$" },
    workspace = "2 silent",
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move  = "20 monitor_h-120",
    float = true,
})

hl.layer_rule({
    name  = "quickshell-bar-blur",
    match = { namespace = "^quickshell:bar-blur$" },
    blur  = true,
    -- Blur covers the whole rectangular surface, so without this the
    -- transparent margin around each rounded widget renders as a blurred
    -- square. Pixels below this alpha are left unblurred.
    ignore_alpha = 0.3,
})

hl.layer_rule({
    name  = "quickshell-keybinds-blur",
    match = { namespace = "^quickshell:keybinds$" },
    blur  = true,
    -- The cheatsheet's own dim is what gets blurred through, so the
    -- threshold sits below it: at the bar's 0.3 the blur would snap in
    -- partway through the fade instead of coming up with it. Closed, the
    -- surface draws nothing at all and no pixel clears this.
    ignore_alpha = 0.02,
    -- Overrides the catch-all quickshell xray rule above. Xray blurs to the
    -- wallpaper and ignores the windows in between, which is right for the
    -- bar sitting over a workspace but not for a sheet thrown over the work
    -- itself -- the point is to see that this is on top of something.
    xray = false,
})

hl.layer_rule({
    name  = "quickshell-wallpapers-blur",
    match = { namespace = "^quickshell:wallpapers$" },
    blur  = true,
    -- Same reasoning as the cheatsheet above: the picker's own dim is what
    -- gets blurred through, so the threshold sits under it rather than at
    -- the bar's 0.3.
    ignore_alpha = 0.02,
    -- And the same override of the catch-all xray rule, for a sharper
    -- reason here: xray blurs to the wallpaper. A wallpaper picker that
    -- shows the old wallpaper through itself is judging every candidate
    -- against the thing it is meant to replace.
    xray = false,
})

hl.layer_rule({
    name  = "quickshell-launcher-blur",
    match = { namespace = "^quickshell:launcher$" },
    blur  = true,
    -- The bar's threshold, not the cheatsheet's, because the launcher does
    -- not dim the screen: everything outside the panel is fully transparent
    -- and must stay unblurred, so only the panel itself clears this. At the
    -- 0.02 the overlays use, the whole screen would blur the moment the
    -- launcher opened -- which is the thing that was asked to stop.
    ignore_alpha = 0.3,
    -- Overrides the catch-all quickshell xray rule. Xray blurs to the
    -- wallpaper and ignores the windows in between; the panel is meant to
    -- take its frosting from whatever it was opened on top of.
    xray = false,
})

-- ── Was hyprland-gui.lua ─────────────────────────────────────────────────
--
-- HyprMod kept its settings in a generated hyprland-gui.lua that this file
-- pulled in with require(). That file is gone from the load path now and
-- everything lives here, so there is one config to read and one to edit.
--
-- Do not point HyprMod's config-path at this file to get the same effect:
-- it rewrites its managed file wholesale from its own state, so it would
-- replace everything above with the handful of settings its UI knows about.
-- Editing here means not running HyprMod (or treating whatever it writes as
-- something to merge in by hand).
--
-- Kept as a layer rather than folded into the blocks above, because that is
-- the order the settings were resolved in before: where a key appears twice,
-- the one down here is the one that was winning.

-- Posy's Improved Cursor, the white set. rose-pine's was a muted rose-grey
-- that went missing against the wallpapers this desktop runs.
--
-- The white one of the eight in the set, measured rather than taken from the
-- name: 59% white pixels against 40% black. That black is the outline, and it
-- is the whole point of the design -- the pointer stays readable on a white
-- page and on a dark one. Posy_Cursor_Strokeless is whiter still, at 93%, but
-- only because the outline is gone.
--
-- From github.com/simtrami/posy-improved-cursor-linux, which ships XCursor
-- only, so this is `hyprcursor-util --extract` then `--create` over it. 17
-- real shapes and 133 aliases, and the aliases survive the conversion as
-- define_override entries -- checked, because a lost alias means an app asking
-- for `left_ptr` silently falls back.
--
-- Under ~/.local/share/icons, so nothing in /usr is touched.
hl.env("HYPRCURSOR_THEME", "Posy_Cursor-hyprcursor")
hl.env("HYPRCURSOR_SIZE", "28")

-- The XCursor half, for XWayland and anything that does not speak hyprcursor.
-- It was never set at all until now, which left those apps on the default --
-- so half the screen would have gone on showing a different pointer.
hl.env("XCURSOR_THEME", "Posy_Cursor")

-- ── Shake to find ────────────────────────────────────────────────────────
--
-- Shaking the mouse magnifies the pointer, the way macOS and Plasma do it.
-- Hyprland has no such option -- checked the stubs, hyprctl and the binary --
-- so it comes from the dynamic-cursors plugin, built from source against this
-- exact Hyprland commit (the author pins one plugin commit per Hyprland
-- release, and v0.56.2 is pinned). Provenance is in the .version file next to
-- the .so.
--
-- Guarded rather than called outright: `hyprctl reload` re-runs this file, and
-- loading an already-loaded plugin a second time is not something to find out
-- about the hard way. pcall because get_loaded_plugins is the plugin API
-- talking, and this file has to parse even when that is not there yet.
--
-- NOTE: the plugin has to be rebuilt after every Hyprland update. It will
-- refuse to load against a version it was not built for, and the pointer goes
-- back to being a plain one -- annoying, not broken.
local dynamicCursorsPath = os.getenv("HOME") .. "/.local/share/hyprland/plugins/dynamic-cursors.so"

local function pluginLoaded(name)
    local ok, plugins = pcall(hl.get_loaded_plugins)
    if not ok or type(plugins) ~= "table" then return false end
    for _, plugin in ipairs(plugins) do
        if plugin.name == name then return true end
    end
    return false
end

-- The .so is not in the dotfiles repo: it is a binary tied to one Hyprland
-- build, and a restored machine would have the wrong one. So its absence is a
-- normal state to parse through, not an error -- rebuild it with
-- `make all` in a clone of the plugin repo, at the commit its hyprpm.toml
-- pins for the Hyprland version in use.
local function fileExists(path)
    local handle = io.open(path, "r")
    if handle == nil then return false end
    handle:close()
    return true
end

if fileExists(dynamicCursorsPath) and not pluginLoaded("dynamic-cursors") then
    hl.plugin.load(dynamicCursorsPath)
end

-- The key is written with an underscore. `["dynamic-cursors"]`, which is what
-- the plugin calls itself everywhere else, is rejected as an unknown config
-- key -- the Lua API normalises the hyphen and does not accept the original.
hl.config({
    plugin = {
        dynamic_cursors = {
            enabled = true,
            shake = {
                enabled = true,
                -- How readily a shake counts as one, where the
                -- magnification starts, and how fast it grows while shaking.
                threshold = 6.0,
                base = 4.0,
                speed = 4.0,

                -- How long it stays big after the shake ends. The default is
                -- 2000, which reads as the pointer being stuck large; macOS
                -- starts shrinking the moment you stop, so: none.
                --
                -- 0 is a plain duration here, not a "no limit" sentinel --
                -- `end = now + timeout`, and the next tick past `end` sets the
                -- zoom back. The tick is a 500us event-loop timer rather than
                -- something driven by pointer motion, so this still fires with
                -- the mouse sitting perfectly still.
                --
                -- The shrink itself animates over 400ms on a bezier the plugin
                -- hardcodes, so this is not an abrupt snap. If a shake ever
                -- flickers mid-way -- the detector dipping under the threshold
                -- for a tick and the pointer bouncing small and large again --
                -- raise this to about 150 and it will ride over it.
                timeout = 0,
            },
        },
    },
})

hl.config({
    cursor = {
        hide_on_key_press = false,
        zoom_factor = 1.0,
    },
    decoration = {
        active_opacity = 0.88,
        blur = {
            ignore_opacity = true,
            noise = 0.014,
            passes = 3,
            size = 5,
            vibrancy = 0.14,
            xray = true,
        },
        dim_inactive = false,
        inactive_opacity = 0.7,
        rounding = 25,
        rounding_power = 2.0,
        shadow = {
            color = "0x77000000",
            color_inactive = "0xee1a1a1a",
            enabled = true,
            range = 8,
            render_power = 1,
            scale = 1.0,
        },
    },
    dwindle = {
        smart_resizing = true,
    },
    general = {
        border_size = 0,
        col = {
            active_border = {
                colors = {"rgba(33ccffee)", "rgba(00ff99ee)"},
            },
        },
        gaps_in = 15,
        gaps_out = 30,
        layout = "dwindle",
        snap = {
            enabled = false,
        },
    },
    input = {
        scroll_factor = 1.7,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

hl.animation({
    leaf = "windows",
    enabled = true,
    speed = 4.79,
    bezier = "default",
})

-- After the catch-all monitor rule at the top of the file, so these win for
-- the two outputs actually attached.
hl.monitor({
    output = "DP-2",
    disabled = false,
    mode = "1920x1080@239.76Hz",
    position = "-1920x240",
    scale = 1,
    cm = "srgb",
})
hl.monitor({
    output = "HDMI-A-1",
    disabled = false,
    mode = "2560x1440@120.00Hz",
    position = "0x0",
    scale = 1,
    cm = "srgb",
})

-- The virtual display, for streaming with the real panels switched off.
--
-- There is no monitor on this port. DP-1 is force-enabled by the kernel with
-- a canned EDID (video=DP-1:e drm.edid_firmware=..., set in
-- /etc/default/limine), so the GPU has an output from boot whether or not
-- anything physical is powered on. That is the whole point: Hyprland cannot
-- come up with zero enabled outputs, and a monitor that is merely switched
-- off drops off the bus like an unplugged one.
--
-- So it stays enabled, always. Disabling it here and turning it on only to
-- stream would put back exactly the hole it exists to fill.
--
-- The EDID's preferred mode is 3840x2160@60, which is a lot of pixels to
-- render for a screen nobody is looking at. Pinned to 1600x900 instead: the
-- client on the other end is a phone, and 1080p arrives there scaled down to
-- something too small to read. The same EDID carries 1280x720 if that is still
-- too much, and 1920x1080 and 2560x1440 at 120 going the other way.
hl.monitor({
    output = "DP-1",
    disabled = false,
    -- Exactly as the EDID spells it: a mode string that matches nothing is
    -- silently dropped and the output falls back to the preferred 4K60. That
    -- is why 1080p had to be asked for as 119.88 and not 120.00. Below 1080p
    -- this EDID only carries 60Hz, which costs nothing here -- Sunshine asks
    -- for 60fps anyway.
    mode = "1600x900@60.00Hz",
    -- Right of HDMI-A-1, which is where Hyprland's catch-all rule was putting
    -- it anyway. Written down so it stops depending on enumeration order.
    position = "2560x0",
    scale = 1,
})

-- Which workspace lands on which of the two. Left to itself Hyprland gives
-- workspace 1 to the output it enumerates first -- HDMI-A-1, at 0x0 -- and
-- pushes 2 onto DP-2; that is backwards. Work belongs on the 240Hz DP-2, so
-- 1 is pinned there and 2, where Discord and Steam open, sits on the HDMI
-- panel. `default` is what makes each monitor come up on its own workspace
-- at start rather than only honouring the pin once the workspace is used.
hl.workspace_rule({ workspace = "1", monitor = "DP-2",     default = true })
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1", default = true })

-- 3 is the remote desktop, and only that. Hyprland was already landing it on
-- DP-1 by enumeration order; pinning it means the windows left on it stay
-- together when DP-1 comes and goes with a stream, instead of being scattered
-- onto whichever panel is up at the time.
hl.workspace_rule({ workspace = "3", monitor = "DP-1", default = true })

-- ── Shell fit-up ─────────────────────────────────────────────────────────
--
-- Last, so it wins over the block above. The bar already reserves 51px at
-- the top, and a full outer gap on top of that left a wide empty band under
-- it; the other edges keep the value from above.
hl.config({
    general = {
        gaps_out = { top = 20, bottom = 30, left = 30, right = 30 },
    },
    decoration = {
        -- Same tone the shell's widgets use (Theme.glass is the background
        -- at 0.8), so the focused window and the panels read as the same
        -- material. Inactive windows stay opaque, as before.
        active_opacity = 0.8,
    },
})

-- ── Zen: the page is not a decoration ────────────────────────────────────
--
-- The global opacity above dims every window, and a compositor has no way to
-- dim only the browser's chrome: the tab strip and the page it frames are one
-- surface, so 0.8 opacity puts the wallpaper through the article as well.
--
-- Focused, the window is therefore forced fully opaque and the translucency
-- is put back inside Zen, where chrome and content *are* separable
-- (zen.widget.linux.transparency, in the profile's user.js). Unfocused, Zen
-- goes back to behaving like any other window and dims whole.
--
-- The value has to be the rule string, not a number. `opacity = 1.0` parses
-- fine and does nothing: without `override` a number is a *factor* on the
-- global opacity, so 1.0 x 0.8 is still 0.8. Which is exactly why the second
-- value here is left un-overridden -- 1.0 x inactive_opacity is whatever
-- that global says, today and after it changes, rather than a copy of 0.7
-- that would quietly stop matching. And the per-field spellings
-- (opacity_override, opacity_inactive) are not keys this schema knows: they
-- land in `hyprctl configerrors` instead of stopping the reload.
hl.window_rule({
    name = "zen-opaque",
    match = { class = "^zen$" },
    -- active, then inactive. Single spaces: the parser rejects anything else.
    opacity = "1.0 override 1.0",
})
