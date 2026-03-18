local M = {}

---@param opts? SigilifyConfig
function M.setup(opts)
  local config = require("sigilify.config")
  local conceal = require("sigilify.conceal")
  local keymap  = require("sigilify.keymap")

  config.set(opts or {})
  conceal.setup()
  keymap.setup()
end

return M
