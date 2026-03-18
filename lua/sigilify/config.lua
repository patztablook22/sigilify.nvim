---@class SigilifyConfig
---@field conceallevel?    integer
---@field concealcursor?   string
---@field conceal_color?   string
---@field keymaps?         boolean
---@field ts_fallback?     boolean     If true, fall back to matchadd when no TS grammar is available (default true)
---@field ts_debounce_ms?  integer     Milliseconds to debounce TS re-renders on buffer change (default 150)
---@field groups?          table<string, SigilifyGroup>          Extend / override built-in groups
---@field ft_ts_queries?   table<string, table<string,string|false>|string>  Per-ft TS query overrides
---@field default_active?  string[]|false
---@field ft_active?       table<string, string[]|false>

local defaults = require("sigilify.defaults")

local M = {}

---@type SigilifyConfig
local _cfg = {}

---@param opts SigilifyConfig
function M.set(opts)
  _cfg.conceallevel   = opts.conceallevel   or 2
  _cfg.concealcursor  = opts.concealcursor  or "nci"
  _cfg.conceal_color  = opts.conceal_color  or "NONE"
  _cfg.keymaps        = opts.keymaps ~= false        -- default true
  _cfg.ts_fallback    = opts.ts_fallback ~= false    -- default true
  _cfg.ts_debounce_ms = opts.ts_debounce_ms or 150

  -- Merge group definitions
  _cfg.groups = vim.tbl_deep_extend("force", defaults.groups, opts.groups or {})

  -- Merge ft_ts_queries: built-ins first, user second
  _cfg.ft_ts_queries = vim.tbl_deep_extend("force",
    defaults.ft_ts_queries,
    opts.ft_ts_queries or {}
  )

  -- default_active
  if opts.default_active ~= nil then
    _cfg.default_active = opts.default_active
  else
    _cfg.default_active = defaults.default_active
  end

  -- ft_active
  _cfg.ft_active = vim.tbl_extend("force", defaults.ft_active, opts.ft_active or {})
end

---@param ft string
---@return string[]|false
function M.active_groups_for_ft(ft)
  local v = _cfg.ft_active[ft]
  if v == false then return false end
  if v ~= nil   then return v end
  if _cfg.default_active == false then return false end
  return _cfg.default_active
end

--- Return the effective TS query string for a group in a filetype.
--- Returns false  → skip TS entirely for this group/ft (use matchadd or nothing)
--- Returns nil    → no override; use the group's own ts_query field
--- Returns string → use this query
---@param ft string
---@param group_name string
---@return string|false|nil
function M.ts_query_for(ft, group_name)
  -- Resolve ft aliases (string values like typescript = "javascript")
  local ft_resolved = ft
  local ft_entry = _cfg.ft_ts_queries[ft]
  if type(ft_entry) == "string" then
    ft_resolved = ft_entry
    ft_entry = _cfg.ft_ts_queries[ft_resolved]
  end

  if type(ft_entry) ~= "table" then return nil end

  local v = ft_entry[group_name]
  -- explicit false = skip TS for this group in this ft
  if v == false then return false end
  -- string = use this query
  if type(v) == "string" then return v end
  -- nil = defer to the group default
  return nil
end

---@return SigilifyConfig
function M.get()
  return _cfg
end

return M
