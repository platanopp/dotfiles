-- QML support. LazyVim ships no extra for it, and this machine writes a
-- whole Quickshell config in it.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        qmlls = {
          -- Arch names the binary after the Qt major version, and Mason has
          -- nothing to install here: qmlls6 comes with qt6-declarative,
          -- which is already a dependency of Quickshell.
          mason = false,
          cmd = { "qmlls6", "-E" },
        },
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "qmljs" })
      end
    end,
  },
}
