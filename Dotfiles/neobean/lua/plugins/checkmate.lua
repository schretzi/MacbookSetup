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
