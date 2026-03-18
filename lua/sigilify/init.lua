local M = {}

---@param opts? SigilifyConfig
function M.setup(opts)
  local config  = require("sigilify.config")
  local conceal = require("sigilify.conceal")
  local keymap  = require("sigilify.keymap")

  config.set(opts or {})

  -- Re-create autocmds (setup clears the augroup, so repeat calls are safe)
  conceal.setup()
  keymap.setup()

  -- Mark as loaded so plugin/sigilify.lua doesn't re-run defaults
  vim.g.loaded_sigilify = true
end

return M
