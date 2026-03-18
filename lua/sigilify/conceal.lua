--- sigilify/conceal.lua
--- Orchestrates the two rendering paths:
---
---   TS path    — nvim_buf_set_extmark with conceal, driven by sigilify/ts.lua.
---                Used for groups that have a ts_query and whose grammar is loaded.
---
---   Regex path — vim.fn.matchadd with \V-escaped literal patterns.
---                Used as fallback when TS is unavailable or a group has no query.
---
--- On BufEnter / FileType the module:
---   1. Runs M.apply() which calls ts.render() to get back a list of groups
---      the TS layer could NOT handle.
---   2. Calls matchadd for those unhandled groups only.
---   3. Stores match IDs per buffer for cleanup.
---
--- Subsequently, ts.lua fires "User SigilifyTSUpdate" after each debounced
--- re-render, which updates the matchadd set for the new unhandled list.

local config = require("sigilify.config")
local ts     = require("sigilify.ts")

local M = {}

-- buf → { match_id, ... }
local _buf_matches = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Regex (matchadd) helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function escape_pattern(s)
  return "\\V" .. s:gsub("\\", "\\\\")
end

---@param buf integer
local function clear_matches(buf)
  local ids = _buf_matches[buf]
  if not ids then return end
  local winid = vim.fn.bufwinid(buf)
  if winid ~= -1 then
    for _, id in ipairs(ids) do
      pcall(vim.fn.matchdelete, id, winid)
    end
  end
  _buf_matches[buf] = nil
end

--- Place matchadd conceals for a specific list of group names.
---@param buf        integer
---@param group_names string[]
local function apply_matchadd(buf, group_names)
  clear_matches(buf)
  if #group_names == 0 then return end

  local cfg    = config.get()
  local groups = cfg.groups

  -- Sort: longer patterns first to avoid prefix shadowing
  local sorted = {}
  for _, name in ipairs(group_names) do
    local g = groups[name]
    if g then
      table.insert(sorted, g)
    end
  end
  table.sort(sorted, function(a, b) return #a.pattern > #b.pattern end)

  local ids = {}
  for _, g in ipairs(sorted) do
    local id = vim.fn.matchadd(
      "Conceal",
      escape_pattern(g.pattern),
      10, -1,
      { conceal = g.symbol }
    )
    if id >= 0 then table.insert(ids, id) end
  end
  _buf_matches[buf] = ids
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main apply — called on BufEnter / FileType
-- ─────────────────────────────────────────────────────────────────────────────

local function apply()
  local buf = vim.api.nvim_get_current_buf()
  local ft  = vim.bo[buf].filetype
  if ft == "" then return end

  local active = config.active_groups_for_ft(ft)
  if active == false then
    clear_matches(buf)
    return
  end

  local cfg = config.get()

  if cfg.ts_fallback then
    -- TS render returns the groups it couldn't handle
    ts.attach(buf)
    local unhandled = ts.render(buf, ft)
    apply_matchadd(buf, unhandled)
  else
    -- TS disabled entirely; matchadd everything
    clear_matches(buf)
    apply_matchadd(buf, active)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Setup
-- ─────────────────────────────────────────────────────────────────────────────

function M.setup()
  local cfg = config.get()

  vim.opt.conceallevel  = cfg.conceallevel
  vim.opt.concealcursor = cfg.concealcursor
  vim.api.nvim_set_hl(0, "Conceal", { fg = cfg.conceal_color })

  local aug = vim.api.nvim_create_augroup("Sigilify", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("SigilifyHL", { clear = true }),
    callback = function()
      vim.api.nvim_set_hl(0, "Conceal", { fg = config.get().conceal_color })
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    group    = aug,
    callback = apply,
  })

  -- After each TS re-render: refresh the matchadd set for newly unhandled groups
  vim.api.nvim_create_autocmd("User", {
    pattern  = "SigilifyTSUpdate",
    group    = aug,
    callback = function(ev)
      local data = ev.data or {}
      if data.buf and vim.api.nvim_buf_is_valid(data.buf) then
        apply_matchadd(data.buf, data.unhandled or {})
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group    = aug,
    callback = function(ev)
      clear_matches(ev.buf)
      ts.detach(ev.buf)
    end,
  })
end

return M
