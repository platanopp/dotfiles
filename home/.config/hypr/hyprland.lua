-- Any monitor without a rule of its own. Kept as a table: putting the
-- monitors in order for X (below) uses it again to bring one back on.
local anyMonitor = {
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
}
hl.monitor(anyMonitor)

local terminal = "kitty"
-- Thunar, themed after the shell (~/.config/gtk-3.0/gtk.css). Yazi is still
-- there for the terminal; its kitty profile (kitty/yazi.conf) keeps kitty's
-- shortcuts off the Dolphin keys it is set up with, should it be run that way.
local kittyDir = os.getenv("HOME") .. "/.config/kitty/"
local fileManager = "thunar"
local mainMod = "SUPER"

hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("GTK_THEME", "Adwaita-dark")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- ── The monitors as X programs see them ──────────────────────────────
--
-- X programs do not see the monitors as they are here. XWayland lays them
-- out side by side at y=0, in the order Hyprland added them
-- (`DISPLAY=:0 xrandr --listmonitors`). That is Hyprland's doing and has no
-- setting; it translates each window's position monitor by monitor, so a
-- window inside one monitor lands where it should. A monitor set higher or
-- lower than its neighbour (here the Samsung, 360 px lower) is lost to X;
-- that much is harmless.
--
-- The order is not. It is the order the monitors were found in, and one that
-- drops its link and comes back -- here the Xiaomi, powered off over DDC for
-- idle -- is found again last. So X's left and right had nothing to do with
-- the desk, and changed under running programs: the Xiaomi at +0+0 at login,
-- where on the desk it is on the right, then swapped with the Samsung at
-- every idle, 27 times in one day. Anything that read the layout before a
-- swap and placed a window after it (Steam, read once at login; a game
-- started before the panels went off) placed it by a map no longer true.
--
-- So the order is put right: left to right as the monitors stand, and of
-- two at the same left edge, the higher first. When it is wrong -- at login,
-- or when a monitor comes back -- the monitors out of place are turned off
-- and back on one at a time, which lines them up at the end. A second or two
-- of black on those, at login behind the lock. Nothing here names a monitor,
-- so it holds for any set of them.
--
-- And which monitor counts as the main one is not translated either: with
-- no primary set, whatever asks for it -- Wine, for Proton games; Steam and
-- other X programs sizing a new window -- got the first one listed. The
-- primary is the fastest monitor, the one games are played on (here the
-- Samsung, 240 Hz to the Xiaomi's 120); of two as fast, the one further
-- left. Set at login, retried until XWayland knows the output, and again
-- when a monitor is added: a monitor coming back is a new output to
-- XWayland, and a primary goes with the output it was set on.

-- The monitors in the order the desk has them. Mirrors are not outputs of
-- their own to X.
local function deskOrder()
    local mons = {}
    for _, m in ipairs(hl.get_monitors()) do
        if not m.is_mirror then table.insert(mons, m) end
    end
    table.sort(mons, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        return a.name < b.name
    end)
    return mons
end

local function setXPrimary()
    local primary
    for _, m in ipairs(deskOrder()) do
        if not primary or m.refresh_rate > primary.refresh_rate + 0.5 then
            primary = m
        end
    end
    -- It goes into a shell command: a plain output name or nothing.
    if not primary or not primary.name:match("^[%w%-_.]+$") then return end
    hl.exec_cmd("sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do "
        .. "xrandr --output " .. primary.name .. " --primary 2>/dev/null && exit; sleep 0.5; done'")
end

-- The monitor rules, with the layout picked in Settings; set where they are
-- written, near the end of the file. Run again to bring a monitor back on.
local applyMonitorRules

-- The monitors to turn off and on so that Hyprland's list -- the order they
-- were added in, which is the order XWayland lays them out in -- is in desk
-- order. Kept: the longest run from the left already in order. Everything
-- after it goes, to come back in turn at the end of the list.
local function xOutOfPlace()
    local listed = {}
    for i, m in ipairs(hl.get_monitors()) do listed[m.name] = i end
    local want = deskOrder()
    local last = 0
    for i, m in ipairs(want) do
        if listed[m.name] < last then
            local out = {}
            for j = i, #want do table.insert(out, want[j].name) end
            return out
        end
        last = listed[m.name]
    end
    return {}
end

local xOrdering = false
local afterXOrder = {}

local function runAfterXOrder()
    local waiting = afterXOrder
    afterXOrder = {}
    for _, fn in ipairs(waiting) do fn() end
end

-- Puts the monitors in desk order, then runs `after`. A monitor coming back
-- on is itself a monitor being added, which lands here again while
-- `xOrdering` is set and leaves it alone; so does login, when a monitor
-- being added may have started the reordering already, and Steam waits for
-- it to end.
local function orderXMonitors(after)
    if after then table.insert(afterXOrder, after) end
    if xOrdering then return end
    local out = xOutOfPlace()
    if #out == 0 then
        runAfterXOrder()
        return
    end
    xOrdering = true
    for _, name in ipairs(out) do
        hl.monitor({ output = name, disabled = true })
    end
    -- Back on one at a time, so each is added in its turn. A monitor gets
    -- the last rule that matches it, and only a rule of the same name undoes
    -- the one that turned it off: the catch-all's settings go in under its
    -- name, and the file's own rules back on top of that -- then the
    -- monitors still waiting are turned off again.
    local function bringBack(i)
        local rule = {}
        for k, v in pairs(anyMonitor) do rule[k] = v end
        rule.output = out[i]
        hl.monitor(rule)
        applyMonitorRules()
        for j = i + 1, #out do
            hl.monitor({ output = out[j], disabled = true })
        end
        if i < #out then
            hl.timer(function() bringBack(i + 1) end, { timeout = 500, type = "oneshot" })
            return
        end
        -- Time for XWayland to hear of the outputs again before anything
        -- reads the layout.
        hl.timer(function()
            xOrdering = false
            setXPrimary()
            runAfterXOrder()
        end, { timeout = 1500, type = "oneshot" })
    end
    hl.timer(function() bringBack(1) end, { timeout = 500, type = "oneshot" })
end

hl.on("monitor.added", function()
    setXPrimary()
    orderXMonitors()
end)

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
    --
    -- On Qt's basic render loop (its own pick here), which draws every window
    -- in one pass: the pills are separate surfaces that move together, and
    -- the threaded loop (QSG_RENDER_LOOP=threaded, animations at the
    -- monitor's refresh instead of 60 fps) presents each window on its own
    -- thread -- neighbours landed a frame apart and the gaps between the
    -- pills shook by up to 12px mid-animation.
    hl.exec_cmd("quickshell")
    -- Before Steam, which reads the monitors when it starts: the primary,
    -- and the monitors in desk order (see "The monitors as X programs see
    -- them").
    setXPrimary()
    -- Chat and the game client.
    hl.exec_cmd("discord")
    orderXMonitors(function() hl.exec_cmd("steam") end)
    hl.exec_cmd("hyprpaper")
    -- The desktop widgets are the shell's own now (Super + D), on a layer
    -- under the windows; the four kitty windows that stood in for them --
    -- fastfetch, tty-clock, cava, btop on workspace 11 -- are gone.
    -- Panels off after fifteen idle minutes and a lock at twenty; rules in
    -- hypridle.conf next door. Its output goes to a log rather than nowhere:
    -- when the timeout does not fire, what it says about inhibits is the only
    -- account of why, and it used to be thrown away.
    hl.exec_cmd("hypridle > $HOME/.local/state/hypridle.log 2>&1")
    -- No OpenRGB server here: scripts/keyboard_rgb.py starts one when a USB
    -- device comes in and keeps it only while it has a keyboard to light.
    -- Started for the whole session it cost a steady 0.25% CPU lighting
    -- nothing, the Wooting being driven through its own SDK.
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
-- The shell's spring (Theme.springOvershoot in quickshell): the same
-- stiffness as "easy", damped to a ratio of 0.68 instead of 0.78, so it runs
-- about 5% past and settles -- what the bar's panels and overlays do, so a
-- window opening and a panel opening move alike. Arrivals only; leaving and
-- fading stay on the plain curves.
hl.curve("soft",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 21 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "soft" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "soft",         style = "popin 80%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
-- Workspaces slide a fifth of the way while they fade, on the spring: a
-- full-width slide would show the overshoot as a strip of the next desktop.
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 4.1,  spring = "soft",         style = "slidefade 20%" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 4.1,  spring = "soft",         style = "slidefade 20%" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 4.1,  spring = "soft",         style = "slidefade 20%" })
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
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(terminal .. " --directory $HOME claude --continue"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
-- Handled inside the shell, which registers the name over Hyprland's
-- global-shortcuts protocol -- see the GlobalShortcut in shell.qml.
-- Locking is in there too, because the lock surface is one quickshell draws
-- itself: LockEngine and LockScreen. Nothing outside the shell to run.
hl.bind(mainMod .. " + L", hl.dsp.global("quickshell:lock"))
hl.bind(mainMod .. " + space", hl.dsp.global("quickshell:launcher"))
hl.bind(mainMod .. " + Tab", hl.dsp.global("quickshell:overview"))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.global("quickshell:record"))

-- ── While the shell's launcher, overview, wallpapers or shortcuts are up ─
--
-- Quickshell switches to this submap as one opens and back as it closes
-- (Panels.modalOpen). In it only the keys that close them do anything: the rest -- above all Super+drag, which moved and resized the
-- windows behind the overview -- waits until they are gone. Keys the
-- overlays handle themselves (Esc, arrows, typing) reach them as usual.
--
-- Each of them drops back to the normal binds itself before asking the
-- shell, so the way out never depends on Quickshell answering: a shell
-- that died with the overview up cannot leave the keyboard stuck here.
hl.define_submap("shell-modal", function()
    hl.bind(mainMod .. " + Tab", function()
        hl.dispatch(hl.dsp.submap("reset"))
        hl.dispatch(hl.dsp.global("quickshell:overview"))
    end)
    hl.bind(mainMod .. " + space", function()
        hl.dispatch(hl.dsp.submap("reset"))
        hl.dispatch(hl.dsp.global("quickshell:launcher"))
    end)
    hl.bind(mainMod .. " + W", function()
        hl.dispatch(hl.dsp.submap("reset"))
        hl.dispatch(hl.dsp.global("quickshell:wallpapers"))
    end)
    hl.bind(mainMod .. " + F", function()
        hl.dispatch(hl.dsp.submap("reset"))
        hl.dispatch(hl.dsp.global("quickshell:keybinds"))
    end)
    hl.bind(mainMod .. " + D", function()
        hl.dispatch(hl.dsp.submap("reset"))
        hl.dispatch(hl.dsp.global("quickshell:widgets"))
    end)
end)
hl.bind(mainMod .. " + F", hl.dsp.global("quickshell:keybinds"))
hl.bind(mainMod .. " + W", hl.dsp.global("quickshell:wallpapers"))
hl.bind(mainMod .. " + D", hl.dsp.global("quickshell:widgets"), { description = "Desktop widgets" })
hl.bind(mainMod .. " + O", hl.dsp.global("quickshell:settings"))
hl.bind(mainMod .. " + ALT + Z", hl.dsp.global("quickshell:micmute"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- ── Workspaces: ten per monitor ──────────────────────────────────────────
--
-- Each monitor has its own block of ten: DP-2 has 1-10, HDMI-A-1 11-20 (the
-- rules that pin them are at the end of the file). Super+N and
-- Super+Shift+N work on the Nth of the focused monitor's block, so each
-- monitor has a 1 to 10 of its own, and the shell's pill and overview number
-- them the same way: 13 reads as HDMI's 3.
--
-- The block comes from the workspace the monitor is showing, not from its
-- name, so the shell can work it out the same way, and a monitor with no
-- rule still gets a block of whatever it landed on.
local workspaceBlocks = { ["DP-2"] = 0, ["HDMI-A-1"] = 10 }

local function focusedBlock()
    local m = hl.get_active_monitor()
    if not m then return 0 end
    local ws = m.active_workspace
    if ws and ws.id > 0 then return math.floor((ws.id - 1) / 10) * 10 end
    return workspaceBlocks[m.name] or 0
end

-- The description is what `hyprctl binds` and the shell's shortcuts sheet
-- show: a Lua function, unlike a dispatcher, says nothing about itself.
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, function()
        hl.dispatch(hl.dsp.focus({ workspace = focusedBlock() + i }))
    end, { description = "Go to workspace " .. i .. " of this monitor" })
    hl.bind(mainMod .. " + SHIFT + " .. key, function()
        hl.dispatch(hl.dsp.window.move({ workspace = focusedBlock() + i }))
    end, { description = "Move to workspace " .. i .. " of this monitor" })
end

hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- `m`, not `e`: the open workspaces of this monitor, not of every monitor.
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "m-1" }))

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

-- The name is dated by the shell when the key is pressed. It used to be
-- built with os.date() here, which runs once, when this file is loaded: every
-- screenshot between two reloads got the same name and overwrote the last.
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(
    'grimblast --notify copysave area "$HOME/Pictures/Screenshots/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"'
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

hl.layer_rule({
    name  = "quickshell-xray",
    -- ".*": rules match the whole namespace, and "quickshell" alone matched
    -- none of the shell's ("quickshell:bar-blur", ...). Harmless while
    -- decoration.blur.xray is on globally, but this is what it meant.
    match = { namespace = "^quickshell.*" },
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

-- ── Desktop widgets ───────────────────────────────────────────────────
--
-- Drawn by the shell on its own layers: "quickshell:desktop" under the
-- windows (one per monitor, unmapped when empty or under a fullscreen
-- window) and "quickshell:widgets", the picker, over everything. The
-- widgets are the bar panels' glass, blurred like the bar: same threshold,
-- so the card is blurred and the transparent space around it is not, and
-- the catch-all xray rule keeps it to the wallpaper, which is cached. The
-- picker dims with its own scrim, like the other overlays. Both animate
-- themselves.
hl.layer_rule({
    name         = "quickshell-desktop",
    match        = { namespace = "^quickshell:desktop$" },
    blur         = true,
    ignore_alpha = 0.3,
    no_anim      = true,
})

hl.layer_rule({
    name         = "quickshell-widgets",
    match        = { namespace = "^quickshell:widgets$" },
    blur         = false,
    ignore_alpha = 0.02,
    xray         = false,
    no_anim      = true,
})

-- ── Steam's notification toasts ─────────────────────────────────────
--
-- "A friend is now playing..." is a small X window, kept floating, pinned to
-- whatever workspace you are on and never taking focus from the game or the
-- window you are typing in.
--
-- The `.*` matters: Hyprland matches a rule's regex against the whole title,
-- not a prefix of it, so "^notificationtoasts" alone matched no toast
-- ("notificationtoasts_6_desktop") and they went on as tiles on workspace 2.
hl.window_rule({
    name     = "steam-toasts",
    match    = { class = "^steam$", title = "^notificationtoasts.*" },
    float    = true,
    pin      = true,
    no_focus = true,
})

-- Where it goes is not up to a rule. Steam moves the toast itself right
-- after it maps -- it slides it up into what it takes for the bottom-right
-- corner, over about a third of a second -- and a floating X window gets the
-- moves it asks for, so a rule's `move` held for 60ms. Steam works that
-- corner out in X coordinates, where both monitors sit at y=0; here the
-- Samsung was 240px lower and the Xiaomi 242px higher, so the slide ended in
-- the middle of the right edge. Mapped with a rule's `move`, the Xiaomi's
-- corner came out off-screen as well (monitor_h, without its offset).
--
-- Since 2026-10-18 the Xiaomi is at 0,0 and the Samsung at -1920,360 (bottoms
-- level, as before), so X and Hyprland agree on the Xiaomi at least. Not only
-- for this: a monitor with a y offset lost it when it came back from being
-- switched off -- Hyprland put its floating windows back as if it were at
-- y=0, 120px low every night (see ~/.config/hypr/scripts/float-keep.py).
-- Keep the Xiaomi, the one that drops its link, at 0,0.
--
-- So: into the bottom-right corner of the monitor in use, 13px in like the
-- windows, and back there every 10ms for as long as the toast is up -- a
-- check that moves nothing once Steam has stopped. One timer per toast, and
-- it ends with the toast.
local function pinToastToCorner(win)
    local mon = hl.get_active_monitor()
    if not mon then return end
    local sel = "address:" .. win.address
    local function place()
        local w = hl.get_window(sel)
        if not w or not w.mapped then return false end
        local x = mon.x + mon.width - w.size.x - 13
        local y = mon.y + mon.height - w.size.y - 13
        if w.at.x ~= x or w.at.y ~= y then
            hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = sel }))
        end
        return true
    end
    if not place() then return end
    local elapsed = 0
    local timer
    timer = hl.timer(function()
        elapsed = elapsed + 10
        -- Steam's toasts last about six seconds; the cap is only for one
        -- that stays up, so it is not watched forever.
        if not place() or elapsed > 15000 then timer:set_enabled(false) end
    end, { timeout = 10, type = "repeat" })
end

-- ── Floating windows bigger than their monitor ──────────────────────
--
-- A floating window that still opens too big for its monitor, or outside
-- it, is brought in: shrunk to the monitor's free area (the bar's space
-- off, 13px in like the windows) and centred there. The case it was written
-- for: an X dialog asking for 2400x1300 opened at 0,0 -- the Xiaomi's
-- corner -- while it belonged to a Samsung workspace, and ran off both.
--
-- Checked when the window maps and once more a moment later, for the X
-- programs (Steam among them) that resize themselves just after. Windows
-- that already fit are not touched. Left out: Proton games (steam_app_*),
-- which render at the size they chose whatever their window is resized to
-- -- the primary monitor above is what gives them the right one; Steam's
-- toasts, placed above; and the nameless surfaces of X drags.
local function fitToMonitor(sel)
    local w = hl.get_window(sel)
    if not w or not w.mapped or not w.floating or w.fullscreen ~= 0 or w.pinned then return end
    local mon = w.monitor
    if not mon then return end
    local r = mon.reserved
    local left, top = mon.x + r.left, mon.y + r.top
    local right, bottom = mon.x + mon.width - r.right, mon.y + mon.height - r.bottom
    if w.at.x >= left and w.at.y >= top
        and w.at.x + w.size.x <= right and w.at.y + w.size.y <= bottom then
        return
    end
    local width = math.min(w.size.x, right - left - 26)
    local height = math.min(w.size.y, bottom - top - 26)
    if width ~= w.size.x or height ~= w.size.y then
        hl.dispatch(hl.dsp.window.resize({ x = width, y = height, window = sel }))
    end
    hl.dispatch(hl.dsp.window.move({
        x = left + math.floor((right - left - width) / 2),
        y = top + math.floor((bottom - top - height) / 2),
        window = sel,
    }))
end

hl.on("window.open", function(win)
    if win.class == "steam" and win.title:find("^notificationtoasts") then
        pinToastToCorner(win)
        return
    end
    if not win.floating or win.class == "" or win.class:find("^steam_app") then return end
    local sel = "address:" .. win.address
    fitToMonitor(sel)
    hl.timer(function() fitToMonitor(sel) end, { timeout = 300, type = "oneshot" })
end)

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

-- The full-screen overlays draw an opaque card over a scrim (Theme.surface,
-- Theme.scrim), so they ask for no blur: the compositor's blur is kept for
-- the bar's glass, and a blurred full-screen layer was the costliest frame
-- the shell could ask for.
hl.layer_rule({
    name  = "quickshell-keybinds-blur",
    match = { namespace = "^quickshell:keybinds$" },
    blur  = false,
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
    -- The sheet fades and drops in by itself, like the launcher; Hyprland's
    -- layer fade on top only made it arrive later.
    no_anim = true,
})

hl.layer_rule({
    name  = "quickshell-wallpapers-blur",
    match = { namespace = "^quickshell:wallpapers$" },
    blur  = false,
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

-- The launcher fades itself in (100ms). Hyprland's own layer fade on top of
-- that stretched its arrival to about 230ms from the keypress -- the slowest
-- part of Super+Space.
-- The workspace overview dims the desktop and has it blurred behind: the
-- real windows (xray off, as for the cheatsheet), under a threshold low
-- enough for the dim. It fades itself, so no layer animation on top.
hl.layer_rule({
    name         = "quickshell-overview",
    match        = { namespace = "^quickshell:overview$" },
    blur  = false,
    ignore_alpha = 0.02,
    xray         = false,
    no_anim      = true,
})

hl.layer_rule({
    name    = "quickshell-launcher",
    match   = { namespace = "^quickshell:launcher$" },
    no_anim = true,
})

hl.layer_rule({
    name  = "quickshell-launcher-blur",
    match = { namespace = "^quickshell:launcher$" },
    blur  = false,
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

        -- A window that asks to be activated gets focus, and its workspace
        -- with it. Opening a link from Discord or the terminal hands the URL
        -- to the browser already running, which asks exactly that; with this
        -- off Hyprland only marked it urgent (the pulse on the workspaces
        -- pill) and you stayed where you were.
        focus_on_activate = true,

        -- Variable refresh (FreeSync / G-Sync compatible), for fullscreen
        -- windows only -- games. Off, a game running below the monitor's
        -- refresh (240 Hz on the Samsung) showed every dip as judder; with
        -- it the monitor follows the frame rate, as it did under Windows.
        -- Not on the desktop, where some panels flicker at low refresh.
        vrr = 2,
    },

    render = {
        -- A fullscreen game's frames go straight to the screen instead of
        -- being composited first: less GPU work and less latency. 1 (any
        -- fullscreen window) rather than 2 (content type "game"): games under
        -- Proton report no content type, and 2 never applied to them.
        --
        -- It only engages with nothing to draw over the game, and the
        -- shell's pill surfaces stay mapped (transparent) over fullscreen --
        -- hyprctl monitors says "blockedBy: CANDIDATE" while they do. Set so
        -- it applies the moment that is no longer so.
        direct_scanout = 1,
    },
})

-- After the catch-all monitor rule at the top of the file, so these win for
-- the two outputs actually attached. A function, because putting the
-- monitors in order for X (near the top) turns monitors off and needs them
-- back on as they were.
applyMonitorRules = function()
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
        mode = "2560x1440@120.00Hz",
        position = "0x0",
        scale = 1,
        cm = "srgb",
    })

    -- The layout picked in the shell's Settings (Displays page) -- mode,
    -- position and scale per monitor -- written to monitors.lua by
    -- display_control.py. Run after the rules above, so it wins: at login,
    -- and at every config reload, which used to put the monitors back where
    -- this file had them. The two rules above stay as the defaults for a
    -- machine with nothing saved yet.
    local path = os.getenv("HOME") .. "/.config/hypr/monitors.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        dofile(path)
    end
end

applyMonitorRules()

-- Each monitor's block of ten (see `workspaceBlocks` by the binds), pinned
-- so a workspace opens on its own monitor whichever one asked for it.
-- `default` has each monitor come up on the first of its block: left alone,
-- Hyprland hands the 1 to whichever monitor it enumerates first (HDMI-A-1),
-- and the work screen, DP-2, got the 2.
for name, base in pairs(workspaceBlocks) do
    for i = 1, 10 do
        hl.workspace_rule({ workspace = tostring(base + i), monitor = name, default = i == 1 })
    end
end

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
