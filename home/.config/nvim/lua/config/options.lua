-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- LazyVim's Python extra defaults to pyright; the one installed here is
-- basedpyright, its fork with stricter inference and no license gate. Without
-- this the extra enables pyright, which is not installed, and Python is left
-- with ruff alone -- lint and format, but no types, no go-to-definition.
vim.g.lazyvim_python_lsp = "basedpyright"
