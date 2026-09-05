-- Filename: ~/.config/neobean/lua/config/modules/task_tags.lua
--
-- Shared helpers for the `@created(...)`/`@client(...)`/`@project(...)`
-- checkmate.nvim metadata tags, used by:
--   - plugins/checkmate.lua      (metadata definitions + styling)
--   - config/keymaps.lua         (<leader>tn: new tagged task)
--   - this module's own continuation autocmd (auto-tag on Enter-continue)
--   - config/modules/task_review.lua (group review by @client/@project)

local M = {}

-- The fixed set of clients offered by the <leader>Tk picker and the
-- <leader>tn "new task" prompt
M.clients = { "Work", "Schretzi", "FF" }

-- Heading used for tasks that carry no @client(...) tag at all, shared by
-- the vault-wide review (task_review.lua) and the daily-note carryover
-- (task_carryover.lua) so both group them under the same name
M.untagged_client = "Untagged"

-- The client whose group starts expanded when a grouped file is first shown
-- in a window (task_review.lua's digest, task_carryover.lua's "Open Tasks
-- for Today" section) -- everything else starts collapsed, so a shared or
-- screen-shared window doesn't show personal task text by default
M.default_expanded_client = M.clients[1]

function M.today()
  return os.date("%Y-%m-%d")
end

-- Extract the `@client(...)` value from a line, or nil if absent
function M.get_client(line)
  return line and line:match("@client%(([^%)]*)%)")
end

-- Extract the `@project(...)` value from a line, or nil if absent
function M.get_project(line)
  return line and line:match("@project%(([^%)]*)%)")
end

-- Scan the whole vault for every distinct `@project(...)` value used so
-- far, so the <leader>tn / <leader>Tj pickers can suggest previously-used
-- projects instead of requiring a hardcoded list (projects change far more
-- often than clients). If `client` is given and it has its own previously
-- tagged projects, only those are returned; otherwise every project seen
-- anywhere in the vault is returned (e.g. for a brand new client). Always
-- sorted alphabetically. Returns {} (not an error) if ripgrep finds nothing
-- or fails.
function M.known_projects(client)
  local notes = require("config.modules.notes")
  local root = notes.root()

  local cmd = {
    "rg",
    "--no-heading",
    "--no-line-number",
    "--glob",
    "*.md",
    "--no-ignore",
    "@project\\(",
    root,
  }

  local ok, result = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)
  if not ok or (result.code ~= 0 and result.code ~= 1) then
    return {}
  end

  local all_seen = {}
  local client_seen = {}
  for _, line in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
    local project = M.get_project(line)
    if project and project ~= "" then
      all_seen[project] = true
      if client and M.get_client(line) == client then
        client_seen[project] = true
      end
    end
  end

  local function to_sorted_list(set)
    local list = {}
    for k in pairs(set) do
      table.insert(list, k)
    end
    table.sort(list)
    return list
  end

  if client then
    local scoped = to_sorted_list(client_seen)
    if #scoped > 0 then
      return scoped
    end
  end
  return to_sorted_list(all_seen)
end

local function is_empty_task_line(line)
  return line ~= nil and line:match("^%s*[-*+]%s*%[%s*%]%s*$") ~= nil
end

local function is_task_line(line)
  return line ~= nil and line:match("^%s*[-*+]%s*%[.%]") ~= nil
end

-- Per-buffer "already tagged this row" guard, so our own edit (appending
-- tags) doesn't re-trigger itself via the same TextChangedI event
local tagged_row = {}

-- Auto-tag a freshly-created, still-empty task line with @created (always)
-- and @client/@project (inherited silently from the task line above, if it
-- has them) -- this is what makes list-continuation (bullets.vim pressing
-- <CR> on a task line) also stamp tags, without needing to touch
-- bullets.vim itself.
--
-- Only fires when the line directly above is itself a task line, so plain
-- "type `- [ ]` by hand as the very first item" isn't auto-tagged --
-- only genuine continuations are.
local function on_text_changed(bufnr)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()

  if not is_empty_task_line(line) then
    return
  end
  if tagged_row[bufnr] == row then
    return
  end

  local prev_line = row > 1 and vim.api.nvim_buf_get_lines(bufnr, row - 2, row - 1, false)[1] or nil
  if not is_task_line(prev_line) then
    return
  end

  local client = M.get_client(prev_line)
  local project = M.get_project(prev_line)
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local tags = " @created(" .. M.today() .. ")"
  if client then
    tags = tags .. " @client(" .. client .. ")"
  end
  if project then
    tags = tags .. " @project(" .. project .. ")"
  end

  tagged_row[bufnr] = row
  vim.api.nvim_set_current_line(line .. tags)
  vim.api.nvim_win_set_cursor(0, { row, col })
end

-- Wire up the continuation auto-tagging for a single buffer. Safe to call
-- more than once per buffer (guarded by a buffer-local flag)
function M.setup_continuation(bufnr)
  if vim.b[bufnr].task_tags_continuation_setup then
    return
  end
  vim.b[bufnr].task_tags_continuation_setup = true

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = bufnr,
    callback = function()
      on_text_changed(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      tagged_row[bufnr] = nil
    end,
  })
end

return M
