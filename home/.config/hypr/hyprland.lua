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
-- Thunar, themed after the shell (~/.config/gtk-3.0/gtk.css). Yazi stays for the terminal; its
-- kitty profile (kitty/yazi.conf) keeps kitty's shortcuts off the Dolphin keys.
local kittyDir = os.getenv("HOME") .. "/.config/kitty/"
local fileManager = "thunar"
local mainMod = "SUPER"

hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("GTK_THEME", "Adwaita-dark")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- The monitors as X programs see them. XWayland lays them out at y=0 in the order Hyprland added
-- them, and a monitor that drops its link (the Xiaomi, off over DDC at idle) is re-added last, so
-- X's left and right swapped under running programs (27 times in one day) and Steam placed windows
-- by a stale map. So the order is put right, left to right as the monitors stand (the higher first
-- at the same left edge): the ones out of place are turned off and on one at a time, at login and
-- when a monitor comes back. X also gets a primary, which Wine and Steam use: the fastest monitor
-- (the 240 Hz Samsung), the leftmost on a tie. Set at login, retried until XWayland knows the
-- output, and again on every monitor added.

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

-- The monitors to turn off and on so Hyprland's list (XWayland's order) is in desk order: keep the
-- longest in-order run from the left, cycle the rest.
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

-- Puts the monitors in desk order, then runs `after`. Re-adding a monitor lands here again while
-- `xOrdering` is set and is left alone; Steam waits for the reordering to end.
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
    -- Back on one at a time, so each is added in its turn. Only a rule of the same
    -- name undoes the one that turned it off: the catch-all's settings go in under its
    -- name, the file's own rules on top.
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
    -- One start for the whole graphical session. `start graphical-session.target` failed silently
    -- at every login (RefuseManualStart=yes), leaving sunshine and gamepad-mode enabled but never
    -- active; hyprland-session.target exists to pull it in as a dependency, which is allowed.
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    hl.timer(function()
     hl.exec_cmd("nvibrant 300 0 0 600")
      end, { timeout = 2000, type = "oneshot" })
    -- First of the lot: on a cold boot the shell puts the lock up on its first frame (greetd hands
    -- the seat over logged in), and everything below would otherwise draw an unlocked desktop. The
    -- basic render loop is set by shell.qml's pragma: the threaded one presents each window on its
    -- own thread and the pills shook by up to 12px.
    hl.exec_cmd("quickshell")
    -- Before Steam, which reads the monitors when it starts (see "The
    -- monitors as X programs see them").
    setXPrimary()
    -- Chat and the game client.
    hl.exec_cmd("discord")
    orderXMonitors(function() hl.exec_cmd("steam") end)
    hl.exec_cmd("hyprpaper")
    -- Panels off after fifteen idle minutes and a lock at twenty (hypridle.conf). Logged: when a
    -- timeout does not fire, what it says about inhibits is the only account of why.
    hl.exec_cmd("hypridle > $HOME/.local/state/hypridle.log 2>&1")
    -- No OpenRGB server here: keyboard_rgb.py starts one when a USB device comes in
    -- and keeps it only while it has a keyboard to light (a session-long server
    -- cost 0.25% CPU lighting nothing).
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    -- Tailscale's tray icon. Delayed so quickshell's tray host exists first: an item registered
    -- before the watcher has nothing to attach to. If the icon is ever missing at login, raise the
    -- delay. dark:nobg: the default dark paints the glyph on an opaque black square.
    hl.timer(function()
        hl.exec_cmd("tailscale systray --theme=dark:nobg")
        -- Wooting's background service (~/.local/bin AppImage): app-linked profiles and Wootility's
        -- helpers. Same wait, for the same tray; the log says which keyboard it found.
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
-- The shell's spring (Theme.springOvershoot): "easy"'s stiffness damped to 0.68 instead
-- of 0.78, so it runs ~5% past and settles, like the bar's panels. Arrivals only; leaving
-- and fading stay on the plain curves.
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
        -- Key repeat: after repeat_delay ms held, repeat_rate per second. Hyprland's 600/25 felt
        -- slow when deleting. Set by the compositor for every app (wl_keyboard.repeat_info).
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
-- Handled inside the shell over Hyprland's global-shortcuts protocol (the GlobalShortcut in
-- shell.qml), locking included: the lock surface is the shell's own.
hl.bind(mainMod .. " + L", hl.dsp.global("quickshell:lock"))
hl.bind(mainMod .. " + space", hl.dsp.global("quickshell:launcher"))
-- Every keyboard to its next layout; does nothing with only one in kb_layout.
hl.bind(mainMod .. " + CTRL + space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))
hl.bind(mainMod .. " + Tab", hl.dsp.global("quickshell:overview"))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.global("quickshell:record"))

-- While the shell's launcher, overview, wallpapers or shortcuts are up, Quickshell switches
-- to this submap (Panels.modalOpen): only the keys that close them work, so Super+drag can't
-- move the windows behind. Each drops back to the normal binds before asking the shell, so a
-- dead shell can't leave the keyboard here. The screenshot key works too and keeps the
-- overlay up; its name is dated when pressed (os.date() here ran once per load, and every
-- shot between reloads overwrote the last).
local screenshot =
    'grimblast --notify copysave area "$HOME/Pictures/Screenshots/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"'

hl.define_submap("shell-modal", function()
    hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(screenshot))
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

-- Workspaces: ten per monitor. DP-2 has 1-10, HDMI-A-1 11-20 (pinned at the end of the
-- file); Super+N and Super+Shift+N use the Nth of the focused monitor's block, numbered the
-- same in the shell (13 reads as 3). The block comes from the workspace the monitor shows,
-- so a monitor with no rule still gets one.
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

hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(screenshot))

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
    -- ".*": rules match the whole namespace, so "quickshell" alone matched none of the shell's.
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

-- World of Warcraft fullscreen: gxWindow "0" is not enough under XWayland, where Hyprland tiles it
-- anyway. Matched on title too, since everything umu launches shares the class "steam_app_default".
hl.window_rule({
    name       = "wow-fullscreen",
    match      = { class = "^steam_app_default$", title = "^World of Warcraft$" },
    fullscreen = true,
})

-- Desktop widgets: "quickshell:desktop" under the windows (one per monitor) and
-- "quickshell:widgets", the picker, over everything. Blurred like the bar's glass (same threshold,
-- xray to the cached wallpaper); both animate themselves.
hl.layer_rule({
    name         = "quickshell-desktop",
    match        = { namespace = "^quickshell:desktop$" },
    blur         = true,
    ignore_alpha = 0.55,
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

-- Steam's notification toasts: small X windows, floating, pinned to the current workspace and never
-- taking focus. The `.*` matters: regexes match the whole title ("notificationtoasts_6_desktop").
hl.window_rule({
    name     = "steam-toasts",
    match    = { class = "^steam$", title = "^notificationtoasts.*" },
    float    = true,
    pin      = true,
    no_focus = true,
})

-- Placement is not up to a rule: Steam slides the toast into what it takes for the bottom-right
-- corner, in X coordinates where every monitor sits at y=0, and a floating X window gets the
-- moves it asks for. Keep the Xiaomi, the one that drops its link, at 0,0: a monitor with a y
-- offset came back from being off with its floating windows 120px low (see
-- scripts/float-keep.py). So the toast is put in the current monitor's bottom-right corner, 13px
-- in, and checked every 10ms while it is up (one timer per toast).
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

-- Floating windows bigger than their monitor, or outside it, are shrunk to its free area (13px in,
-- minus the bar) and centred; an X dialog once opened at 2400x1300 on the Xiaomi's corner. Checked
-- on map and once more after, for X programs that resize themselves. Left out: Proton games
-- (steam_app_*), Steam's toasts, X drags.
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
    -- Blur covers the whole rectangular surface, so pixels below this alpha stay unblurred, or the
    -- transparent margin around each rounded widget would blur as a square. Above the shadows'
    -- 0.5 and below the glass's 0.9: at 0.3 a blurred band showed under every pill.
    ignore_alpha = 0.55,
    -- No compositor animation: the shell animates the pills itself, and Hyprland
    -- easing them a beat behind made a shrinking pill jump over its neighbour. They
    -- are never mapped or unmapped in use.
    no_anim = true,
})

-- The full-screen overlays draw an opaque card over a scrim, so no blur: a blurred full-screen
-- layer was the costliest frame the shell could ask for.
hl.layer_rule({
    name  = "quickshell-keybinds-blur",
    match = { namespace = "^quickshell:keybinds$" },
    blur  = false,
    -- The cheatsheet's dim is what gets blurred through, so the threshold sits below it (at 0.3 the
    -- blur snapped in mid-fade). Closed, the surface draws nothing.
    ignore_alpha = 0.02,
    -- Overrides the catch-all xray rule: a sheet over the work should show the
    -- windows under it, not the wallpaper.
    xray = false,
    -- The sheet fades and drops in by itself, like the launcher; Hyprland's
    -- layer fade on top only made it arrive later.
    no_anim = true,
})

hl.layer_rule({
    name  = "quickshell-wallpapers-blur",
    match = { namespace = "^quickshell:wallpapers$" },
    blur  = false,
    -- Same as the cheatsheet: the picker's own dim is what gets blurred through.
    ignore_alpha = 0.02,
    -- And no xray: a wallpaper picker showing the old wallpaper through itself
    -- judges every candidate against it.
    xray = false,
})

-- The launcher fades itself in (100ms); Hyprland's layer fade on top stretched it to
-- ~230ms. The overview dims the desktop with the real windows blurred behind (xray off),
-- under a low threshold; it fades itself too.
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
    -- The bar's threshold: the launcher doesn't dim the screen, so only the panel may clear it (at
    -- 0.02 the whole screen blurred on open).
    ignore_alpha = 0.3,
    -- Overrides the catch-all xray rule: the panel takes its frosting from whatever it opened over.
    xray = false,
})

-- Was hyprland-gui.lua: HyprMod's generated settings now live here, one config to read and edit.
-- Don't point HyprMod's config-path at this file: it rewrites its managed file wholesale. Kept as a
-- layer in the order the settings resolved before: where a key appears twice, this one was winning.

-- Posy's Improved Cursor, the white set (59% white with a black outline, readable on light and
-- dark pages). From simtrami/posy-improved-cursor-linux (XCursor only), converted with
-- `hyprcursor-util --extract` then `--create`; the 133 aliases survive as define_override
-- entries. Installed under ~/.local/share/icons.
hl.env("HYPRCURSOR_THEME", "Posy_Cursor-hyprcursor")
hl.env("HYPRCURSOR_SIZE", "28")

-- The XCursor half, for XWayland and apps without hyprcursor; unset,
-- those showed a different pointer.
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

        -- If the lock client dies holding the screen, a restarted locker may adopt the orphaned
        -- lock, so `quickshell` coming back puts a field up again instead of needing a TTY.
        allow_session_lock_restore = true,

        -- What fills the gap at boot between Hyprland taking the display and quickshell's lock: the
        -- shell's own background, so the handover reads as one screen.
        background_color = "rgb(101014)",

        -- A window asking to be activated gets focus and its workspace: a link from Discord goes to
        -- the running browser, which Hyprland only marked urgent before.
        focus_on_activate = true,

        -- Variable refresh for fullscreen windows only (games): without it a game below 240 Hz
        -- judders. Not on the desktop, where some panels flicker at low refresh.
        vrr = 2,
    },

    render = {
        -- Direct scanout for any fullscreen window (1), not content type "game" (2), which Proton
        -- games never report. It only engages with nothing drawn over the game; while the shell's
        -- pill surfaces are mapped hyprctl monitors says "blockedBy: CANDIDATE".
        direct_scanout = 1,
    },
})

-- After the catch-all monitor rule at the top, so these win for the attached outputs. A function,
-- because putting the monitors in order for X turns them off and needs them back as they were.
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

    -- The layout picked in Settings -> Displays (monitors.lua, from display_control.py), run
    -- after the rules above so it wins at login and on every reload; those rules stay as
    -- defaults for a machine with nothing saved.
    local path = os.getenv("HOME") .. "/.config/hypr/monitors.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        dofile(path)
    end
end

applyMonitorRules()

-- Each monitor's block of ten (`workspaceBlocks`), pinned so a workspace opens on its own monitor.
-- `default` puts each monitor on its block's first; left alone, HDMI-A-1 got the 1 and DP-2 the 2.
for name, base in pairs(workspaceBlocks) do
    for i = 1, 10 do
        hl.workspace_rule({ workspace = tostring(base + i), monitor = name, default = i == 1 })
    end
end

-- Shell fit-up. Last, so it wins: the bar already reserves 51px at the
-- top, so the top gap is smaller.
hl.config({
    general = {
        gaps_out = { top = 20, bottom = 30, left = 30, right = 30 },
    },
    decoration = {
        -- Focused windows at 0.8; inactive ones keep the 0.7 from the block above.
        active_opacity = 0.8,
    },
})

-- Zen and NIKKE, opaque while focused: global opacity would put the wallpaper through the page or
-- the game. Zen's translucency is redone inside Zen (zen.widget.linux.transparency in user.js), and
-- its inactive value stays a factor so it tracks the global; NIKKE overrides both, often watched
-- unfocused. NIKKE is matched on its appid class, not umu's generic one. The value must be the rule
-- string: a bare number is a factor on the global opacity (1.0 x 0.8 is 0.8), and
-- opacity_override/opacity_inactive are not keys of this schema.
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

-- Settings made in the shell: the Settings window's Hyprland page writes
-- gui-settings.lua (hypr_settings.py), never this file. Run last so those choices win;
-- with no such file nothing happens.
do
    local path = os.getenv("HOME") .. "/.config/hypr/gui-settings.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        dofile(path)
    end
end
