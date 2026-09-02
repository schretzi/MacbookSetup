-- Filename: ~/.config/neobean/lua/config/modules/task_carryover.lua
--
-- When today's daily note is created (config/keymaps.lua's create_daily_note()),
-- sweep every *other* daily note for unfinished tasks (any not-done state --
-- open, in-progress, on-hold, ..., same set task_review.lua treats as "not
-- done") and really move them: deleted from the old note, inserted into
-- today's "### Open Tasks for Today" section. Small stray to-dos jotted in a
-- daily note don't get silently lost once that day scrolls off -- they
-- follow you forward until done.
--
-- Also exposed as `<leader>tC` (config/keymaps.lua) to re-run manually against
-- the daily note under the cursor, in case a task was added to an old daily
-- note after today's was already created.

local M = {}

local notes = require("config.modules.notes")
local task_states = require("config.modules.task_states")

-- Heading in the daily template (Templates/daily.md) under which carried-over
-- tasks are inserted. Keep in sync if the template heading text changes.
M.section_heading = "### Open Tasks for Today"

-- Scan every daily note under notes.daily_dir() (excluding `exclude_file`,
-- today's own note) for "not done" task lines. Returns a table keyed by
-- absolute file path -> list of { line_number, text }, plus an ordered list
-- of the file paths touched (so deletions/reporting have a stable order).
local function scan_daily_notes(exclude_file)
  local daily_dir = notes.daily_dir()
  local not_done_class = " " .. task_states.escape_class(task_states.active_chars())
  local pattern = "^\\s*- \\[[" .. not_done_class .. "]\\]"
  local exclude_path = exclude_file and vim.fn.fnamemodify(exclude_file, ":p") or nil

  local cmd = {
    "rg",
    "--json",
    "--regexp",
    pattern,
    "--glob",
    "*.md",
    "--no-ignore",
    daily_dir,
  }

  local ok, result = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)

  if not ok or (result.code ~= 0 and result.code ~= 1) then
    vim.notify(
      "task_carryover: ripgrep failed: " .. (ok and (result.stderr or "") or tostring(result)),
      vim.log.levels.ERROR
    )
    return {}, {}
  end

  local by_file = {}
  local file_order = {}
  for _, json_line in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
    local decode_ok, decoded = pcall(vim.json.decode, json_line)
    if decode_ok and decoded.type == "match" then
      local abs = vim.fn.fnamemodify(decoded.data.path.text, ":p")
      if abs ~= exclude_path then
        if not by_file[abs] then
          by_file[abs] = {}
          table.insert(file_order, abs)
        end
        table.insert(by_file[abs], {
          line_number = decoded.data.line_number,
          text = decoded.data.lines.text,
        })
      end
    end
  end
  return by_file, file_order
end

-- Delete the matched task lines from a single source file. Line numbers are
-- removed highest-first so earlier removals don't shift the indices of
-- later ones.
local function delete_lines(abs_path, matches)
  local lines = vim.fn.readfile(abs_path)
  local line_numbers = {}
  for _, match in ipairs(matches) do
    table.insert(line_numbers, match.line_number)
  end
  table.sort(line_numbers, function(a, b)
    return a > b
  end)
  for _, lnum in ipairs(line_numbers) do
    table.remove(lines, lnum)
  end
  vim.fn.writefile(lines, abs_path)

  -- If the source file happens to be open already, reload it in place so
  -- the buffer doesn't silently drift out of sync with disk
  local bufnr = vim.fn.bufnr(abs_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("checktime")
    end)
  end
end

-- Insert `moved_lines` into `target_file`'s `M.section_heading` section,
-- above whatever's already there. If the heading is missing (hand-edited
-- file, or the template changed), the heading + lines are appended at the
-- end instead of failing.
local function insert_into_section(target_file, moved_lines)
  local target_lines = vim.fn.filereadable(target_file) == 1 and vim.fn.readfile(target_file) or {}

  local heading_idx
  for i, line in ipairs(target_lines) do
    if vim.trim(line) == M.section_heading then
      heading_idx = i
      break
    end
  end

  if not heading_idx then
    if #target_lines > 0 and target_lines[#target_lines] ~= "" then
      table.insert(target_lines, "")
    end
    table.insert(target_lines, M.section_heading)
    heading_idx = #target_lines
  end

  -- The rest of the section runs until the next heading (any level) or EOF
  local section_end = #target_lines + 1
  for i = heading_idx + 1, #target_lines do
    if target_lines[i]:match("^#+%s") then
      section_end = i
      break
    end
  end

  -- Existing body content already under the heading (usually empty on a
  -- freshly templated note), trimmed of surrounding blank lines so we don't
  -- accumulate blank-line cruft on repeated runs
  local body = {}
  for i = heading_idx + 1, section_end - 1 do
    table.insert(body, target_lines[i])
  end
  while body[1] == "" do
    table.remove(body, 1)
  end
  while body[#body] == "" do
    table.remove(body)
  end

  local new_body = vim.deepcopy(moved_lines)
  if #body > 0 then
    table.insert(new_body, "")
    vim.list_extend(new_body, body)
  end

  local result = {}
  for i = 1, heading_idx do
    table.insert(result, target_lines[i])
  end
  table.insert(result, "")
  vim.list_extend(result, new_body)
  table.insert(result, "")
  for i = section_end, #target_lines do
    table.insert(result, target_lines[i])
  end

  vim.fn.writefile(result, target_file)

  local bufnr = vim.fn.bufnr(target_file)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("checktime")
    end)
  end
end

-- Find every unfinished task in every daily note other than `target_file`,
-- delete them from those source files, and insert them (deduplicated by
-- exact trimmed line text, first occurrence wins) into `target_file`'s
-- "### Open Tasks for Today" section. Returns the number of tasks moved.
function M.move_unfinished_tasks(target_file)
  target_file = vim.fn.expand(target_file)
  local by_file, file_order = scan_daily_notes(target_file)
  if #file_order == 0 then
    return 0
  end

  local moved_lines = {}
  local seen = {}
  for _, abs in ipairs(file_order) do
    for _, match in ipairs(by_file[abs]) do
      local trimmed = vim.trim(match.text)
      if trimmed ~= "" and not seen[trimmed] then
        seen[trimmed] = true
        table.insert(moved_lines, trimmed)
      end
    end
  end

  -- Delete from every source file regardless of dedupe -- a real move means
  -- the old copies are gone even if their text happened to duplicate
  -- another task already carried over
  for _, abs in ipairs(file_order) do
    delete_lines(abs, by_file[abs])
  end

  if #moved_lines > 0 then
    insert_into_section(target_file, moved_lines)
  end

  vim.notify(
    string.format("Task carryover: moved %d unfinished task(s) into %s", #moved_lines, vim.fn.fnamemodify(target_file, ":t"))
  )
  return #moved_lines
end

return M
