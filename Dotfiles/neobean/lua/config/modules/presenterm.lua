-- Filename: ~/.config/neobean/lua/config/modules/presenterm.lua
--
-- Present the current markdown buffer as a terminal slide deck
-- https://github.com/mfontanini/presenterm
--
-- Slides are split on `---` thematic breaks. Inside kitty the deck opens in its
-- own OS window, so nvim stays usable next to it and presenterm's file watcher
-- reloads the slides as you keep editing the buffer

local M = {}

-- NOTE: Customize the presenterm theme here, `presenterm --list-themes` shows them
local theme = nil

local function kitty_cmd()
  -- kitty is not always on nvim's PATH when launched outside a shell
  if vim.fn.executable("kitty") == 1 then
    return "kitty"
  end
  local bundled = "/Applications/kitty.app/Contents/MacOS/kitty"
  return vim.fn.executable(bundled) == 1 and bundled or nil
end

-- Returns the path of the buffer to present, or nil with a reason
local function presentable_path(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return nil, "Buffer has no file on disk, save it first"
  end
  if vim.bo[buf].filetype ~= "markdown" then
    return nil, "Not a markdown buffer: " .. vim.bo[buf].filetype
  end

  -- presenterm reads from disk, so flush pending changes before it starts
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent update")
  end)

  return path
end

function M.present(opts)
  opts = opts or {}

  local path, err = presentable_path(opts.buf)
  if not path then
    vim.notify(err, vim.log.levels.WARN)
    return false
  end

  local args = { "presenterm" }
  if theme then
    vim.list_extend(args, { "--theme", theme })
  end
  -- Without `--present` presenterm stays in its hot-reload mode, which is what
  -- makes the side-by-side edit/preview loop work
  if opts.present_mode then
    table.insert(args, "--present")
  end
  table.insert(args, path)

  local kitty = kitty_cmd()
  if not (kitty and vim.env.KITTY_LISTEN_ON) then
    -- Not inside kitty, or remote control is off: take over this terminal
    -- instead, nvim comes back when presenterm exits
    vim.cmd("silent !" .. table.concat(vim.tbl_map(vim.fn.shellescape, args), " "))
    vim.cmd("redraw!")
    return true
  end

  local launch = {
    kitty,
    "@",
    "launch",
    "--type=os-window",
    "--title",
    vim.fn.fnamemodify(path, ":t:r"),
    "--cwd",
    vim.fn.fnamemodify(path, ":h"),
  }
  vim.list_extend(launch, args)

  local result = vim.system(launch, { text = true }):wait()
  if result.code ~= 0 then
    vim.notify("presenterm failed to launch: " .. (result.stderr or "unknown error"), vim.log.levels.ERROR)
    return false
  end

  return true
end

return M
