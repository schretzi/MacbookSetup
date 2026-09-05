-- Filename: ~/github/dotfiles-latest/neovim/neobean/lua/plugins/checkmate.lua
-- ~/github/dotfiles-latest/neovim/neobean/lua/plugins/checkmate.lua

-- https://github.com/bngarren/checkmate.nvim
--
-- Adds @tag(value) metadata (e.g. @due, @priority) and custom todo states
-- (in-progress, on-hold, cancelled) on top of plain `- [ ]` markdown todos.
-- Custom states are defined in config/modules/task_states.lua, shared with
-- the task-overview pickers in plugins/snacks.lua so both agree on what
-- each markdown character means.
--
-- Scoped only to the personal notes vault (see config/modules/notes.lua) so
-- it doesn't activate in this dotfiles repo or other project markdown.
--
-- list_continuation is disabled on purpose: bullets.vim already owns <CR>
-- continuation for bullets/todos everywhere, running both would double up
-- (see plugins/bullets.lua).

local task_states = require("config.modules.task_states")
local task_tags = require("config.modules.task_tags")

-- checkmate's own `<leader>Tn` (`:Checkmate create`) leaves the new todo
-- without any metadata. It's wrapped below so a task gets stamped the way
-- the rest of this config expects -- @created(today) -- same as
-- `<leader>tn` (config/keymaps.lua) and the list-continuation auto-tagging
-- (config/modules/task_tags.lua) already do.
--
-- The checkmate call runs its own transaction, so the tagging has to wait
-- for that to finish -- hence the `vim.schedule`. In visual mode the call
-- acts on the whole selection and then exits visual mode, so we re-select
-- with `gv` first and `add_metadata` tags every todo in the range in one go.
---@param action fun(checkmate: table): boolean the checkmate API call to run first
---@param meta_name string metadata tag to stamp with today's date afterwards
---@param on_done? fun() normal-mode-only follow-up, after the tag is in place
local function with_date_tag(action, meta_name, on_done)
  local checkmate = require("checkmate")
  local was_visual = vim.fn.mode():match("^[vV\22]") ~= nil

  if not action(checkmate) then
    return
  end

  vim.schedule(function()
    if was_visual then
      pcall(vim.cmd, "normal! gv")
    end
    pcall(checkmate.add_metadata, meta_name, task_tags.today())
    if was_visual then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
      return
    end
    if on_done then
      on_done()
    end
  end)
end

-- When the new todo is still empty (i.e. `@created(...)` is all it contains,
-- which is what happens when `<leader>Tn` is pressed on an existing todo and
-- checkmate adds a sibling below), park the cursor *before* the tag and start
-- insert mode -- so typing produces `- [ ] buy milk @created(...)` and not
-- `- [ ] @created(...) buy milk`. Same convention as `<leader>tn`.
local function type_before_metadata()
  local line = vim.api.nvim_get_current_line()
  local _, text = task_states.parse_task_line(line)
  -- nothing but metadata tags after the todo marker -> empty new todo
  if not text or not text:match("^@%S") then
    return
  end
  local prefix = line:match("^%s*[-*+]%s*%S+%s")
  if not prefix then
    return
  end
  -- One blank column to type into, so the text ends up separated from the
  -- tag rather than glued onto it. checkmate leaves a trailing space of its
  -- own behind, drop that while we're here.
  vim.api.nvim_set_current_line(prefix .. " " .. vim.trim(text))
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], #prefix })
  vim.cmd("startinsert")
end

-- checkmate *replaces* `keys` wholesale instead of merging it (a merge would
-- leave duplicate mappings behind when an lhs changes), so overriding a
-- couple of mappings means handing back the full table -- taken from
-- checkmate's own defaults so the rest keeps following upstream.
local function checkmate_keys()
  local keys = vim.deepcopy(require("checkmate.config.defaults").keys)

  keys["<leader>Tn"] = {
    rhs = function()
      with_date_tag(function(checkmate)
        return checkmate.create()
      end, "created", type_before_metadata)
    end,
    desc = "Create todo item (+ @created today)",
    modes = { "n", "v" },
  }

  -- `<leader>tx` (config/keymaps.lua) already closes a todo *and* stamps
  -- @done(today); checkmate's own check keymap would be a second, subtly
  -- different way to do the same thing, so it's dropped rather than kept
  -- around as a trap. `false` tells checkmate not to map it at all.
  keys["<leader>Tc"] = false

  return keys
end

-- Auto-tag continuation lines (bullets.vim's <CR>) with
-- @created/@client/@project, but only inside the vault (matches
-- checkmate's own `files` scope below).
--
-- This lives in `init` (not `opts`) so it's registered unconditionally at
-- startup, not only once checkmate.nvim itself lazy-loads: `opts` only runs
-- the first time a markdown buffer triggers `ft = "markdown"`, which is
-- *after* that very buffer's own FileType event already fired -- so an
-- autocmd registered in `opts` would miss the first markdown file opened
-- in a session.
local function setup_continuation_autocmd()
  local notes = require("config.modules.notes")

  local function maybe_setup(bufnr)
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path ~= "" and notes.is_inside(path, notes.root()) then
      task_tags.setup_continuation(bufnr)
    end
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function(args)
      maybe_setup(args.buf)
    end,
  })

  -- Cover any markdown buffer(s) that already had FileType fire before
  -- this autocmd was registered (e.g. a file passed on the command line)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].filetype == "markdown" then
      maybe_setup(bufnr)
    end
  end
end

return {
  "bngarren/checkmate.nvim",
  ft = "markdown",
  init = setup_continuation_autocmd,
  opts = function()
    local notes = require("config.modules.notes")

    local todo_states = {}
    for name, state in pairs(task_states.custom_states) do
      todo_states[name] = {
        marker = state.marker,
        markdown = state.markdown,
        type = state.type,
        order = state.order,
      }
    end

    return {
      -- Only activate inside the Obsidian vault, any nesting depth.
      -- Both patterns are needed: checkmate's glob2regpat conversion of
      -- `**/*.md` requires at least one subdirectory (`.*/.*\.md`), so it
      -- alone would silently skip .md files living directly at vault root
      files = {
        notes.root() .. "/*.md",
        notes.root() .. "/**/*.md",
      },
      todo_states = todo_states,
      keys = checkmate_keys(),
      list_continuation = { enabled = false },
      metadata = {
        -- @due(YYYY-MM-DD) -- read by the `<leader>td` due-date picker
        due = {
          style = { fg = "#ffb86c" },
          get_value = function()
            return os.date("%Y-%m-%d")
          end,
          key = "<leader>TD",
          sort_order = 5,
        },
        -- @priority(low|medium|high)
        priority = {
          style = function(context)
            local value = context.value:lower()
            if value == "high" then
              return { fg = "#ff5555", bold = true }
            elseif value == "medium" then
              return { fg = "#ffb86c" }
            else
              return { fg = "#8be9fd" }
            end
          end,
          get_value = function()
            return "medium"
          end,
          choices = function()
            return { "low", "medium", "high" }
          end,
          key = "<leader>Tp",
          sort_order = 10,
        },
        -- @created(YYYY-MM-DD) -- key mnemonic: "Zeit" (German for "time")
        -- Usually set automatically by <leader>tn or list-continuation
        -- (config/modules/task_tags.lua), this key is just the manual escape hatch
        created = {
          style = { fg = "#9fd6d5" },
          get_value = function()
            return os.date("%Y-%m-%d")
          end,
          key = "<leader>Tz",
          sort_order = 1,
        },
        -- @done(YYYY-MM-DD) -- stamped automatically by <leader>tx
        -- (config/keymaps.lua), which also checks the todo off. This key
        -- is just the manual escape hatch.
        done = {
          style = { fg = "#50fa7b" },
          get_value = function()
            return os.date("%Y-%m-%d")
          end,
          key = "<leader>Tx",
          sort_order = 2,
        },
        -- @client(Work|Schretzi|FF) -- key mnemonic: "Klient" (German for "client")
        -- Top-level grouping in config/modules/task_review.lua
        client = {
          style = function(context)
            local value = context.value
            if value == "Work" then
              return { fg = "#8be9fd" }
            elseif value == "Schretzi" then
              return { fg = "#bd93f9" }
            elseif value == "FF" then
              return { fg = "#50fa7b" }
            else
              return { fg = "#f8f8f2" }
            end
          end,
          get_value = function()
            return task_tags.clients[1]
          end,
          choices = function()
            return task_tags.clients
          end,
          key = "<leader>Tk",
          select_on_insert = true,
          sort_order = 15,
        },
        -- @project(<free text>) -- sub-grouped under @client in
        -- config/modules/task_review.lua. Suggestions are previously-used
        -- @project values scoped to the todo's own @client (or every known
        -- project if it has none yet), from
        -- config/modules/task_tags.lua's known_projects() -- any typed
        -- value is still accepted, it just won't be offered as a suggestion
        project = {
          style = { fg = "#f1fa8c" },
          get_value = function()
            return ""
          end,
          choices = function(context)
            local _, client = context.todo:get_metadata("client")
            return task_tags.known_projects(client)
          end,
          key = "<leader>Tj",
          select_on_insert = true,
          sort_order = 16,
        },
      },
    }
  end,
}
