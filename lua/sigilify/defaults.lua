---@class SigilifyGroup
---@field pattern  string    Literal string to match (used by matchadd fallback)
---@field symbol   string    Unicode replacement glyph
---@field ts_query string?   Optional Tree-sitter query.  The capture named @sigil
---                          marks the exact range that will be concealed.
---                          When present, the TS path is used instead of matchadd
---                          (provided a grammar is available for the filetype).
---                          Use ft_ts_queries to supply per-filetype variants of
---                          the same logical group.

---@alias GroupName string

local M = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Built-in symbol groups
-- ─────────────────────────────────────────────────────────────────────────────
-- ts_query values use a generic capture name @sigil for the node/token to
-- conceal.  Queries are written for the most common grammar; per-filetype
-- overrides live in ft_ts_queries below.
--
-- Longer patterns must be listed first within the same logical category so
-- the sort in conceal.lua keeps them above shorter prefixes.
-- ─────────────────────────────────────────────────────────────────────────────

M.groups = {
  -- ── Comparisons ─────────────────────────────────────────────────────────
  strict_eq = {
    pattern  = "===",
    symbol   = "≣",
    ts_query = [[ (binary_expression operator: "===" @sigil) ]],
  },
  strict_neq = {
    pattern  = "!==",
    symbol   = "≢",
    ts_query = [[ (binary_expression operator: "!==" @sigil) ]],
  },
  spaceship = {
    pattern  = "<=>",
    symbol   = "⇔",
    -- no universal grammar node; ts handled per-ft in ft_ts_queries
  },
  eq = {
    pattern  = "==",
    symbol   = "≡",
    ts_query = [[ (binary_expression operator: "==" @sigil) ]],
  },
  neq = {
    pattern  = "!=",
    symbol   = "≠",
    ts_query = [[ (binary_expression operator: "!=" @sigil) ]],
  },
  lte = {
    pattern  = "<=",
    symbol   = "≤",
    ts_query = [[ (binary_expression operator: "<=" @sigil) ]],
  },
  gte = {
    pattern  = ">=",
    symbol   = "≥",
    ts_query = [[ (binary_expression operator: ">=" @sigil) ]],
  },

  -- ── Arrows ──────────────────────────────────────────────────────────────
  fat_arrow = {
    pattern  = "=>",
    symbol   = "⇒",
    ts_query = [[ (arrow_function "=>" @sigil) ]],
  },
  r_arrow = {
    pattern  = "->",
    symbol   = "→",
    -- generic: function return type arrows, method chains, etc.
    ts_query = [[ "->" @sigil ]],
  },
  l_arrow = {
    pattern  = "<-",
    symbol   = "←",
    ts_query = [[ "<-" @sigil ]],
  },

  -- ── Logical ─────────────────────────────────────────────────────────────
  and_op = {
    pattern  = "&&",
    symbol   = "∧",
    ts_query = [[ (binary_expression operator: "&&" @sigil) ]],
  },
  or_op = {
    pattern  = "||",
    symbol   = "∨",
    ts_query = [[ (binary_expression operator: "||" @sigil) ]],
  },

  -- ── Misc ────────────────────────────────────────────────────────────────
  double_colon = {
    pattern  = "::",
    symbol   = "∷",
    ts_query = [[ "::" @sigil ]],
  },

  -- ── Lambda (opt-in; currently only meaningful via ft_ts_queries) ─────────
  lambda = {
    pattern  = [[\]],
    symbol   = "λ",
    -- The generic pattern is too broad; real use is via ft_ts_queries below.
  },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Per-filetype Tree-sitter query overrides
--
-- Keys are filetype strings (same as vim's &filetype).
-- Values are tables mapping GroupName → ts_query string, or → false to force
-- the matchadd fallback for that group in that filetype, or → nil to inherit
-- the group's default ts_query.
--
-- Use this when:
--   • The grammar uses different node names than the generic query.
--   • You want a stricter or looser match for a specific language.
--   • You want to enable a group (e.g. lambda) only for certain filetypes.
-- ─────────────────────────────────────────────────────────────────────────────

M.ft_ts_queries = {
  -- ── Haskell ─────────────────────────────────────────────────────────────
  haskell = {
    -- \ only when starting a lambda expression
    lambda       = [[ (expression "\\" @sigil) ]],
    -- -> in type signatures and case branches
    r_arrow      = [[ (fun_arrow "->" @sigil) (match_arrow "->" @sigil) ]],
    -- <- in do-notation binds
    l_arrow      = [[ (bind_statement "<-" @sigil) ]],
    -- => in class/instance constraints
    fat_arrow    = [[ (context "=>" @sigil) ]],
    -- :: type annotation
    double_colon = [[ (type_annotation "::" @sigil) ]],
    -- == only in expressions, not in type-level equality
    eq           = [[ (infix_id operator: "==" @sigil) ]],
  },

  -- ── Rust ────────────────────────────────────────────────────────────────
  rust = {
    r_arrow      = [[ (->  @sigil) ]],   -- fn return types & closure returns
    fat_arrow    = [[ (match_arm "=>" @sigil) ]],
    double_colon = [[ (scoped_identifier "::" @sigil)
                      (scoped_use_list    "::" @sigil) ]],
    eq           = [[ (binary_expression operator: "==" @sigil) ]],
    neq          = [[ (binary_expression operator: "!=" @sigil) ]],
    lte          = [[ (binary_expression operator: "<=" @sigil) ]],
    gte          = [[ (binary_expression operator: ">=" @sigil) ]],
    -- spaceship doesn't exist in Rust; keep false so matchadd is also skipped
    spaceship    = false,
  },

  -- ── OCaml ───────────────────────────────────────────────────────────────
  ocaml = {
    lambda       = [[ (fun_expression "fun" @sigil) ]],  -- "fun" acts as lambda keyword
    r_arrow      = [[ (match_case "->" @sigil) (fun_expression "->" @sigil) ]],
    l_arrow      = [[ (assignment_expression "<-" @sigil) ]],
    double_colon = [[ (type_constraint ":" @sigil) ]],
  },

  -- ── Elixir ──────────────────────────────────────────────────────────────
  elixir = {
    r_arrow      = [[ (stab_clause "->" @sigil) ]],
    l_arrow      = [[ (left_arrow_block "<-" @sigil) ]],
    fat_arrow    = [[ (map_content "=>" @sigil) ]],
  },

  -- ── Python ──────────────────────────────────────────────────────────────
  python = {
    r_arrow      = [[ (function_definition "->" @sigil) ]],
    -- := walrus — opt-in custom group example users can add
    eq           = [[ (comparison_operator operators: "==" @sigil) ]],
    neq          = [[ (comparison_operator operators: "!=" @sigil) ]],
    lte          = [[ (comparison_operator operators: "<=" @sigil) ]],
    gte          = [[ (comparison_operator operators: ">=" @sigil) ]],
    -- Python has no && / ||  — force matchadd to also skip them
    and_op       = false,
    or_op        = false,
  },

  -- ── JavaScript / TypeScript ─────────────────────────────────────────────
  javascript = {
    fat_arrow    = [[ (arrow_function "=>" @sigil) ]],
    eq           = [[ (binary_expression operator: "==" @sigil) ]],
    strict_eq    = [[ (binary_expression operator: "===" @sigil) ]],
    neq          = [[ (binary_expression operator: "!=" @sigil) ]],
    strict_neq   = [[ (binary_expression operator: "!==" @sigil) ]],
  },
  typescript      = "javascript",   -- string value = alias another ft's queries
  javascriptreact = "javascript",
  typescriptreact = "javascript",

  -- ── C++ ─────────────────────────────────────────────────────────────────
  cpp = {
    spaceship    = [[ (binary_expression operator: "<=>" @sigil) ]],
    double_colon = [[ (qualified_identifier "::" @sigil) ]],
  },

  -- ── Lua ─────────────────────────────────────────────────────────────────
  lua = {
    -- Lua uses ~= for not-equal; map matchadd fallback only (no TS override needed)
    -- but disable JS-style operators so they don't fire
    strict_eq  = false,
    strict_neq = false,
    fat_arrow  = false,
    and_op     = false,   -- Lua uses `and` keyword
    or_op      = false,   -- Lua uses `or` keyword
    eq         = [[ (binary_expression operator: "==" @sigil) ]],
    neq        = [[ (binary_expression operator: "~=" @sigil) ]],
    lte        = [[ (binary_expression operator: "<=" @sigil) ]],
    gte        = [[ (binary_expression operator: ">=" @sigil) ]],
  },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Default active group list (used when a filetype has no ft_active entry)
-- ─────────────────────────────────────────────────────────────────────────────

---@type GroupName[]
M.default_active = {
  "strict_eq", "strict_neq", "spaceship",
  "eq", "neq", "lte", "gte",
  "fat_arrow", "r_arrow", "l_arrow",
  "and_op", "or_op",
  "double_colon",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Per-filetype active group lists
-- false  → disable sigilify entirely for this ft
-- table  → only these groups are active
-- ─────────────────────────────────────────────────────────────────────────────

---@type table<string, GroupName[]|false>
M.ft_active = {
  lua        = { "eq", "neq", "lte", "gte", "r_arrow", "double_colon" },
  python     = { "eq", "neq", "lte", "gte", "r_arrow" },
  javascript = { "strict_eq", "strict_neq", "eq", "neq", "lte", "gte", "fat_arrow", "r_arrow", "and_op", "or_op" },
  typescript = { "strict_eq", "strict_neq", "eq", "neq", "lte", "gte", "fat_arrow", "r_arrow", "and_op", "or_op" },
  javascriptreact = { "strict_eq", "strict_neq", "eq", "neq", "lte", "gte", "fat_arrow", "r_arrow", "and_op", "or_op" },
  typescriptreact = { "strict_eq", "strict_neq", "eq", "neq", "lte", "gte", "fat_arrow", "r_arrow", "and_op", "or_op" },
  rust       = { "eq", "neq", "lte", "gte", "r_arrow", "fat_arrow", "and_op", "or_op", "double_colon" },
  go         = { "eq", "neq", "lte", "gte", "r_arrow", "and_op", "or_op", "double_colon" },
  c          = { "eq", "neq", "lte", "gte", "r_arrow", "and_op", "or_op" },
  cpp        = { "eq", "neq", "lte", "gte", "r_arrow", "and_op", "or_op", "spaceship", "double_colon" },
  php        = { "strict_eq", "strict_neq", "eq", "neq", "lte", "gte", "r_arrow", "fat_arrow", "and_op", "or_op", "spaceship" },
  ruby       = { "eq", "neq", "lte", "gte", "r_arrow", "l_arrow", "fat_arrow", "and_op", "or_op", "spaceship", "double_colon" },
  haskell    = { "eq", "neq", "lte", "gte", "r_arrow", "l_arrow", "fat_arrow", "and_op", "or_op", "double_colon", "lambda" },
  elixir     = { "eq", "neq", "lte", "gte", "r_arrow", "l_arrow", "fat_arrow", "and_op", "or_op" },
  ocaml      = { "eq", "neq", "lte", "gte", "r_arrow", "l_arrow", "fat_arrow", "and_op", "or_op", "double_colon", "lambda" },
  scala      = { "eq", "neq", "lte", "gte", "r_arrow", "l_arrow", "fat_arrow", "and_op", "or_op", "double_colon" },
  sh         = { "eq", "neq", "lte", "gte", "and_op", "or_op", "r_arrow" },
  bash       = { "eq", "neq", "lte", "gte", "and_op", "or_op", "r_arrow" },

  help            = false,
  TelescopePrompt = false,
  lazy            = false,
}

return M
