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

return M
