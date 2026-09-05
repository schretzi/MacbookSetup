-- Filename: ~/.config/neobean/lua/config/modules/task_states.lua
--
-- Single source of truth for custom checkmate.nvim todo states, shared by
-- the checkmate plugin config (plugins/checkmate.lua) and the task overview
-- pickers (plugins/snacks.lua), so both agree on which markdown character
-- inside `- [<char>]` means what.
--
-- checkmate.nvim always saves `- [ ]` (open) and `- [x]` (done) per the
-- GitHub-flavored Markdown spec; everything else here is a *custom* state,
-- saved as its own single character.
--
-- That's only half the story on disk though. checkmate renders every todo
-- as its `marker` glyph in the buffer and converts back to the bracket form
-- in its own BufWriteCmd -- so any write that bypasses that hook (a file
-- synced in from Obsidian on another device, a plugin writing the file
-- directly, a save from a buffer checkmate never attached to) leaves the
-- *glyph* on disk instead: `- □ Buy milk`. Both forms therefore occur in the
-- vault, and everything that scans files for tasks (task_carryover.lua,
-- task_review.lua, the plugins/snacks.lua pickers) has to accept both --
-- see `M.rg_task_prefix` and `M.parse_task_line` below.
--
-- `marker` is the pretty single-glyph icon checkmate.nvim renders live in
-- the buffer (e.g. "⏸" for on-hold) instead of the raw `- [<char>]` text --
-- this looks good and is how checkmate is meant to be used, but it means
-- every *other* tool here that expects literal bracket text in the live
-- buffer (`<M-x>` in config/modules/markdown_tasks.lua, the continuation
-- auto-tagging in config/modules/task_tags.lua) can't see/edit these lines
-- reliably once they're rendered as an icon. That's why there are
-- dedicated `<leader>tx` / `<leader>t.` / `<leader>t/` keymaps
-- (config/keymaps.lua) that go through checkmate's own `toggle()`/
-- `add_metadata()` API instead of regex -- that API works against
-- checkmate's parsed state, not the rendered buffer text, so it isn't
-- affected by the icon substitution.

local M = {}

-- Custom states: not-yet-done ("incomplete"/"inactive") or done ("complete")
-- see: https://github.com/bngarren/checkmate.nvim#custom-states
M.custom_states = {
  in_progress = { marker = "◐", markdown = ".", type = "incomplete", order = 50 },
  on_hold = { marker = "⏸", markdown = "/", type = "inactive", order = 100 },
  cancelled = { marker = "✗", markdown = "c", type = "complete", order = 2 },
}

-- Markdown chars that are "active but not open" (in progress / on hold) --
-- used by the `<leader>tp` picker
function M.active_chars()
  local chars = {}
  for _, state in pairs(M.custom_states) do
    if state.type ~= "complete" then
      table.insert(chars, state.markdown)
    end
  end
  return chars
end

-- Markdown chars that count as "done": built-in x/X plus any custom
-- `type = "complete"` state (e.g. cancelled) -- used by `<leader>tc`
function M.done_chars()
  local chars = { "x", "X" }
  for _, state in pairs(M.custom_states) do
    if state.type == "complete" then
      table.insert(chars, state.markdown)
    end
  end
  return chars
end

-- Build a ripgrep character-class body, e.g. {".", "/"} -> "./"
-- Escapes characters that are special inside a `[...]` regex class
function M.escape_class(chars)
  local escaped = {}
  for _, c in ipairs(chars) do
    if c == "]" or c == "\\" or c == "^" or c == "-" then
      table.insert(escaped, "\\" .. c)
    else
      table.insert(escaped, c)
    end
  end
  return table.concat(escaped)
end

-- checkmate.nvim's two built-in states. They're deliberately kept out of
-- `M.custom_states` (plugins/checkmate.lua feeds that straight into
-- checkmate's `todo_states`, and checkmate refuses to have these two
-- overridden), but the file scanners still need their marker/markdown pair.
-- `marker` must match checkmate's own defaults.
M.builtin_states = {
  unchecked = { marker = "□", markdown = " ", type = "incomplete" },
  checked = { marker = "✔", markdown = "x", type = "complete" },
}

-- Markdown char -> the unicode glyph checkmate renders for it, covering
-- built-in and custom states. Built once, the state tables never change.
local marker_by_char = {}
for _, state in pairs(M.builtin_states) do
  marker_by_char[state.markdown] = state.marker
end
for _, state in pairs(M.custom_states) do
  marker_by_char[state.markdown] = state.marker
end
-- Reverse lookup, built before the `X` alias below so a glyph always maps
-- back to the canonical char checkmate itself writes
local char_by_marker = {}
for markdown, marker in pairs(marker_by_char) do
  char_by_marker[marker] = markdown
end

-- `- [X]` is the same checked state as `- [x]`
marker_by_char["X"] = M.builtin_states.checked.marker

-- Markdown chars that mean "not done yet": the built-in open state plus
-- every active custom state -- what the carryover and the review sweep for
function M.not_done_chars()
  local chars = { M.builtin_states.unchecked.markdown }
  vim.list_extend(chars, M.active_chars())
  return chars
end

-- Build a ripgrep pattern matching the start of a task line whose state is
-- one of `chars`, in *either* on-disk form: the bracket form checkmate
-- saves (`- [<char>]`) or the rendered glyph (`- □`). See the module header
-- for why both show up. Callers can append to the returned pattern.
function M.rg_task_prefix(chars)
  local alternatives = { "\\[[" .. M.escape_class(chars) .. "]\\]" }
  local seen = {}
  for _, char in ipairs(chars) do
    local marker = marker_by_char[char]
    if marker and not seen[marker] then
      seen[marker] = true
      table.insert(alternatives, marker)
    end
  end
  return "^\\s*- (?:" .. table.concat(alternatives, "|") .. ")"
end

-- Split a task line into its markdown state char and its text, accepting
-- both on-disk forms, so `- [ ] Buy milk` and `- □ Buy milk` are read
-- identically. Returns nil when the line isn't a task at all.
function M.parse_task_line(line)
  line = (line or ""):gsub("\r?\n$", "")

  local char, text = line:match("^%s*[-*+]%s*%[(.)%]%s*(.*)$")
  if char then
    return char, text
  end

  local glyph, rest = line:match("^%s*[-*+]%s*(%S+)%s*(.*)$")
  if glyph and char_by_marker[glyph] then
    return char_by_marker[glyph], rest
  end

  return nil, nil
end

return M
