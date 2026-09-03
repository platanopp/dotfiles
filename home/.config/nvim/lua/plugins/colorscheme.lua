-- The editor wearing the terminal's palette.
--
-- kitty's theme here is deliberately monochrome: background #1a1a1a and
-- sixteen ANSI slots that are all greys, no hue anywhere. An editor sitting
-- inside that window in full One Dark was the one colourful thing on the
-- desktop, so the syntax moves onto the same greyscale.
--
-- What keeps its colour is what carries meaning rather than grammar: an LSP
-- error, a warning, a git sign. That is the rule the shell already follows --
-- Theme.qml's accent is the neutral #d8d8d8, and its red/green/yellow only
-- ever appear as error/warning/success -- so the three surfaces now agree.
--
-- Grammar is read by brightness and weight instead of hue, on a six-step
-- ramp: keywords brightest and bold, then functions, types, variables,
-- literals, and comments dimmest and italic.

-- kitty's own values, so these are a copy rather than an approximation.
local term = {
  bg = "#1a1a1a",     -- background
  fg = "#e2e2e2",     -- foreground / color15
  sel = "#5b5b5b",    -- selection_background
  cursor = "#bebebe", -- cursor
  tab = "#232323",    -- active_tab_background
  dim = "#a5a5a5",    -- color7
}

-- Meaning, not grammar. Taken from the shell's Theme.qml, so a hot CPU on the
-- bar and a type error in the editor are the same red.
local signal = {
  red = "#e06c75",
  green = "#98c379",
  yellow = "#e5c07b",
  cyan = "#56b6c2",
}

return {
  {
    "navarasu/onedark.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "darker",
      transparent = false,
      -- nvim's own :terminal palette, which would otherwise stay One Dark's
      -- and disagree with the kitty tab next to it.
      term_colors = true,
      ending_tildes = false,

      -- Hue is gone, so weight carries the distinction colour used to.
      code_style = {
        comments = "italic",
        keywords = "bold",
        functions = "bold",
        strings = "none",
        variables = "none",
      },

      -- Diagnostics are the one thing that must not be muted: `darker` routes
      -- them through dark_red/dark_yellow, which are greys below, and
      -- `background` tints the line behind the virtual text. Both off, and
      -- the colours are put back by name in `highlights`.
      diagnostics = {
        darker = false,
        undercurl = true,
        background = false,
      },

      -- onedark reaches every syntax group through these named slots, so
      -- greying the slots greys the whole scheme. The name on the left is the
      -- hue being replaced; the comment is what it actually paints.
      colors = {
        black = term.bg,
        bg0 = term.bg,          -- editor ground, exactly kitty's
        bg1 = "#1f1f1f",
        bg2 = term.tab,
        bg3 = "#2b2b2b",
        bg_d = "#141414",       -- statusline and sidebars, a step down
        bg_blue = term.dim,     -- completion menu selection
        bg_yellow = term.cursor, -- search match
        fg = "#d8d8d8",         -- plain text

        purple = "#f2f2f2",     -- keywords, operators, statements
        blue = "#dadada",       -- functions
        yellow = "#bebebe",     -- types
        red = term.dim,         -- variables and identifiers
        orange = "#9a9a9a",     -- numbers and booleans
        cyan = "#9a9a9a",       -- constants
        green = "#8c8c8c",      -- strings
        grey = "#767676",       -- comments; dim, but still meant to be read
        light_grey = "#6b6b6b", -- delimiters and punctuation

        dark_cyan = "#7a7a7a",
        dark_red = "#5b5b5b",
        dark_yellow = "#6b6b6b",
        dark_purple = "#6b6b6b",

        -- Diff blocks keep a tint: a hunk is meaning, not grammar. Dark
        -- enough that the grey text on top still reads.
        diff_add = "#1f2a1c",
        diff_delete = "#2c1e20",
        diff_change = "#2a2620",
        diff_text = "#3a3428",
      },

      highlights = {
        -- Panels on the terminal's ground rather than a lighter grey.
        NormalFloat = { bg = term.bg },
        FloatBorder = { fg = "#444444", bg = term.bg },

        -- kitty's selection, so dragging over text looks the same in both.
        Visual = { fg = term.fg, bg = term.sel },

        -- nvim's own defaults ship a mint green for these two.
        ModeMsg = { fg = term.dim, fmt = "bold" },
        OkMsg = { fg = signal.green },

        -- Everything below earns its colour back.
        DiagnosticError = { fg = signal.red },
        DiagnosticWarn = { fg = signal.yellow },
        DiagnosticInfo = { fg = signal.cyan },
        DiagnosticHint = { fg = signal.green },
        DiagnosticOk = { fg = signal.green },
        DiagnosticVirtualTextError = { fg = signal.red },
        DiagnosticVirtualTextWarn = { fg = signal.yellow },
        DiagnosticVirtualTextInfo = { fg = signal.cyan },
        DiagnosticVirtualTextHint = { fg = signal.green },
        DiagnosticUnderlineError = { fmt = "undercurl", sp = signal.red },
        DiagnosticUnderlineWarn = { fmt = "undercurl", sp = signal.yellow },
        DiagnosticUnderlineInfo = { fmt = "undercurl", sp = signal.cyan },
        DiagnosticUnderlineHint = { fmt = "undercurl", sp = signal.green },

        GitSignsAdd = { fg = signal.green },
        GitSignsAddNr = { fg = signal.green },
        GitSignsAddLn = { fg = signal.green },
        GitSignsChange = { fg = signal.yellow },
        GitSignsChangeNr = { fg = signal.yellow },
        GitSignsChangeLn = { fg = signal.yellow },
        GitSignsDelete = { fg = signal.red },
        GitSignsDeleteNr = { fg = signal.red },
        GitSignsDeleteLn = { fg = signal.red },

        Added = { fg = signal.green },
        Changed = { fg = signal.yellow },
        Removed = { fg = signal.red },
        DiffAdded = { fg = signal.green },
        DiffChanged = { fg = signal.yellow },
        DiffRemoved = { fg = signal.red },
        DiffDeleted = { fg = signal.red },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "onedark",
    },
  },
}
