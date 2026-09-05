-- Filename: ~/.config/neobean/lua/config/modules/task_review.lua
--
-- Builds a deduplicated list of every not-yet-done task across the vault
-- (open + custom in-progress/on-hold states -- everything except
-- checkmate.nvim's "checked"/"cancelled") and writes it into a single
-- marked section of a target file, replacing *only* that section on every
-- run. Safe to re-run repeatedly, and safe to keep other content in the
-- same file -- anything outside the markers is left untouched.
--
-- Used by the `<leader>tR` keymap (config/keymaps.lua)

local M = {}

local notes = require("config.modules.notes")
local task_states = require("config.modules.task_states")
local task_tags = require("config.modules.task_tags")

-- Markers delimiting the managed section
M.start_marker = "<!-- task-review:start -->"
M.end_marker = "<!-- task-review:end -->"

-- Default target file for the review, if none is given to refresh()
function M.default_target()
  return notes.root() .. "/Review.md"
end

-- Fold defaults applied the first time the review file is displayed in a
-- window (see setup_autofold() below): the first `@client` (Work, by
-- declared order in task_tags.lua) starts expanded along with all its
-- `#### <project>` subheadings, every other `### <heading>` (other clients
-- + Untagged) starts collapsed -- handy so a shared/work screen doesn't
-- show personal task text by default. Change this to expand a different
-- heading by default.
M.default_expanded_heading = task_tags.default_expanded_client

-- True if the buffer contains our managed section at all (so we don't
-- touch fold state in unrelated markdown files or a not-yet-populated
-- target file). Public, also used by config/autocmds.lua to exclude this
-- file from the generic "collapse all headings" `zk` autocmd -- that
-- autocmd would otherwise race with (and clobber) the fold defaults below.
function M.is_review_buffer(bufnr)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line == M.start_marker then
      return true
    end
  end
  return false
end

-- Collapse every `### <heading>` inside the managed section except
-- `M.default_expanded_heading` (left at whatever `foldlevel` says, i.e.
-- fully open) -- run once per window via setup_autofold()
local function apply_default_folds(bufnr, winid)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start_idx, end_idx
  for i, line in ipairs(lines) do
    if line == M.start_marker then
      start_idx = i
    elseif line == M.end_marker then
      end_idx = i
      break
    end
  end
  if not start_idx or not end_idx then
    return
  end

  vim.api.nvim_win_call(winid, function()
    -- Recompute folds and reset to 'foldlevel' (everything open, per
    -- set_markdown_folding() in config/keymaps.lua) before selectively
    -- closing the ones we don't want expanded by default
    pcall(vim.cmd, "normal! zx")
    for lnum = start_idx, end_idx do
      local heading = lines[lnum]:match("^### (.+)$")
      if heading and heading ~= M.default_expanded_heading then
        vim.fn.cursor(lnum, 1)
        if vim.fn.foldclosed(lnum) == -1 then
          pcall(vim.cmd, "normal! zc")
        end
      end
    end
  end)
end

-- Registers a BufWinEnter autocmd that applies the fold defaults above the
-- first time the review file is shown in a given window -- once applied,
-- manual fold changes during the session are left alone (re-entering the
-- same window later, e.g. via `gF` and back, won't re-collapse anything);
-- opening it again in a fresh window (new split, or a new Neovim session)
-- re-applies the defaults. Call once at startup (config/autocmds.lua).
function M.setup_autofold()
  local function maybe_apply(bufnr, winid)
    if not M.is_review_buffer(bufnr) then
      return
    end
    if vim.w[winid].task_review_folds_applied then
      return
    end
    vim.w[winid].task_review_folds_applied = true
    -- Defer so the window's foldexpr/foldlevel has been set up
    -- (set_markdown_folding runs on FileType, which may not have fully
    -- applied to this window yet at the exact moment we're called)
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
        apply_default_folds(bufnr, winid)
      end
    end)
  end

  vim.api.nvim_create_autocmd("BufWinEnter", {
    pattern = "*.md",
    callback = function(args)
      maybe_apply(args.buf, vim.api.nvim_get_current_win())
    end,
  })

  -- Catch up any window(s) that already displayed the review file before
  -- this autocmd was registered (e.g. it was passed on the command line
  -- and BufWinEnter already fired before config/autocmds.lua loaded)
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    maybe_apply(vim.api.nvim_win_get_buf(winid), winid)
  end
end

-- Strip the leading list marker/checkbox and trim, so `- [ ] Buy milk` and
-- `  - [.] Buy milk @priority(high)` compare/display consistently, and any
-- duplicate whitespace differences don't create false-distinct entries.
-- Reads checkmate's rendered form (`- □ Buy milk`) too, since that also
-- lands on disk -- see config/modules/task_states.lua
local function extract_text(line)
  local _, text = task_states.parse_task_line(line)
  return vim.trim(text or (line:gsub("\n$", "")))
end

-- Extract the state character (e.g. " " for open, "." for in-progress, "/"
-- for on-hold), so the review can render the task with its actual state
-- instead of flattening everything to open
local function extract_marker(line)
  local char = task_states.parse_task_line(line)
  return char or " "
end

-- Run ripgrep for every "not done" task (built-in open + custom
-- incomplete/inactive states from task_states.lua), across the whole vault.
-- `exclude_file`, if given (a path), is filtered out of the results after
-- the fact (comparing resolved absolute paths) -- this is used to keep the
-- review's own target file from being re-scanned as a source of tasks (its
-- rendered lines like `- [ ] Buy milk _(a.md:2)_` would otherwise match the
-- same "not done" pattern and get picked up as new, slightly-different
-- duplicate tasks on every subsequent refresh).
-- Returns a list of { file = <absolute path>, line = <n>, text = <string>,
-- marker = <single char> }
local function find_open_tasks(exclude_file)
  local root = notes.root()
  -- Matches both on-disk task forms (`- [ ]` and checkmate's rendered `- □`),
  -- see config/modules/task_states.lua
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
    root,
  }

  local ok, result = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)

  if not ok or (result.code ~= 0 and result.code ~= 1) then
    -- code 1 just means "no matches", not an error
    vim.notify(
      "task_review: ripgrep failed: " .. (ok and (result.stderr or "") or tostring(result)),
      vim.log.levels.ERROR
    )
    return {}
  end

  local tasks = {}
  for _, json_line in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
    local decode_ok, decoded = pcall(vim.json.decode, json_line)
    if decode_ok and decoded.type == "match" then
      local file = decoded.data.path.text
      if not exclude_path or vim.fn.fnamemodify(file, ":p") ~= exclude_path then
        local raw_line = decoded.data.lines.text
        table.insert(tasks, {
          file = file,
          line = decoded.data.line_number,
          marker = extract_marker(raw_line),
          text = extract_text(raw_line),
        })
      end
    end
  end
  return tasks
end

-- Deduplicate tasks by their trimmed text (case-sensitive), keeping every
-- source location so recurring tasks (e.g. copy-pasted across daily notes)
-- still show where they came from, once each. The marker of the *first*
-- occurrence encountered is kept for display -- if the same task text
-- somehow exists with different states across files, this is an edge case
-- we don't try to reconcile further
local function dedupe(tasks)
  local by_text = {}
  local order = {}
  for _, task in ipairs(tasks) do
    if task.text ~= "" then
      local entry = by_text[task.text]
      if not entry then
        entry = { text = task.text, marker = task.marker, sources = {} }
        by_text[task.text] = entry
        table.insert(order, entry)
      end
      table.insert(entry.sources, { file = task.file, line = task.line })
    end
  end
  table.sort(order, function(a, b)
    return a.text:lower() < b.text:lower()
  end)
  return order
end

-- Render the managed section's lines from the deduplicated task list,
-- grouped into one `###` heading per @client(...) value (fixed clients
-- first, in their declared order, then any other/custom client value found
-- alphabetically, then "Untagged" last for client-less tasks), each
-- sub-grouped into `####` headings per @project(...) value (custom
-- projects alphabetically, then "No project" last for tasks with a client
-- but no project)
local UNTAGGED_CLIENT = task_tags.untagged_client
local NO_PROJECT = "No project"

local function new_client_bucket()
  return { groups = {}, extra_projects = {}, seen_extra_projects = {}, project_order = {} }
end

local function ensure_project(bucket, name)
  if not bucket.groups[name] then
    bucket.groups[name] = {}
  end
  return bucket.groups[name]
end

local function group_by_client_project(entries)
  local buckets = {}
  local extra_clients = {}
  local seen_extra_client = {}

  local function ensure_client(name)
    if not buckets[name] then
      buckets[name] = new_client_bucket()
    end
    return buckets[name]
  end

  for _, client in ipairs(task_tags.clients) do
    ensure_client(client)
  end
  ensure_client(UNTAGGED_CLIENT)

  for _, entry in ipairs(entries) do
    local client = task_tags.get_client(entry.text)
    local project = task_tags.get_project(entry.text)
    local bucket_name = client or UNTAGGED_CLIENT

    if client and not buckets[client] and not seen_extra_client[client] then
      seen_extra_client[client] = true
      table.insert(extra_clients, client)
    end

    local bucket = ensure_client(bucket_name)
    local project_name = project or NO_PROJECT
    if project and not bucket.groups[project] and not bucket.seen_extra_projects[project] then
      bucket.seen_extra_projects[project] = true
      table.insert(bucket.extra_projects, project)
    end
    table.insert(ensure_project(bucket, project_name), entry)
  end

  table.sort(extra_clients)

  local client_order = {}
  for _, client in ipairs(task_tags.clients) do
    if next(buckets[client].groups) then
      table.insert(client_order, client)
    end
  end
  for _, client in ipairs(extra_clients) do
    table.insert(client_order, client)
  end
  if next(buckets[UNTAGGED_CLIENT].groups) then
    table.insert(client_order, UNTAGGED_CLIENT)
  end

  for _, bucket in pairs(buckets) do
    table.sort(bucket.extra_projects)
    for _, project in ipairs(bucket.extra_projects) do
      table.insert(bucket.project_order, project)
    end
    if bucket.groups[NO_PROJECT] then
      table.insert(bucket.project_order, NO_PROJECT)
    end
  end

  return buckets, client_order
end

local function render_section(entries, root)
  local buckets, client_order = group_by_client_project(entries)
  local lines = {
    M.start_marker,
    "## Open Tasks Review",
    "",
    string.format("_Generated %s -- %d unique open task(s)_", os.date("%Y-%m-%d %H:%M"), #entries),
  }

  local function render_entry(entry)
    local refs = {}
    for _, src in ipairs(entry.sources) do
      local rel = src.file:gsub("^" .. vim.pesc(root) .. "/", "")
      table.insert(refs, string.format("%s:%d", rel, src.line))
    end
    local suffix = #refs > 1 and string.format(" _(x%d: %s)_", #refs, table.concat(refs, ", "))
      or string.format(" _(%s)_", refs[1])
    table.insert(lines, "- [" .. entry.marker .. "] " .. entry.text .. suffix)
  end

  for _, client in ipairs(client_order) do
    table.insert(lines, "")
    table.insert(lines, "### " .. client)
    local bucket = buckets[client]
    for _, project in ipairs(bucket.project_order) do
      table.insert(lines, "")
      table.insert(lines, "#### " .. project)
      table.insert(lines, "")
      for _, entry in ipairs(bucket.groups[project]) do
        render_entry(entry)
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, M.end_marker)
  return lines
end

-- Replace the managed section inside `target_lines` with `section_lines`.
-- If the markers aren't found (e.g. brand new file), the section is
-- appended at the end instead
local function splice_section(target_lines, section_lines)
  local start_idx, end_idx
  for i, line in ipairs(target_lines) do
    if line == M.start_marker then
      start_idx = i
    elseif line == M.end_marker and start_idx then
      end_idx = i
      break
    end
  end

  if start_idx and end_idx then
    local new_lines = {}
    for i = 1, start_idx - 1 do
      table.insert(new_lines, target_lines[i])
    end
    vim.list_extend(new_lines, section_lines)
    for i = end_idx + 1, #target_lines do
      table.insert(new_lines, target_lines[i])
    end
    return new_lines
  end

  local new_lines = vim.deepcopy(target_lines)
  if #new_lines > 0 and new_lines[#new_lines] ~= "" then
    table.insert(new_lines, "")
  end
  vim.list_extend(new_lines, section_lines)
  return new_lines
end

-- Find every not-done task in the vault, dedupe it, and write/replace the
-- managed section in `target_file` (defaults to `notes.root()/Review.md`).
-- Safe to call repeatedly: only the marked section is ever touched, and
-- running it again with no task changes produces the same list (only the
-- generated-timestamp line differs).
function M.refresh(target_file)
  target_file = vim.fn.expand(target_file or M.default_target())

  local root = notes.root()
  local entries = dedupe(find_open_tasks(target_file))
  local section_lines = render_section(entries, root)

  local target_lines = {}
  if vim.fn.filereadable(target_file) == 1 then
    target_lines = vim.fn.readfile(target_file)
  else
    vim.fn.mkdir(vim.fn.fnamemodify(target_file, ":h"), "p")
  end

  local new_lines = splice_section(target_lines, section_lines)
  vim.fn.writefile(new_lines, target_file)

  -- If the target file happens to be open already, reload it in place
  local bufnr = vim.fn.bufnr(target_file)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("checktime")
    end)
  end

  vim.notify(string.format("Task review: %d unique open task(s) written to %s", #entries, target_file))
  return #entries
end

return M
