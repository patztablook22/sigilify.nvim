--- sigilify/ts.lua
--- Tree-sitter powered concealment via extmarks.
--- Each buffer gets its own namespace and a debounced re-render attached via
--- nvim_buf_attach.  Only the @sigil capture in each query is concealed.

local config = require("sigilify.config")

local M = {}

-- Namespace for all extmarks placed by this module
local NS = vim.api.nvim_create_namespace("sigilify_ts")

-- buf → uv_timer handle (for debouncing)
local _timers = {}

-- buf → true  (buffers we have already attached to)
local _attached = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

--- Check whether a TS parser is available for a language/filetype.
---@param ft string
---@return boolean
local function has_parser(ft)
  local ok, _ = pcall(vim.treesitter.get_parser, 0, ft)
  return ok
end

--- Compile (or retrieve from cache) a TS query for a language.
--- Returns nil on failure.
---@param lang string
---@param query_str string
---@return vim.treesitter.Query|nil
local function compile_query(lang, query_str)
  local ok, q = pcall(vim.treesitter.query.parse, lang, query_str)
  if not ok then
    -- Silently ignore bad queries so one bad entry doesn't break the rest
    return nil
  end
  return q
end

--- Map a filetype to the Tree-sitter language name.
--- Usually identical, but a few differ (e.g. javascriptreact → javascript).
---@param ft string
---@return string
local function ft_to_lang(ft)
  local overrides = {
    javascriptreact = "javascript",
    typescriptreact = "typescript",
    sh              = "bash",
  }
  return overrides[ft] or ft
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Core render
-- ─────────────────────────────────────────────────────────────────────────────

--- Clear all sigilify extmarks in a buffer.
---@param buf integer
local function clear_extmarks(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  end
end

--- Render TS-based concealment for one group in buf.
--- Returns true if any concealment was placed.
---@param buf     integer
---@param ft      string
---@param name    string
---@param group   SigilifyGroup
---@param parser  vim.treesitter.LanguageTree
---@return boolean
local function render_group(buf, ft, name, group, parser)
  local lang = ft_to_lang(ft)

  -- Determine which query string to use (ft override > group default > none)
  local q_str = config.ts_query_for(ft, name)
  if q_str == false then return false end   -- explicitly disabled for this ft
  if q_str == nil   then q_str = group.ts_query end
  if not q_str      then return false end   -- no TS query defined

  local q = compile_query(lang, q_str)
  if not q then return false end

  local tree = parser:parse()[1]
  if not tree then return false end
  local root = tree:root()

  local placed = false

  for id, node in q:iter_captures(root, buf, 0, -1) do
    local capture_name = q.captures[id]
    if capture_name == "sigil" then
      local sr, sc, er, ec = node:range()
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, sr, sc, {
        end_row       = er,
        end_col       = ec,
        conceal       = group.symbol,
        -- Priority slightly above default so we win over generic syntax conceal
        priority      = 120,
        -- Don't interfere with spell checking etc.
        spell         = false,
      })
      placed = true
    end
  end

  return placed
end

--- Full render pass for a buffer: places extmarks for all active TS groups.
--- Returns a list of group names that could NOT be handled by TS
--- (caller should hand those to matchadd).
---@param buf integer
---@param ft  string
---@return string[] unhandled_groups
function M.render(buf, ft)
  if not vim.api.nvim_buf_is_valid(buf) then return {} end

  clear_extmarks(buf)

  local lang = ft_to_lang(ft)
  if not has_parser(ft) then
    -- No grammar available; everything falls back to matchadd
    return config.active_groups_for_ft(ft) or {}
  end

  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if not ok or not parser then
    return config.active_groups_for_ft(ft) or {}
  end

  local active = config.active_groups_for_ft(ft)
  if active == false then return {} end

  local cfg      = config.get()
  local groups   = cfg.groups
  local unhandled = {}

  for _, name in ipairs(active) do
    local group = groups[name]
    if group then
      local handled = render_group(buf, ft, name, group, parser)
      if not handled then
        table.insert(unhandled, name)
      end
    end
  end

  return unhandled
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Debounced re-render on buffer change
-- ─────────────────────────────────────────────────────────────────────────────

local function schedule_render(buf)
  local ft = vim.bo[buf].filetype
  if ft == "" then return end

  -- Cancel any pending timer for this buffer
  if _timers[buf] then
    pcall(function() _timers[buf]:stop(); _timers[buf]:close() end)
    _timers[buf] = nil
  end

  local delay = config.get().ts_debounce_ms
  local timer  = vim.uv.new_timer()
  _timers[buf] = timer

  timer:start(delay, 0, vim.schedule_wrap(function()
    if _timers[buf] == timer then _timers[buf] = nil end
    timer:stop(); timer:close()

    if not vim.api.nvim_buf_is_valid(buf) then return end

    -- TS render — unhandled groups are returned so conceal.lua can matchadd them
    -- We fire a custom event that conceal.lua listens to for the hybrid update.
    local unhandled = M.render(buf, ft)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "SigilifyTSUpdate",
      data    = { buf = buf, unhandled = unhandled },
    })
  end))
end

--- Attach incremental re-render to a buffer (called once per buffer).
---@param buf integer
function M.attach(buf)
  if _attached[buf] then return end
  _attached[buf] = true

  vim.api.nvim_buf_attach(buf, false, {
    on_bytes = function(_, b)
      schedule_render(b)
    end,
    on_detach = function(_, b)
      _attached[b] = nil
      if _timers[b] then
        pcall(function() _timers[b]:stop(); _timers[b]:close() end)
        _timers[b] = nil
      end
    end,
  })
end

--- Clear all TS state for a buffer (called on BufDelete).
---@param buf integer
function M.detach(buf)
  _attached[buf] = nil
  if _timers[buf] then
    pcall(function() _timers[buf]:stop(); _timers[buf]:close() end)
    _timers[buf] = nil
  end
  clear_extmarks(buf)
end

return M
