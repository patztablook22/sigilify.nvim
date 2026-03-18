--- sigilify/keymap.lua
--- Smart <BS> / <DEL> / x that delete whole operator sequences in one keystroke.

local config = require("sigilify.config")

local M = {}

--- Collect every pattern that is active in *any* filetype so the keymaps
--- handle them regardless of the current ft.  We build a set of pattern
--- strings keyed by length (3 then 2) for fast lookup.
---@return table<integer, table<string, true>>  indexed by pattern length
local function build_pattern_sets()
  local cfg    = config.get()
  local groups = cfg.groups
  local sets   = { [3] = {}, [2] = {} }

  local function add_list(list)
    if not list or list == false then return end
    for _, name in ipairs(list) do
      local g = groups[name]
      if g then
        local len = #g.pattern
        if sets[len] then
          sets[len][g.pattern] = true
        end
      end
    end
  end

  add_list(cfg.default_active)
  for _, list in pairs(cfg.ft_active) do
    add_list(list)
  end

  return sets
end

--- Find a multi-char operator at or adjacent to `col` (0-indexed) in `line`.
--- Returns start_col, end_col (both 0-indexed, end exclusive) or nil.
---@param line   string
---@param col    integer   0-indexed cursor column
---@param mode   "backspace"|"delete"
---@return integer|nil, integer|nil
local function find_operator(line, col, mode)
  local sets = build_pattern_sets()

  for len = 3, 2, -1 do
    local set = sets[len]
    if mode == "backspace" then
      -- Pattern ending at cursor (delete left)
      local s = col - len
      if s >= 0 then
        local pat = line:sub(s + 1, col)   -- lua 1-indexed
        if set[pat] then return s, col end
      end
      -- Pattern starting one before cursor (straddles)
      s = col - len + 1
      if s >= 0 then
        local pat = line:sub(s + 1, s + len)
        if set[pat] then return s, s + len end
      end
    else
      -- mode == "delete": pattern starting at cursor
      local pat = line:sub(col + 1, col + len)
      if set[pat] then return col, col + len end
      -- Pattern ending just after cursor
      local s = col - len + 1
      if s >= 0 then
        local pat2 = line:sub(s + 1, s + len)
        if set[pat2] then return s, s + len end
      end
    end
  end

  return nil, nil
end

local function backspace_handler()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line     = vim.api.nvim_get_current_line()
  local s, e     = find_operator(line, col, "backspace")
  if s then
    vim.api.nvim_buf_set_text(0, row - 1, s, row - 1, e, {})
  else
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<BS>", true, false, true), "n", true
    )
  end
end

local function delete_handler()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line     = vim.api.nvim_get_current_line()
  local s, e     = find_operator(line, col, "delete")
  if s then
    vim.api.nvim_buf_set_text(0, row - 1, s, row - 1, e, {})
  else
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<DEL>", true, false, true), "n", true
    )
  end
end

function M.setup()
  if not config.get().keymaps then return end

  local opts = { noremap = true }
  vim.keymap.set("i", "<BS>",  backspace_handler, vim.tbl_extend("force", opts, { desc = "Sigilify: smart backspace" }))
  vim.keymap.set("i", "<DEL>", delete_handler,    vim.tbl_extend("force", opts, { desc = "Sigilify: smart delete (insert)" }))
  vim.keymap.set("n", "x",     delete_handler,    vim.tbl_extend("force", opts, { desc = "Sigilify: smart x" }))
  vim.keymap.set("n", "<DEL>", delete_handler,    vim.tbl_extend("force", opts, { desc = "Sigilify: smart delete (normal)" }))
end

return M
