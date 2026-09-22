-- Filename: ~/.config/neobean/lua/config/modules/inbox_note.lua
--
-- Quick-capture workflow for the Inbox:
--   <leader>nn  ask for a title, create Inbox/YYYY-MM-DD_Title.md from
--               Templates/note.md and open it
--   <leader>nh  fuzzy-find a Hub (Hubs/*.md) and insert `[[Hub]]` at the cursor
--   <leader>nt  fuzzy-find a canonical Tag (Tags/*.md) and insert it at the
--               cursor, so you don't have to remember spelling/casing

local M = {}

local notes = require("config.modules.notes")

-- Turn a free-form title into the slug used in the filename, e.g.
-- "Kafka Mirroring Prozesse!" -> "Kafka-Mirroring-Prozesse". Only strips
-- whitespace and filesystem-unsafe characters, umlauts and other UTF-8
-- letters are kept as-is (Lua's %w is ASCII-only and would mangle them)
local function slugify(title)
  local slug = title:gsub("^%s+", ""):gsub("%s+$", "")
  slug = slug:gsub("%s+", "-")
  slug = slug:gsub('[/\\:%*%?"<>|]', "")
  return slug
end

-- Insert text at the current cursor position (normal mode), leaving the
-- cursor right after the inserted text
local function insert_at_cursor(text)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { new_line })
  vim.api.nvim_win_set_cursor(0, { row, col + #text })
end

-- Prompt for Private/Work, then a title, then create + open
-- {Private,Work}/00-Inbox/YYYY-MM-DD_Title.md, seeded from
-- Templates/note.md in whichever vault was chosen (mirrors the daily-note
-- flow in config/keymaps.lua)
function M.create_note()
  vim.ui.select({ "Private", "Work" }, { prompt = "New note: Private or Work?" }, function(context)
    if not context then
      return
    end
    local which = context == "Work" and "work" or "private"

    vim.ui.input({ prompt = "New note title: " }, function(title)
      if not title or title:match("^%s*$") then
        return
      end

      local date = os.date("%Y-%m-%d")
      local slug = slugify(title)
      if slug == "" then
        vim.api.nvim_echo({ { "Title has no usable characters", "ErrorMsg" } }, false, {})
        return
      end

      local dir = notes.inbox_dir_for(which)
      vim.fn.mkdir(dir, "p")
      local path = string.format("%s/%s_%s.md", dir, date, slug)

      if vim.fn.filereadable(path) == 1 then
        vim.api.nvim_echo({ { "Note already exists, opening it: " .. path, "WarningMsg" } }, false, {})
        vim.cmd.edit(path)
        return
      end

      local lines = notes.render_note_template(title, date, notes.root_for(which))
      if not lines then
        -- Template missing, fall back to a minimal scaffold
        lines = {
          "---",
          "date: " .. date,
          "hubs:",
          "  - ",
          "tags:",
          "  - ",
          "urls:",
          "  - ",
          "---",
          "",
          "# " .. title,
        }
      end

      vim.fn.writefile(lines, path)
      vim.cmd.edit(path)
      vim.api.nvim_echo({ { "CREATED NOTE (" .. context .. ") " .. path, "WarningMsg" } }, false, {})
    end)
  end)
end

-- Open a Snacks picker over every `*.md` file in `dir`, and on confirm call
-- `on_pick(name)` with the filename (without extension) instead of opening it
local function pick_from(dir, prompt, on_pick)
  Snacks.picker.files({
    cwd = dir,
    prompt = prompt,
    finder = "files",
    format = "file",
    glob = "*.md",
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      on_pick(vim.fn.fnamemodify(item.file, ":t:r"))
    end,
  })
end

-- Fuzzy-find a Hub and insert `[[Hub]]` at the cursor
function M.pick_hub()
  pick_from(notes.hubs_dir(), "Hubs> ", function(name)
    insert_at_cursor("[[" .. name .. "]]")
  end)
end

-- Fuzzy-find a canonical Tag and insert its (lowercased) name at the cursor
function M.pick_tag()
  pick_from(notes.tags_dir(), "Tags> ", function(name)
    insert_at_cursor(name:lower())
  end)
end

return M
