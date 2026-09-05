-- Filename: ~/.config/neobean/lua/config/modules/daily_meetings.lua
--
-- Fills a daily note's "### Meetings" section from the macOS calendar, and
-- refreshes it later without destroying anything written underneath.
--
-- The events come from Scripts/calendar-eventkit.py in the MacbookSetup repo,
-- which reads EventKit -- the local store macOS keeps in sync from the
-- Exchange account. Nothing here talks to Microsoft: every direct route was
-- tried and is closed, and Dotfiles/zsh/.zsh/functions/calendar records which
-- and why.
--
-- Two details that are easy to get wrong:
--
--   * Meeting lines are plain bullets, never `- [ ]` / `- □`. A task-shaped
--     meeting would be swept up by task_carryover.lua as an unfinished task
--     and dragged forward for ever.
--   * Each line carries `<!-- ek:KEY -->`, invisible in Obsidian's reader.
--     KEY is the per-occurrence hash the script emits: EventKit reuses one
--     eventIdentifier across every instance of a recurring meeting, so the
--     identifier alone cannot tell Monday's stand-up from Tuesday's.
--
-- Refresh is a merge, not a rewrite. Lines you add under a meeting stay with
-- it, changed times update in place, and a meeting that disappears from the
-- calendar is struck through and marked cancelled rather than deleted -- a
-- meeting silently vanishing is exactly the failure that makes you distrust
-- the calendar.

local M = {}

local notes = require("config.modules.notes")

M.section_heading = "### Meetings"

-- Section this one is inserted before when the note does not have it yet.
M.insert_before = "### Open Tasks for Today"

-- EventKit source and calendar titles holding the work calendar. The account
-- mounts several -- birthdays, US holidays and three empty shared ones -- so
-- filtering by source alone once put "Labor Day" in a Vienna work agenda.
M.source = "Exchange"
M.calendars = "Calendar"

-- Subscribed calendar used to decide whether a date is a public holiday.
M.holiday_calendars = "Österreichische Feiertage"

local section_level = #(M.section_heading:match("^#+") or "###")

-- Resolve Scripts/calendar-eventkit.py without hardcoding a checkout path:
-- this file is symlinked into ~/.config/neobean from the MacbookSetup repo,
-- so resolving the symlink and walking up finds the repo the config actually
-- came from. Falls back to the usual location when that fails.
local function script_path()
  local this = debug.getinfo(1, "S").source:sub(2)
  local real = vim.loop.fs_realpath(this)
  if real then
    -- <repo>/Dotfiles/neobean/lua/config/modules/daily_meetings.lua
    local repo = vim.fn.fnamemodify(real, ":h:h:h:h:h:h")
    local candidate = repo .. "/Scripts/calendar-eventkit.py"
    if vim.fn.filereadable(candidate) == 1 then
      return candidate
    end
  end
  return vim.fn.expand("~/Workspace/Schretzi/MacbookSetup/Scripts/calendar-eventkit.py")
end

-- Run the script for one day and return a list of event tables.
-- Returns nil plus a message when the calendar could not be read at all, so
-- callers can tell "no meetings" from "could not look".
function M.fetch(date_str, calendars, source)
  local script = script_path()
  if vim.fn.filereadable(script) == 0 then
    return nil, "calendar-eventkit.py not found at " .. script
  end

  local cmd = {
    "env",
    -- PyPI arrives under privoxy's inspection certificate, which uv's bundled
    -- root store has never heard of; without this the first run dies while
    -- resolving dependencies. Same reason the uv_tools role sets it.
    "UV_SYSTEM_CERTS=1",
    "uv",
    "run",
    "--quiet",
    script,
    date_str,
    "--json",
    "--calendars",
    calendars or M.calendars,
  }
  if source ~= false then
    table.insert(cmd, "--source")
    table.insert(cmd, source or M.source)
  end

  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, vim.trim(out)
  end

  local ok, decoded = pcall(vim.json.decode, out)
  if not ok or type(decoded) ~= "table" then
    return nil, "could not parse calendar output"
  end
  return decoded
end

-- True when `date_str` carries an all-day event in the holidays calendar.
-- `source = false` because that calendar is subscribed, not from Exchange.
function M.is_holiday(date_str)
  local events = M.fetch(date_str, M.holiday_calendars, false)
  return events ~= nil and #events > 0
end

local function marker(key, cancelled)
  return cancelled and ("<!-- ek:" .. key .. " cancelled -->")
    or ("<!-- ek:" .. key .. " -->")
end

local function describe(event)
  local when = event.all_day and "all day" or (event.start_hm .. "-" .. event.end_hm)
  local text = when .. " " .. (event.subject or "")
  if event.location and event.location ~= "" then
    text = text .. " @ " .. event.location
  end
  return text
end

local function render(event)
  return "- " .. describe(event) .. " " .. marker(event.occurrence)
end

local function render_cancelled(event_text, key)
  return "- ~~" .. event_text .. "~~ (cancelled) " .. marker(key, true)
end

-- Split a rendered entry line back into its visible text and its key.
local function parse_entry(line)
  local key, cancelled = line:match("<!%-%-%s*ek:(%x+)%s*(c?a?n?c?e?l?l?e?d?)%s*%-%->")
  if not key then
    return nil
  end
  local text = line:gsub("%s*<!%-%-%s*ek:%x+.-%-%->%s*$", "")
  text = text:gsub("^%-%s*", "")
  text = text:gsub("^~~(.*)~~%s*%(cancelled%)%s*$", "%1")
  return key, text, cancelled == "cancelled"
end

-- Merge `events` into the "### Meetings" section of `path`.
function M.fill(path, date_str)
  local events, err = M.fetch(date_str)
  if not events then
    return false, err
  end

  local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}

  local heading_idx
  for i, line in ipairs(lines) do
    if vim.trim(line) == M.section_heading then
      heading_idx = i
      break
    end
  end

  if not heading_idx then
    -- Put it before the tasks section when there is one, so the day reads
    -- fixed-commitments-then-choices; otherwise append.
    local anchor
    for i, line in ipairs(lines) do
      if vim.trim(line) == M.insert_before then
        anchor = i
        break
      end
    end
    if anchor then
      table.insert(lines, anchor, "")
      table.insert(lines, anchor, M.section_heading)
      heading_idx = anchor
    else
      if #lines > 0 and lines[#lines] ~= "" then
        table.insert(lines, "")
      end
      table.insert(lines, M.section_heading)
      heading_idx = #lines
    end
  end

  local section_end = #lines + 1
  for i = heading_idx + 1, #lines do
    local hashes = lines[i]:match("^(#+)%s")
    if hashes and #hashes <= section_level then
      section_end = i
      break
    end
  end

  -- Existing entries, each with whatever the user wrote beneath it.
  local existing, order, preamble = {}, {}, {}
  local current
  for i = heading_idx + 1, section_end - 1 do
    local line = lines[i]
    local key, text, cancelled = parse_entry(line)
    if key then
      current = { key = key, text = text, cancelled = cancelled, notes = {} }
      existing[key] = current
      table.insert(order, key)
    elseif current then
      table.insert(current.notes, line)
    elseif vim.trim(line) ~= "" then
      table.insert(preamble, line)
    end
  end

  -- Trailing blank lines belong to the section, not to the last meeting.
  for _, entry in pairs(existing) do
    while #entry.notes > 0 and vim.trim(entry.notes[#entry.notes]) == "" do
      table.remove(entry.notes)
    end
  end

  local body, seen = {}, {}
  vim.list_extend(body, preamble)

  for _, event in ipairs(events) do
    seen[event.occurrence] = true
    table.insert(body, render(event))
    local prior = existing[event.occurrence]
    if prior then
      vim.list_extend(body, prior.notes)
    end
  end

  -- Anything left was on the calendar before and is not any more.
  for _, key in ipairs(order) do
    if not seen[key] then
      local entry = existing[key]
      table.insert(body, render_cancelled(entry.text, key))
      vim.list_extend(body, entry.notes)
    end
  end

  if #body == 0 then
    body = { "- no meetings" }
  end

  local rebuilt = {}
  for i = 1, heading_idx do
    table.insert(rebuilt, lines[i])
  end
  table.insert(rebuilt, "")
  vim.list_extend(rebuilt, body)
  table.insert(rebuilt, "")
  for i = section_end, #lines do
    table.insert(rebuilt, lines[i])
  end

  vim.fn.writefile(rebuilt, path)

  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("checktime")
    end)
  end

  return true, #events
end

-- Refresh the meetings of the daily note in the current buffer.
function M.refresh()
  local path = vim.fn.expand("%:p")
  local name = vim.fn.fnamemodify(path, ":t:r")
  local y, m, d = name:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then
    vim.notify("daily_meetings: current file is not a daily note", vim.log.levels.WARN)
    return
  end
  if not notes.is_inside(path, notes.root()) then
    vim.notify("daily_meetings: current file is outside the vault", vim.log.levels.WARN)
    return
  end

  local date_str = string.format("%s-%s-%s", y, m, d)
  local ok, result = M.fill(path, date_str)
  if not ok then
    vim.notify("daily_meetings: " .. tostring(result), vim.log.levels.ERROR)
    return
  end
  vim.notify(string.format("Meetings refreshed for %s (%d)", date_str, result))
end

return M
