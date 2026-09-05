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
-- Inside that section the tasks are grouped into one `#### <client>` heading
-- per @client(...) value, the same shape task_review.lua gives the vault-wide
-- digest. `M.setup_autofold()` (wired up in config/autocmds.lua) then opens
-- the section with only task_tags.default_expanded_client expanded, so a
-- screen-shared daily note doesn't spill personal task text.
--
-- Also exposed as `<leader>tC` (config/keymaps.lua) to re-run manually against
-- the daily note under the cursor, in case a task was added to an old daily
-- note after today's was already created.

local M = {}

local notes = require("config.modules.notes")
local task_states = require("config.modules.task_states")
local task_tags = require("config.modules.task_tags")

-- Heading in the daily template (Templates/daily.md) under which carried-over
-- tasks are inserted. Keep in sync if the template heading text changes.
M.section_heading = "### Open Tasks for Today"

-- Scan every daily note under notes.daily_dir() (excluding `exclude_file`,
-- today's own note) for "not done" task lines. Returns a table keyed by
-- absolute file path -> list of { line_number, text }, plus an ordered list
-- of the file paths touched (so deletions/reporting have a stable order).
local function scan_daily_notes(exclude_file)
  local daily_dir = notes.daily_dir()
  -- Matches both on-disk task forms (`- [ ]` and checkmate's rendered `- □`),
  -- see config/modules/task_states.lua -- daily notes really do contain both
  local pattern = task_states.rg_task_prefix(task_states.not_done_chars())
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

-- Heading level of `M.section_heading` (3 for `### ...`), so the section's
-- extent can be found without stopping at the `#### <client>` group
-- headings we write *inside* it
local section_level = #(M.section_heading:match("^#+") or "###")

-- Heading a client's tasks are grouped under inside the section
local function client_heading(client)
  return string.rep("#", section_level + 1) .. " " .. client
end

-- Order the clients found: the fixed ones from task_tags.lua first, in
-- their declared order, then any other @client(...) value alphabetically,
-- then "Untagged" last for tasks with no client at all -- same convention
-- as the vault-wide review in task_review.lua
local function ordered_clients(buckets)
  local order = {}
  local taken = {}

  for _, client in ipairs(task_tags.clients) do
    if buckets[client] then
      table.insert(order, client)
      taken[client] = true
    end
  end

  local extra = {}
  for client in pairs(buckets) do
    if not taken[client] and client ~= task_tags.untagged_client then
      table.insert(extra, client)
    end
  end
  table.sort(extra)
  vim.list_extend(order, extra)

  if buckets[task_tags.untagged_client] then
    table.insert(order, task_tags.untagged_client)
  end

  return order
end

-- Rebuild `target_file`'s `M.section_heading` section from `moved_lines`
-- plus whatever tasks were already sitting in it, grouped into one
-- `#### <client>` heading per @client(...) value.
--
-- Rebuilding rather than prepending is what makes the grouping hold up:
-- running the carryover again can't strand the same task under two client
-- headings, and duplicates collapse instead of piling up. Tasks carried in
-- from older notes are listed above ones that were already in the section.
-- Non-task lines already in the section (free-form notes typed during the
-- day) are kept verbatim at the top, above the first client heading, so
-- nothing written by hand is lost. If the heading is missing (hand-edited
-- file, or the template changed), it's appended at the end of the file
-- instead of failing.
local function write_section(target_file, moved_lines)
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

  -- The section runs until the next heading at the *same or higher* level
  -- (i.e. `###` or `##`), so our own `#### <client>` groups stay inside it
  local section_end = #target_lines + 1
  for i = heading_idx + 1, #target_lines do
    local hashes = target_lines[i]:match("^(#+)%s")
    if hashes and #hashes <= section_level then
      section_end = i
      break
    end
  end

  local buckets = {}
  local seen = {}
  local extra = {}

  local function add_task(line)
    local text = vim.trim(line)
    if text == "" or seen[text] then
      return
    end
    seen[text] = true
    local client = task_tags.get_client(text) or task_tags.untagged_client
    buckets[client] = buckets[client] or {}
    table.insert(buckets[client], text)
  end

  -- Carried-over tasks first, so they end up at the top of their group
  for _, line in ipairs(moved_lines) do
    add_task(line)
  end

  for i = heading_idx + 1, section_end - 1 do
    local line = target_lines[i]
    if task_states.parse_task_line(line) then
      add_task(line)
    elseif not line:match("^#+%s") and vim.trim(line) ~= "" then
      table.insert(extra, line)
    end
  end

  local body = {}
  vim.list_extend(body, extra)
  for _, client in ipairs(ordered_clients(buckets)) do
    if #body > 0 then
      table.insert(body, "")
    end
    table.insert(body, client_heading(client))
    table.insert(body, "")
    vim.list_extend(body, buckets[client])
  end

  local result = {}
  for i = 1, heading_idx do
    table.insert(result, target_lines[i])
  end
  if #body > 0 then
    table.insert(result, "")
    vim.list_extend(result, body)
  end
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
-- delete them from those source files, and write them (deduplicated by
-- exact trimmed line text, first occurrence wins) into `target_file`'s
-- "### Open Tasks for Today" section, grouped per @client(...).
-- Returns the number of tasks moved.
function M.move_unfinished_tasks(target_file)
  target_file = vim.fn.expand(target_file)
  local by_file, file_order = scan_daily_notes(target_file)

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

  -- Always rebuild, even with nothing carried over: it regroups tasks that
  -- were added to today's note by hand since the last run
  write_section(target_file, moved_lines)

  vim.notify(
    string.format("Task carryover: moved %d unfinished task(s) into %s", #moved_lines, vim.fn.fnamemodify(target_file, ":t"))
  )
  return #moved_lines
end

-- True when the buffer carries our managed section at all, so the fold
-- defaults below (and the generic "collapse everything" autocmd in
-- config/autocmds.lua) can tell a daily note from any other markdown file
-- without going through path matching
function M.is_daily_note_buffer(bufnr)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if vim.trim(line) == M.section_heading then
      return true
    end
  end
  return false
end

-- Fold defaults applied the first time a daily note is shown in a window:
-- everything from `###` down starts collapsed (the "expand to level 2" rule
-- config/autocmds.lua applies to markdown generally), except the
-- "Open Tasks for Today" section, which is opened along with the
-- task_tags.default_expanded_client group inside it. Every other client
-- group stays collapsed.
local function apply_default_folds(bufnr, winid)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local heading_idx
  for i, line in ipairs(lines) do
    if vim.trim(line) == M.section_heading then
      heading_idx = i
      break
    end
  end
  if not heading_idx then
    return
  end

  local section_end = #lines + 1
  for i = heading_idx + 1, #lines do
    local hashes = lines[i]:match("^(#+)%s")
    if hashes and #hashes <= section_level then
      section_end = i
      break
    end
  end

  vim.api.nvim_win_call(winid, function()
    -- Recompute folds and drop any manual open/close state, then collapse
    -- everything deeper than a `##` heading. markdown_foldexpr()
    -- (config/keymaps.lua) uses the heading depth as the fold level, so
    -- `section_level - 1` is literally "one level above `### <section>`"
    pcall(vim.cmd, "normal! zx")
    vim.wo[winid].foldlevel = section_level - 1

    -- Reopen the tasks section itself, then only the default client's group
    -- inside it -- the rest stay closed by virtue of 'foldlevel'
    vim.fn.cursor(heading_idx, 1)
    pcall(vim.cmd, "normal! zo")

    local wanted = client_heading(task_tags.default_expanded_client)
    for lnum = heading_idx + 1, section_end - 1 do
      local heading = lines[lnum]:match("^#+%s") and vim.trim(lines[lnum]) or nil
      if heading == wanted then
        vim.fn.cursor(lnum, 1)
        pcall(vim.cmd, "normal! zo")
      elseif heading and vim.fn.foldclosed(lnum) == -1 then
        -- 'foldlevel' should already have these closed; close them
        -- explicitly anyway so the result doesn't depend on nothing else
        -- resetting 'foldlevel' behind our back
        vim.fn.cursor(lnum, 1)
        pcall(vim.cmd, "normal! zc")
      end
    end

    vim.fn.cursor(heading_idx, 1)
  end)
end

-- Registers a BufWinEnter autocmd that applies the fold defaults above the
-- first time a daily note is shown in a given window -- once applied, manual
-- fold changes during the session are left alone; opening the note in a
-- fresh window (new split, or a new Neovim session) re-applies them.
-- Call once at startup (config/autocmds.lua). Mirrors task_review.lua's
-- setup_autofold for the review digest.
function M.setup_autofold()
  local function maybe_apply(bufnr, winid)
    if vim.w[winid].task_carryover_folds_applied then
      return
    end
    if not M.is_daily_note_buffer(bufnr) then
      return
    end
    -- Defer so the window's foldexpr/foldlevel has been set up
    -- (set_markdown_folding runs on FileType, which may not have fully
    -- applied to this window yet at the exact moment we're called). The
    -- same 100ms-ish delay the generic fold pass in config/autocmds.lua
    -- needs for the same reason.
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then
        return
      end
      if vim.api.nvim_win_get_buf(winid) ~= bufnr then
        return
      end
      -- Marked only once the folds were really applied, never up front:
      -- create_daily_note() (config/keymaps.lua) opens the freshly written
      -- note and immediately `bd!`s it again, and that throwaway window
      -- would otherwise burn the flag -- leaving the *real* `:edit` that
      -- follows with no fold defaults at all
      vim.w[winid].task_carryover_folds_applied = true
      apply_default_folds(bufnr, winid)
    end, 150)
  end

  vim.api.nvim_create_autocmd("BufWinEnter", {
    pattern = "*.md",
    callback = function(args)
      maybe_apply(args.buf, vim.api.nvim_get_current_win())
    end,
  })

  -- Catch up any window(s) that already displayed a daily note before this
  -- autocmd was registered (e.g. one passed on the command line)
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    maybe_apply(vim.api.nvim_win_get_buf(winid), winid)
  end
end

return M
