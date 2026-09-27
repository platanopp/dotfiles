hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

local terminal = "kitty"
local fileManager = "kitty --class yazi -e yazi"
local browser = "zen-browser"
local mainMod = "SUPER"

hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("GTK_THEME", "Adwaita-dark")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.on("hyprland.start", function()
    -- Un solo arranque para toda la sesion grafica.
    --
    -- Antes esto decia `start graphical-session.target`, y fallaba en silencio
    -- en cada login: ese target tiene RefuseManualStart=yes. sunshine y
    -- gamepad-mode quedaban enabled y nunca active. hyprland-session.target
    -- existe solo para arrastrarlo como dependencia, que si esta permitido --
    -- ver el comentario en ese archivo.
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    hl.timer(function()
     hl.exec_cmd("nvibrant 300 0 0 600")
      end, { timeout = 2000, type = "oneshot" })
    -- First of the lot, and for one reason: on a cold boot the shell puts the
    -- lock up on the first frame it can, and nothing has asked for a password
    -- before that -- greetd hands the seat over already logged in. Everything
    -- below takes a second or two to draw, and every one of those seconds
    -- would be desktop on screen with no lock over it. Behind the lock they
    -- can take as long as they like.
    hl.exec_cmd("quickshell")
    hl.exec_cmd("kitty")
    -- Chat and the game client, parked on workspace 2 by the rules further
    -- down so they come up behind the terminal instead of over it.
    hl.exec_cmd("discord")
    hl.exec_cmd("steam")
    hl.exec_cmd("hyprpaper")
    -- Panels off after fifteen idle minutes and a lock at twenty; rules in
    -- hypridle.conf next door. Its output goes to a log rather than nowhere:
    -- when the timeout does not fire, what it says about inhibits is the only
    -- account of why, and it used to be thrown away.
    hl.exec_cmd("hypridle > $HOME/.local/state/hypridle.log 2>&1")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    -- Tailscale's tray icon: tailnet state and a connect/disconnect toggle
    -- without a terminal.
    --
    -- Delayed because it needs somewhere to appear. The tray host is
    -- quickshell, started a few lines up, and a StatusNotifierItem that
    -- registers before the watcher exists has nothing to attach to. Whether
    -- this one retries or gives up was not established -- finding out means
    -- killing the shell out from under a live session -- so it waits instead.
    -- If the icon is ever missing at login, that delay is the first thing to
    -- raise.
    --
    -- dark:nobg, not the default dark: the default paints the glyph on an
    -- opaque black square, which sits as a hard-edged box among the
    -- transparent icons already in the tray. Compared side by side before
    -- choosing.
    hl.timer(function()
        hl.exec_cmd("tailscale systray --theme=dark:nobg")
        -- Wooting's background service (the AppImage, installed to
        -- ~/.local/bin): app linking -- switching keyboard profiles by the
        -- focused app -- and Wootility's helpers. Same wait as above, for the
        -- same tray. Its log is kept: it says which keyboard it found.
        hl.exec_cmd("wooting-bg-service > $HOME/.local/state/wooting-bg-service.log 2>&1")
    end, { timeout = 4000, type = "oneshot" })
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
        -- Repeticion de tecla: tras repeat_delay ms aguantando, repite
        -- repeat_rate veces por segundo. Los defaults de Hyprland (600/25)
        -- se sienten lentos al borrar. Afecta a todas las aplicaciones,
        -- no solo al terminal: lo fija el compositor y lo reparte por
        -- wl_keyboard.repeat_info.
        repeat_delay = 400,
        repeat_rate  = 40,
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

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
-- Handled inside the shell, which registers the name over Hyprland's
-- global-shortcuts protocol -- see the GlobalShortcut in shell.qml.
-- Locking is in there too, because the lock surface is one quickshell draws
-- itself: LockEngine and LockScreen. Nothing outside the shell to run.
hl.bind(mainMod .. " + L", hl.dsp.global("quickshell:lock"))
hl.bind(mainMod .. " + space", hl.dsp.global("quickshell:launcher"))
hl.bind(mainMod .. " + F", hl.dsp.global("quickshell:keybinds"))
hl.bind(mainMod .. " + W", hl.dsp.global("quickshell:wallpapers"))
hl.bind(mainMod .. " + O", hl.dsp.global("quickshell:settings"))
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
-- ── World of Warcraft fullscreen ──────────────────────────────────
--
-- The gxWindow "0" CVar in Config.wtf is not enough: under XWayland the
-- client asks, Hyprland tiles it anyway, and the window lands inset by the
-- gaps and the bar. Forcing it here wins regardless of what the game asks.
--
-- Matched on title as well as class, because everything umu launches shares
-- the class "steam_app_default" -- on class alone this would also catch
-- every other Battle.net and Lutris game.
hl.window_rule({
    name       = "wow-fullscreen",
    match      = { class = "^steam_app_default$", title = "^World of Warcraft$" },
    fullscreen = true,
})

hl.window_rule({
    name      = "discord-on-2",
    match     = { class = "^discord$" },
    workspace = "2 silent",
})
hl.window_rule({
    name      = "steam-on-2",
    -- Anything launched from Steam gets its own class (steam_app_...), so
    -- this catches the client and its dialogs and no actual game. Not its
    -- notification toasts: those belong where you are looking (below).
    match     = { class = "^steam$", title = "negative:^notificationtoasts" },
    workspace = "2 silent",
})

-- ── Steam's notification toasts ─────────────────────────────────────
--
-- "A friend is now playing..." is a small X window Steam places itself, in
-- X coordinates that do not match this layout (the Samsung sits left of and
-- lower than the Xiaomi), so it landed well above the corner. Pinned here to
-- the bottom-right of the monitor in use, on the same 13px gap as windows,
-- and never taking focus from the game or the window you are typing in.
hl.window_rule({
    name     = "steam-toasts",
    match    = { class = "^steam$", title = "^notificationtoasts" },
    float    = true,
    pin      = true,
    no_focus = true,
    move     = "monitor_w-window_w-13 monitor_h-window_h-13",
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
    -- No compositor animation for these surfaces. The "layers" animation
    -- above slides a layer from its old geometry to its new one whenever it
    -- moves or resizes -- and the shell moves and resizes the pills itself,
    -- frame by frame, with its own animations. The two fought: every pill
    -- that followed a neighbour was also being eased by Hyprland a beat
    -- behind, and when a pill's window shrank at the end of a close,
    -- Hyprland slid it across from where the larger window had been, so it
    -- jumped over its neighbour and crept back. These are never mapped or
    -- unmapped in use (hidden by input mask), so nothing else is lost.
    no_anim = true,
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

        -- If the lock client dies while it is holding the screen, Hyprland
        -- keeps the session locked and there is no client left to type into:
        -- the only way back is killing the compositor from a TTY, which takes
        -- the whole session with it. With this on, a freshly started locker is
        -- allowed to adopt the orphaned lock instead, so `quickshell` coming
        -- back up puts a field back on the screen.
        allow_session_lock_restore = true,

        -- What fills the gap at boot between Hyprland taking the display and
        -- quickshell drawing the lock over it -- the moment of "monitor sin
        -- nada". The default is black; this is the shell's own background, so
        -- the handover reads as one screen rather than two.
        background_color = "rgb(101014)",
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

-- Que workspace cae en cada monitor. Por su cuenta Hyprland le da el 1 al
-- monitor que enumera primero -- HDMI-A-1, en 0x0 -- y empuja el 2 al DP-2,
-- que es al reves de lo util: el trabajo va en el DP-2 de 240Hz, y el 2,
-- donde abren Discord y Steam, en el panel HDMI. `default` hace que cada
-- monitor arranque ya en su workspace, en vez de respetar el anclaje solo
-- cuando ese workspace se usa por primera vez.
hl.workspace_rule({ workspace = "1", monitor = "DP-2",     default = true })
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1", default = true })

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
-- ── NIKKE: a game is not a decoration either ─────────────────────────────
--
-- Same reasoning as Zen below, with one difference: both states are
-- overridden here. Zen deliberately leaves the inactive value as a factor so
-- it tracks the global, but a game showing the wallpaper through it while
-- unfocused is just as wrong as while focused -- and it is watched unfocused
-- often, in the background of something else.
--
-- Matched on the Steam appid class, which is specific to this game. The
-- generic "steam_app_default" that umu hands out would catch every other
-- Lutris and Battle.net title too.
hl.window_rule({
    name = "nikke-opaque",
    match = { class = "^steam_app_3741011882$" },
    -- active, then inactive. Single spaces: the parser rejects anything else.
    opacity = "1.0 override 1.0 override",
})

hl.window_rule({
    name = "zen-opaque",
    match = { class = "^zen$" },
    -- active, then inactive. Single spaces: the parser rejects anything else.
    opacity = "1.0 override 1.0",
})

-- ── Settings made in the shell ───────────────────────────────────────────
--
-- The Settings window's Hyprland page writes its choices to gui-settings.lua
-- (see ~/.config/quickshell/scripts/hypr_settings.py) and never touches this
-- file. Run last, so what was picked there wins over the blocks above; with
-- no such file -- a fresh machine, or every choice reset -- nothing happens.
do
    local path = os.getenv("HOME") .. "/.config/hypr/gui-settings.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        dofile(path)
    end
end
