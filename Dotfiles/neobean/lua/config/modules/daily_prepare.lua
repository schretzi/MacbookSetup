-- Filename: ~/.config/neobean/lua/config/modules/daily_prepare.lua
--
-- End of day: build the next working day's note before closing the laptop, so
-- the morning starts with carried-over tasks and the day's meetings already
-- in place.
--
-- Two entry points, one seeding step, so the two can never drift:
--
--   M.prepare()          asks for a date (prefilled with the next working
--                        day), creates the note, then seeds it
--   M.seed(path, date)   carry over unfinished tasks + fill in meetings;
--                        also called from config/keymaps.lua when today's
--                        note is created because this was missed
--
-- "Next working day" skips weekends and Austrian public holidays, the latter
-- read from the subscribed holidays calendar through EventKit. If that
-- calendar is missing the logic quietly degrades to weekends-only, so the
-- holiday lookup says so once rather than failing silently.
--
-- Note on carryover: task_carryover really *moves* tasks -- they are deleted
-- from the older note and inserted into the new one, so a task exists in
-- exactly one place. Preparing Monday's note on Friday evening therefore
-- empties Friday's open tasks into Monday's. That is deliberate.

local M = {}

local notes = require("config.modules.notes")
local daily_meetings = require("config.modules.daily_meetings")

-- Guard against the failure that is otherwise diagnosed at `:w`: if the month
-- directory is not writable -- it has been created owned by root before --
-- nvim's atomic write (temp file, then rename) fails with a permission error
-- that names the file, not the directory, which is thoroughly misleading.
local function ensure_writable_dir(dir)
  if vim.fn.isdirectory(dir) == 0 then
    if vim.fn.mkdir(dir, "p") == 0 then
      return false, "could not create " .. dir
    end
  end
  if vim.fn.filewritable(dir) ~= 2 then
    -- Name the actual cause. A month directory owned by root needs a chown; a
    -- directory of yours with the write bit off needs a chmod, and suggesting
    -- the wrong one sends you off with sudo for no reason.
    local stat = vim.fn.systemlist({ "stat", "-f", "%Su %Lp", dir })[1] or ""
    local owner, mode = stat:match("^(%S+)%s+(%S+)$")
    local me = vim.env.USER or "$USER"
    local fix = (owner and owner ~= me)
        and string.format("sudo chown %s '%s'", me, dir)
      or string.format("chmod u+w '%s'", dir)
    return false,
      string.format("%s is not writable (owner=%s mode=%s) - fix with: %s",
        dir, owner or "?", mode or "?", fix)
  end
  return true
end

-- os.time for a YYYY-MM-DD string.
local function to_time(date_str)
  local y, m, d = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then
    return nil
  end
  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

-- First working day strictly after `from` (default today). Skips Saturday and
-- Sunday always, and public holidays when the holidays calendar answers.
function M.next_working_day(from)
  local candidate = (from or os.time()) + 24 * 60 * 60
  for _ = 1, 14 do
    local wday = tonumber(os.date("%w", candidate))
    local date_str = os.date("%Y-%m-%d", candidate)
    local weekend = wday == 0 or wday == 6
    if not weekend and not daily_meetings.is_holiday(date_str) then
      return candidate
    end
    candidate = candidate + 24 * 60 * 60
  end
  -- Fourteen non-working days in a row means the holiday lookup is wrong
  -- rather than the calendar being that generous.
  return (from or os.time()) + 24 * 60 * 60
end

-- Carry unfinished tasks forward and fill in the meetings. Safe to re-run:
-- carryover only moves what is still unfinished, and the meetings merge
-- updates in place.
function M.seed(path, date_str)
  local messages = {}

  local ok, err = pcall(function()
    require("config.modules.task_carryover").move_unfinished_tasks(path)
  end)
  if not ok then
    table.insert(messages, "carryover failed: " .. tostring(err))
  end

  local filled, result = daily_meetings.fill(path, date_str)
  if filled then
    table.insert(messages, string.format("%d meeting(s)", result))
  else
    table.insert(messages, "meetings unavailable: " .. tostring(result))
  end

  return messages
end

-- Create (if needed) and seed the note for a chosen date, then open it.
function M.build(date_str)
  local when = to_time(date_str)
  if not when then
    vim.notify("daily_prepare: not a date: " .. tostring(date_str), vim.log.levels.ERROR)
    return
  end

  local path = notes.daily_path(when)
  local dir = vim.fn.fnamemodify(path, ":h")

  local writable, why = ensure_writable_dir(dir)
  if not writable then
    vim.notify("daily_prepare: " .. why, vim.log.levels.ERROR)
    return
  end

  local created = false
  if vim.fn.filereadable(path) == 0 then
    local body = notes.render_daily_template(when)
    if not body then
      body = { "", "## Daily Log - " .. date_str, "" }
    end
    vim.fn.writefile(body, path)
    created = true
  end

  local messages = M.seed(path, date_str)
  vim.cmd("edit " .. vim.fn.fnameescape(path))

  vim.notify(string.format(
    "%s %s (%s)",
    created and "Created" or "Updated",
    vim.fn.fnamemodify(path, ":t"),
    table.concat(messages, ", ")
  ))
end

-- Ask which day to prepare, prefilled with the next working day.
function M.prepare()
  local suggestion = os.date("%Y-%m-%d", M.next_working_day())
  vim.ui.input({
    prompt = "Prepare daily note for: ",
    default = suggestion,
  }, function(answer)
    if not answer or vim.trim(answer) == "" then
      return
    end
    M.build(vim.trim(answer))
  end)
end

return M
