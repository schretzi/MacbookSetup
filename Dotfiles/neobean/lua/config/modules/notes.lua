-- Filename: ~/.config/neobean/lua/config/modules/notes.lua
--
-- Single source of truth for where markdown notes live.
-- Used by the daily note keymaps (config/keymaps.lua) and by the task pickers
-- (plugins/snacks.lua), so both agree on what "my notes" means.

local M = {}

-- NOTE: Customize your personal notes root here, everything else derives from it
-- This is the Obsidian vault synced through iCloud
local personal_root =
  vim.fn.expand("~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Schretzi")
-- NOTE: Subdirectory of the root that holds the daily notes
local personal_daily_subdir = "Daily"

-- Work paths are not hardcoded, they are sourced from this file if it exists
local work_env_file = vim.fn.expand("~/.config/work/work-env.sh")

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.expand(path)
  local resolved = vim.uv.fs_realpath(expanded)
  return (resolved or vim.fs.normalize(expanded)):gsub("/$", "")
end

-- Sourcing work-env.sh spawns a shell, and the pickers ask for these paths on
-- every invocation, so the answers are cached for the session
local work_env_cache = {}

function M.work_env_path(name)
  if work_env_cache[name] ~= nil then
    return work_env_cache[name] or nil
  end
  if not name:match("^WORK_[A-Z0-9_]+$") or vim.fn.filereadable(work_env_file) == 0 then
    work_env_cache[name] = false
    return nil
  end

  local command =
    string.format("source %s >/dev/null 2>&1 && print -r -- ${%s}", vim.fn.shellescape(work_env_file), name)
  local output = vim.fn.systemlist({ "/bin/zsh", "-lc", command })
  if vim.v.shell_error ~= 0 or not output[1] or output[1] == "" then
    work_env_cache[name] = false
    return nil
  end

  work_env_cache[name] = normalize(output[1])
  return work_env_cache[name] or nil
end

function M.is_inside(path, root)
  local normalized_path = normalize(path)
  local normalized_root = normalize(root)
  if not normalized_path or not normalized_root then
    return false
  end
  return normalized_path == normalized_root or vim.startswith(normalized_path, normalized_root .. "/")
end

-- True when the cwd sits anywhere inside the work tree or its daily notes
local function in_work_tree()
  local cwd = vim.fn.getcwd()
  local work_daily = M.work_env_path("WORK_DAILY_NOTE_DIR")
  local work_main = M.work_env_path("WORK_MAIN_DIR")
  return (work_daily and M.is_inside(cwd, work_daily)) or (work_main and M.is_inside(cwd, work_main)) or false
end

-- Root to search for notes, independent of where nvim happens to be started
function M.root()
  if in_work_tree() then
    return M.work_env_path("WORK_MAIN_DIR") or M.work_env_path("WORK_DAILY_NOTE_DIR") or personal_root
  end
  return personal_root
end

-- Directory that holds the daily notes, used by the `gt` keymap
function M.daily_dir()
  if in_work_tree() then
    return M.work_env_path("WORK_DAILY_NOTE_DIR") or (personal_root .. "/" .. personal_daily_subdir)
  end
  return personal_root .. "/" .. personal_daily_subdir
end

-- Absolute path of the daily note for `date` (an os.time value), following the
-- vault convention Daily/YYYY/MM-Mon/YYYY-MM-DD-Weekday.md.
--
-- This is the canonical implementation. config/keymaps.lua still carries its
-- own copies of the same convention in parse_date_line, current_file_date,
-- current_daily_note_dir and create_next_n_days -- they predate this and are
-- not derived from it, so a change to the naming still has to touch them too.
-- New code should call this rather than adding a fifth copy.
function M.daily_path(date)
  date = date or os.time()
  return string.format(
    "%s/%s/%s-%s/%s.md",
    M.daily_dir(),
    os.date("%Y", date),
    os.date("%m", date),
    os.date("%b", date),
    os.date("%Y-%m-%d-%A", date)
  )
end

-- NOTE: The Obsidian template applied to newly created daily notes, relative to
-- the notes root. Keep this in sync with `template` in .obsidian/daily-notes.json
local daily_template = "Templates/daily.md"

-- NOTE: The Obsidian template applied to new inbox notes, see `M.render_note_template`
local note_template = "Templates/note.md"

-- Subdirectories of the root that hold quick-capture notes, hub pages, and
-- canonical tag pages, used by the `<leader>nn`/`<leader>nh`/`<leader>nt`
-- keymaps (config/keymaps.lua and config/modules/inbox_note.lua)
local inbox_subdir = "Inbox"
local hubs_subdir = "Hubs"
local tags_subdir = "Tags"

-- Directory that holds quick-capture notes, used by `<leader>nn`
function M.inbox_dir()
  return M.root() .. "/" .. inbox_subdir
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
-- Returns a list of lines, or nil when the template is missing or unreadable
function M.render_note_template(title, date)
  date = date or os.date("%Y-%m-%d")

  local path = M.root() .. "/" .. note_template
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
