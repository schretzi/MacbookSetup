-- Filename: ~/.config/neobean/lua/config/modules/notes.lua
--
-- Single source of truth for where markdown notes live.
-- Used by the daily note keymaps (config/keymaps.lua) and by the task pickers
-- (plugins/snacks.lua), so both agree on what "my notes" means.

local M = {}

-- NOTE: Both vaults live under the ~/Brain collection (see
-- ~/mnt/Brain and ~/Workspace/Rewe/Brain, rclone-mounted/git-cloned
-- respectively, collected under ~/Brain/{Private,Work} via symlinks) and
-- share the same subdirectory convention (00-Inbox, 10-Daily, 20-Hubs, ...),
-- so a single pair of roots plus one set of subdir constants covers both.
local personal_root = vim.fn.expand("~/Brain/Private")
local work_root = vim.fn.expand("~/Brain/Work")
-- NOTE: Subdirectory of a root that holds its daily notes
local daily_subdir = "10-Daily"

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.expand(path)
  local resolved = vim.uv.fs_realpath(expanded)
  return (resolved or vim.fs.normalize(expanded)):gsub("/$", "")
end

function M.is_inside(path, root)
  local normalized_path = normalize(path)
  local normalized_root = normalize(root)
  if not normalized_path or not normalized_root then
    return false
  end
  return normalized_path == normalized_root or vim.startswith(normalized_path, normalized_root .. "/")
end

-- True when the cwd sits anywhere inside the private vault
function M.in_private_tree()
  return M.is_inside(vim.fn.getcwd(), personal_root)
end

-- True when the cwd sits anywhere inside the work vault
function M.in_work_tree()
  return M.is_inside(vim.fn.getcwd(), work_root)
end

-- Root to search for notes, independent of where nvim happens to be started.
-- Defaults to Work: only an explicit cwd inside the private tree opts back
-- into Private, so a daily note (or anything else keyed off M.root()) never
-- lands in Private by accident - see M.daily_dir() and inbox_note.lua's
-- explicit Private/Work prompt for the two places this actually matters.
function M.root()
  if M.in_private_tree() then
    return personal_root
  end
  return work_root
end

-- Either root by explicit name, for callers that ask rather than infer (the
-- Private/Work prompt in inbox_note.lua). Falls back to M.root() for any
-- other value, so a nil/typo'd choice degrades to the same default as
-- everything else instead of erroring.
function M.root_for(which)
  if which == "private" then
    return personal_root
  end
  if which == "work" then
    return work_root
  end
  return M.root()
end

-- Directory that holds the daily notes, used by the `gt` keymap
function M.daily_dir()
  return M.root() .. "/" .. daily_subdir
end

-- Absolute path of the daily note for `date` (an os.time value), following the
-- vault convention 10-Daily/YYYY/MM-Mon/YYYY-MM-DD-Weekday.md.
--
-- `dir_override`, if given, is used instead of M.daily_dir() -- this lets
-- config/keymaps.lua build the path for an explicit directory (e.g. one
-- read off the current file, potentially in the work tree) without
-- duplicating the naming convention itself.
--
-- This is the canonical implementation. config/keymaps.lua used to carry its
-- own copy of the same convention in parse_date_line; that has been folded
-- into this function. New code should call this rather than adding a new copy.
function M.daily_path(date, dir_override)
  date = date or os.time()
  return string.format(
    "%s/%s/%s-%s/%s.md",
    dir_override or M.daily_dir(),
    os.date("%Y", date),
    os.date("%m", date),
    os.date("%b", date),
    os.date("%Y-%m-%d-%A", date)
  )
end

-- NOTE: The Obsidian template applied to newly created daily notes, relative to
-- the notes root. Keep this in sync with `template` in .obsidian/daily-notes.json
local daily_template = "60-Meta/Templates/daily.md"

-- NOTE: The Obsidian template applied to new inbox notes, see `M.render_note_template`
local note_template = "60-Meta/Templates/note.md"

-- Subdirectories of the root that hold quick-capture notes, hub pages, and
-- canonical tag pages, used by the `<leader>nn`/`<leader>nh`/`<leader>nt`
-- keymaps (config/keymaps.lua and config/modules/inbox_note.lua)
local inbox_subdir = "00-Inbox"
local hubs_subdir = "20-Hubs"
local tags_subdir = "20-Hubs" -- Tags/ wurde in der Migration aufgeloest, siehe Vault-Migration-Plan Phase 5

-- Directory that holds quick-capture notes, used by `<leader>nn`
function M.inbox_dir()
  return M.root() .. "/" .. inbox_subdir
end

-- Same as M.inbox_dir(), but for an explicit "private"/"work" choice rather
-- than the cwd-inferred root - used by inbox_note.lua's Private/Work prompt.
function M.inbox_dir_for(which)
  return M.root_for(which) .. "/" .. inbox_subdir
end

-- Directory that holds hub pages (topic index notes), used by `<leader>nh`
function M.hubs_dir()
  return M.root() .. "/" .. hubs_subdir
end

-- Directory that holds canonical tag pages, used by `<leader>nt` as a
-- spelling/lookup reference for the `tags:` frontmatter field
function M.tags_dir()
  return M.root() .. "/" .. tags_subdir
end

-- Render the Obsidian daily template for the given date, substituting the
-- template variables Obsidian itself supports, so a note created from nvim
-- looks the same as one created from Obsidian
--
-- Returns a list of lines, or nil when the template is missing or unreadable
function M.render_daily_template(date)
  date = date or os.time()

  local path = M.root() .. "/" .. daily_template
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return nil
  end

  -- Matches Obsidian's default template date and time formats
  local values = {
    date = os.date("%Y-%m-%d", date),
    time = os.date("%H:%M", date),
    title = os.date("%Y-%m-%d-%A", date),
  }

  for i, line in ipairs(lines) do
    lines[i] = line:gsub("{{(%w+)}}", function(name)
      -- Unknown variables are left untouched rather than blanked out
      return values[name:lower()]
    end)
  end

  return lines
end

-- Render the Obsidian note template for a new inbox note, substituting
-- {{date}} and {{title}}, so a note created from nvim looks the same as one
-- created from Obsidian's "New note from template" command
--
-- `root_override`, if given, is used instead of M.root() - lets
-- inbox_note.lua's Private/Work prompt pull the template from whichever
-- vault was actually chosen rather than the cwd-inferred one.
--
-- Returns a list of lines, or nil when the template is missing or unreadable
function M.render_note_template(title, date, root_override)
  date = date or os.date("%Y-%m-%d")

  local path = (root_override or M.root()) .. "/" .. note_template
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return nil
  end

  local values = { date = date, title = title }

  for i, line in ipairs(lines) do
    lines[i] = line:gsub("{{(%w+)}}", function(name)
      return values[name:lower()]
    end)
  end

  return lines
end

return M
