-- Reports the keybinds of a Hyprland Lua config as JSON, for the shell's
-- control panel.
--
-- The config is Lua, and its binds are built with locals, concatenation and
-- a `for` loop over the workspace keys -- none of which survive a regex. So
-- instead of parsing the file we *run* it against a stub `hl` table that
-- records calls and does nothing else. Whatever the file computes is what we
-- report, and it keeps working when the file is rewritten.
--
-- `hyprctl binds` cannot answer this: in Lua mode every bind reports the
-- dispatcher `__lua` with an opaque callback index, so it knows the keys but
-- not what any of them do.

local config_path = arg[1]
if not config_path or config_path == "" then
    config_path = (os.getenv("HOME") or "") .. "/.config/hypr/hyprland.lua"
end

local config_dir = config_path:match("^(.*)/[^/]*$") or "."

-- ── Recording ────────────────────────────────────────────────────────────

-- Every bind and unbind in the order the config makes them, so a later
-- unbind/rebind (which is how HyprMod's generated file overrides SUPER+R)
-- resolves the same way Hyprland resolves it.
local events = {}
local includes = {}

local Proxy = {}

-- Any `hl.*` path the config touches becomes a value that can be indexed
-- further and called: `hl.dsp.window.float({...})` records its path and
-- arguments rather than dispatching anything.
local function proxy(path, args)
    return setmetatable({ _path = path, _args = args }, Proxy)
end

Proxy.__index = function(t, k)
    return proxy(rawget(t, "_path") .. "." .. tostring(k))
end
Proxy.__call = function(t, ...)
    return proxy(rawget(t, "_path"), table.pack(...))
end
Proxy.__tostring = function(t) return rawget(t, "_path") end
Proxy.__concat = function(a, b) return tostring(a) .. tostring(b) end

local function is_proxy(v)
    return type(v) == "table" and getmetatable(v) == Proxy
end

local handlers = {}

function handlers.bind(keyspec, action, opts)
    if type(keyspec) == "string" then
        events[#events + 1] = {
            kind = "bind",
            keyspec = keyspec,
            action = action,
            opts = type(opts) == "table" and not is_proxy(opts) and opts or nil,
        }
    end
    return proxy("hl.bind")
end

function handlers.unbind(keyspec)
    if type(keyspec) == "string" then
        events[#events + 1] = { kind = "unbind", keyspec = keyspec }
    end
    return proxy("hl.unbind")
end

local hl = setmetatable({}, {
    __index = function(_, k)
        local h = handlers[k]
        if h then return h end
        return proxy("hl." .. tostring(k))
    end,
})

-- ── Sandbox ──────────────────────────────────────────────────────────────

local env
local loaded = {}

-- `require`/`dofile` resolve next to the entry file and run in the same
-- sandbox, so a config split across files (HyprMod's generated
-- hyprland-gui.lua being the usual one) is followed rather than missed.
local function run_file(path, name)
    local chunk, err = loadfile(path, "t", env)
    if not chunk then error(err, 0) end
    includes[#includes + 1] = path
    loaded[name or path] = true
    return chunk()
end

local function sandbox_require(name)
    if type(name) ~= "string" then return true end
    if loaded[name] then return true end
    local path = config_dir .. "/" .. name:gsub("%.", "/") .. ".lua"
    local f = io.open(path, "r")
    if not f then
        loaded[name] = true
        return true
    end
    f:close()
    return run_file(path, name) or true
end

local function sandbox_dofile(path)
    if type(path) ~= "string" then return true end
    if not path:match("^/") then path = config_dir .. "/" .. path end
    local f = io.open(path, "r")
    if not f then return true end
    f:close()
    return run_file(path)
end

env = {
    hl = hl,
    assert = assert, error = error, ipairs = ipairs, next = next,
    pairs = pairs, pcall = pcall, xpcall = xpcall, select = select,
    tonumber = tonumber, tostring = tostring, type = type, unpack = table.unpack,
    setmetatable = setmetatable, getmetatable = getmetatable,
    rawget = rawget, rawset = rawset, rawequal = rawequal, rawlen = rawlen,
    string = string, table = table, math = math,
    -- Nothing here should touch the system: os/io are cut down to the
    -- lookups a config legitimately makes while reading itself.
    os = { date = os.date, time = os.time, clock = os.clock, getenv = os.getenv },
    io = { open = io.open },
    print = function() end,
    require = sandbox_require,
    dofile = sandbox_dofile,
}
env._G = env

local ok, load_err = pcall(run_file, config_path)

-- ── Describing ───────────────────────────────────────────────────────────

local MOD_NAMES = {
    SUPER = "Super", MOD4 = "Super", WIN = "Super",
    SHIFT = "Shift", ALT = "Alt", MOD1 = "Alt",
    CTRL = "Ctrl", CONTROL = "Ctrl", CAPS = "Caps Lock",
}

local KEY_NAMES = {
    left = "←", right = "→", up = "↑", down = "↓",
    space = "Space", return_ = "Enter", ["return"] = "Enter",
    escape = "Esc", tab = "Tab", print = "Print Screen",
    mouse_down = "Wheel ↓", mouse_up = "Wheel ↑",
    ["mouse:272"] = "Left click", ["mouse:273"] = "Right click",
    XF86AudioRaiseVolume = "Vol +", XF86AudioLowerVolume = "Vol −",
    XF86AudioMute = "Mute", XF86AudioMicMute = "Mic",
    XF86MonBrightnessUp = "Brightness +", XF86MonBrightnessDown = "Brightness −",
    XF86AudioNext = "Media next", XF86AudioPrev = "Media prev.",
    XF86AudioPlay = "Media play", XF86AudioPause = "Media pause",
}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "SUPER + SHIFT + P" -> mods {"SUPER","SHIFT"}, key "P". The last token is
-- the key; everything before it is a modifier.
local function split_keyspec(spec)
    local parts = {}
    for raw in spec:gmatch("[^+]+") do
        local token = trim(raw)
        if token ~= "" then parts[#parts + 1] = token end
    end
    if #parts == 0 then return {}, "" end
    local key = table.remove(parts)
    return parts, key
end

local function canonical(spec)
    local mods, key = split_keyspec(spec)
    local up = {}
    for _, m in ipairs(mods) do up[#up + 1] = m:upper() end
    table.sort(up)
    return table.concat(up, "+") .. ">" .. key:lower()
end

local function pretty_keyspec(spec)
    local mods, key = split_keyspec(spec)
    local out = {}
    for _, m in ipairs(mods) do
        out[#out + 1] = MOD_NAMES[m:upper()] or m
    end
    local label = KEY_NAMES[key]
    if not label then
        local stripped = key:match("^XF86(.+)$")
        if stripped then
            label = stripped
        elseif #key == 1 then
            label = key:upper()
        else
            label = key:sub(1, 1):upper() .. key:sub(2)
        end
    end
    out[#out + 1] = label
    return table.concat(out, " + "), label
end

-- Commands are matched on the whole string, not the first word: the file
-- manager bind runs `kitty --class yazi -e yazi`, whose leading binary says
-- "terminal" and whose point is yazi.
local EXEC_RULES = {
    { "grimblast",                 "Screenshot" },
    { "yazi",                      "File manager" },
    { "rofi",                      "Application launcher" },
    { "veila lock",                "Lock screen" },
    { "hyprshutdown",              "Log out" },
    { "wpctl set%-volume.*%%%+",   "Volume up" },
    { "wpctl set%-volume.*%%%-",   "Volume down" },
    { "wpctl set%-mute.*SOURCE",   "Mute microphone" },
    { "wpctl set%-mute.*SINK",     "Mute audio" },
    { "brightnessctl.*%%%+",       "Brightness up" },
    { "brightnessctl.*%%%-",       "Brightness down" },
    { "playerctl next",            "Next track" },
    { "playerctl previous",        "Previous track" },
    { "playerctl play%-pause",     "Play / pause" },
    { "kitty",                     "Terminal" },
}

local function describe_exec(cmd)
    for _, rule in ipairs(EXEC_RULES) do
        if cmd:find(rule[1]) then return rule[2] end
    end
    local first = cmd:match("^%s*([%w%-_%.]+)")
    return first and (first:sub(1, 1):upper() .. first:sub(2)) or "Run a command"
end

local DIRECTIONS = {
    left = "left", right = "right",
    up = "arriba", down = "abajo",
}

-- "next"/"previous" name a direction rather than a place, so they read as a
-- phrase instead of slotting into "Workspace <name>".
local RELATIVE_WS = {
    next = { focus = "Next workspace", move = "Move to the next workspace" },
    previous = { focus = "Previous workspace", move = "Move to the previous workspace" },
}

local function workspace_label(ws)
    if type(ws) == "number" then return tostring(ws), true end
    local s = tostring(ws)
    if s == "e+1" then return "next", false end
    if s == "e-1" then return "previous", false end
    local special = s:match("^special:(.+)$")
    if special then return special, false end
    return s, tonumber(s) ~= nil
end

-- Returns a table: the action text, the raw command when there is one, the
-- category the bind belongs under, and -- for the numbered workspace binds --
-- a fold tag plus the workspace it targets, so the ten of them can collapse
-- into one row.
local function describe(action)
    if not is_proxy(action) then return { action = "Custom action", category = "Windows" } end

    local path = rawget(action, "_path") or ""
    local disp = path:gsub("^hl%.dsp%.", ""):gsub("^hl%.", "")
    local args = rawget(action, "_args") or { n = 0 }
    local a1 = args[1]
    local opts = (type(a1) == "table" and not is_proxy(a1)) and a1 or nil

    if disp == "exec_cmd" or disp == "exec" then
        local cmd = type(a1) == "string" and a1 or ""
        return { action = describe_exec(cmd), command = cmd, category = "Applications" }
    end
    if disp == "window.close" then return { action = "Close window", category = "Windows" } end
    if disp == "window.pseudo" then return { action = "Toggle pseudo-tiling", category = "Windows" } end
    if disp == "window.drag" then return { action = "Move window with the mouse", category = "Windows" } end
    if disp == "window.resize" then return { action = "Resize with the mouse", category = "Windows" } end
    if disp == "window.float" then return { action = "Toggle floating", category = "Windows" } end
    if disp == "window.fullscreen" then return { action = "Fullscreen", category = "Windows" } end
    if disp == "exit" then return { action = "Quit Hyprland", category = "System" } end
    -- Dispatched over Hyprland's global-shortcuts protocol, so the name is
    -- claimed by whichever client registered it rather than by Hyprland.
    if disp == "global" then
        local name = type(a1) == "string" and a1 or ""
        if name == "quickshell:keybinds" then
            return { action = "Show keyboard shortcuts", category = "System", overlay = true }
        end
        if name == "quickshell:wallpapers" then
            return { action = "Choose the wallpaper", category = "System" }
        end
        if name == "quickshell:micmute" then
            return { action = "Mute or unmute the microphone", category = "System" }
        end
        return { action = "Global shortcut: " .. name, category = "System" }
    end
    if disp == "layout" then
        local mode = type(a1) == "string" and a1 or ""
        local text = mode == "togglesplit" and "Toggle split" or ("Layout: " .. mode)
        return { action = text, category = "Windows" }
    end
    if disp == "workspace.toggle_special" then
        local name = type(a1) == "string" and a1 or "magic"
        return { action = "Special workspace \"" .. name .. "\"", category = "Workspaces" }
    end
    if disp == "focus" then
        if opts and opts.direction then
            return {
                action = "Focus " .. (DIRECTIONS[opts.direction] or opts.direction),
                category = "Windows",
            }
        end
        if opts and opts.workspace ~= nil then
            local label, numeric = workspace_label(opts.workspace)
            if numeric then
                return {
                    action = "Go to workspace " .. label, category = "Workspaces",
                    fold = "ws-focus", workspace = label,
                }
            end
            local relative = RELATIVE_WS[label]
            return {
                action = relative and relative.focus or ("Workspace " .. label),
                category = "Workspaces",
            }
        end
    end
    if disp == "window.move" then
        if opts and opts.workspace ~= nil then
            local label, numeric = workspace_label(opts.workspace)
            if numeric then
                return {
                    action = "Move to workspace " .. label, category = "Workspaces",
                    fold = "ws-move", workspace = label,
                }
            end
            local relative = RELATIVE_WS[label]
            return {
                action = relative and relative.move or ("Move to \"" .. label .. "\""),
                category = "Workspaces",
            }
        end
        if opts and opts.direction then
            return {
                action = "Move window " .. (DIRECTIONS[opts.direction] or opts.direction),
                category = "Windows",
            }
        end
    end

    local readable = disp:gsub("[%._]", " ")
    return { action = readable:sub(1, 1):upper() .. readable:sub(2), category = "System" }
end

-- ── Resolve ──────────────────────────────────────────────────────────────

-- Replayed in file order: an unbind drops the binding made before it and a
-- rebind of the same key replaces it, so the effective set is what a HyprMod
-- override actually leaves behind.
local resolved = {}
local order = {}

for _, ev in ipairs(events) do
    local id = canonical(ev.keyspec)
    if ev.kind == "unbind" then
        resolved[id] = nil
    else
        if resolved[id] == nil then order[#order + 1] = id end
        resolved[id] = ev
    end
end

local entries = {}
for _, id in ipairs(order) do
    local ev = resolved[id]
    if ev then
        local keys, key_label = pretty_keyspec(ev.keyspec)
        local mods, key = split_keyspec(ev.keyspec)
        local d = describe(ev.action)
        local mod_key = {}
        for _, m in ipairs(mods) do mod_key[#mod_key + 1] = m:upper() end
        table.sort(mod_key)
        entries[#entries + 1] = {
            keys = keys,
            key_label = key_label,
            mod_key = table.concat(mod_key, "+"),
            action = d.action,
            command = d.command,
            fold = d.fold,
            workspace = d.workspace,
            overlay = d.overlay,
            -- A media key is a media key whatever it dispatches, so the
            -- hardware wins over the action for these.
            category = key:match("^XF86") and "Media" or d.category,
        }
    end
end

-- Ten `Super + N` rows saying the same thing crowd out everything else, so a
-- run of numbered workspace binds sharing a modifier collapses to one row.
local function fold_workspaces(list)
    local out = {}
    local seen = {}
    for _, e in ipairs(list) do
        if not e.fold then
            out[#out + 1] = e
        else
            local bucket = e.fold .. "|" .. e.mod_key
            local at = seen[bucket]
            if not at then
                local folded = {
                    keys = e.keys, key_label = e.key_label, category = e.category,
                    action = e.action,
                    _first_key = e.key_label, _last_key = e.key_label,
                    _first_ws = e.workspace, _last_ws = e.workspace,
                    _base = e.fold == "ws-move" and "Move to workspace"
                            or "Go to workspace",
                    -- Everything ahead of the key, "Super + Shift + " included.
                    _mods = e.keys:sub(1, #e.keys - #e.key_label),
                }
                out[#out + 1] = folded
                seen[bucket] = folded
            else
                at._last_key = e.key_label
                at._last_ws = e.workspace
            end
        end
    end
    for _, e in ipairs(out) do
        if e._first_key and e._first_key ~= e._last_key then
            e.keys = e._mods .. e._first_key .. " … " .. e._last_key
            e.action = e._base .. " " .. e._first_ws .. "–" .. e._last_ws
        end
        e._first_key, e._last_key = nil, nil
        e._first_ws, e._last_ws, e._base, e._mods = nil, nil, nil, nil
    end
    return out
end

entries = fold_workspaces(entries)

local CATEGORY_ORDER = { "Applications", "Windows", "Workspaces", "Media", "System" }

local grouped, index = {}, {}
for _, name in ipairs(CATEGORY_ORDER) do
    local g = { name = name, binds = {} }
    grouped[#grouped + 1] = g
    index[name] = g
end
for _, e in ipairs(entries) do
    local g = index[e.category] or index["Windows"]
    g.binds[#g.binds + 1] = e
end

-- ── Emit ─────────────────────────────────────────────────────────────────

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function jstr(s)
    if s == nil then return "null" end
    return '"' .. tostring(s):gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04X", c:byte())
    end) .. '"'
end

-- The keys the config points at this shell's cheatsheet. Reported
-- separately so the control panel can label its button with the live bind
-- instead of a combination hardcoded in the QML.
local overlay_keys = nil
for _, e in ipairs(entries) do
    if e.overlay then overlay_keys = e.keys end
end

local out = {}
out[#out + 1] = '{"source":' .. jstr(config_path)
out[#out + 1] = ',"overlayKeys":' .. jstr(overlay_keys)
out[#out + 1] = ',"error":' .. (ok and "null" or jstr(tostring(load_err)))
out[#out + 1] = ',"count":' .. #entries
out[#out + 1] = ',"sources":['
for i, path in ipairs(includes) do
    out[#out + 1] = (i > 1 and "," or "") .. jstr(path)
end
out[#out + 1] = '],"groups":['

local first_group = true
for _, g in ipairs(grouped) do
    if #g.binds > 0 then
        out[#out + 1] = (first_group and "" or ",") .. '{"name":' .. jstr(g.name) .. ',"binds":['
        first_group = false
        for i, b in ipairs(g.binds) do
            -- The command is only carried for launchers, where "Terminal"
            -- is a name for `kitty` and the reader may well want the other.
            -- Elsewhere it restates the label: a row reading "Subir
            -- volumen / wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
            -- costs a line and says nothing new.
            local cmd = g.name == "Applications" and b.command or nil
            out[#out + 1] = (i > 1 and "," or "")
                .. '{"keys":' .. jstr(b.keys)
                .. ',"action":' .. jstr(b.action)
                .. ',"command":' .. jstr(cmd)
                .. "}"
        end
        out[#out + 1] = "]}"
    end
end
out[#out + 1] = "]}"

io.write(table.concat(out), "\n")
