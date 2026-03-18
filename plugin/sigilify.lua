-- Auto-setup with defaults so the plugin works out of the box
-- (e.g. lazy.nvim spec: { "patztablook22/sigilify.nvim" })
-- Users can still call require("sigilify").setup(opts) to override.

if vim.g.loaded_sigilify then return end
vim.g.loaded_sigilify = true

require("sigilify").setup()
