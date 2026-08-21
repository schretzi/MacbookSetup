-- Filename: ~/github/dotfiles-latest/neovim/neobean/lua/plugins/ai-gemini.lua
-- ~/github/dotfiles-latest/neovim/neobean/lua/plugins/ai-gemini.lua
--
-- Claude (lazyvim.plugins.extras.ai.claudecode) and GitHub Copilot
-- (lazyvim.plugins.extras.ai.copilot / ai.copilot-chat) are enabled as
-- official LazyVim extras in lua/config/lazy.lua and need no secrets here -
-- Claude uses the `claude` CLI's own login, Copilot uses its OAuth session.
--
-- Gemini has no official LazyVim extra, so it's wired up here via
-- CodeCompanion.nvim, using the "gemini_api" HTTP adapter with a
-- pay-as-you-go API key from Google AI Studio
-- (https://aistudio.google.com/apikey). Key is read from the macOS Keychain
-- at runtime via CodeCompanion's `cmd:` prefix - it is never stored in this
-- file. One-time setup on a new machine:
--   security add-generic-password -s "gemini" -a "nvim" -w "<GEMINI-API-KEY>"
--
-- NOTE on the Google AI Pro subscription quota (2TB plan):
-- Since 2026-06-18 Google discontinued "Login with Google" OAuth in the
-- classic Gemini CLI for individual/Pro/Ultra accounts - that path now
-- errors with "This client is no longer supported for Gemini Code Assist
-- for individuals". The official successor is the Antigravity CLI
-- (`brew install --cask antigravity-cli`), which DOES ride on the
-- subscription quota, but as of now has no ACP (Agent Client Protocol)
-- support, so CodeCompanion can't wire it in as a proper adapter yet
-- (tracked upstream: google-antigravity/antigravity-cli#31). Once that
-- lands, an "antigravity_cli" ACP adapter can be added here the same way
-- gemini_cli was. Until then, Gemini access in Neovim is API-key only.
--
-- DEFAULT ADAPTERS (multiple AIs are configured, so CodeCompanion needs one
-- default per strategy - these don't have to match):
--   chat:   gemini_api  - the one thing CodeCompanion uniquely covers, since
--           Claude has its own chat (claudecode.nvim) and Copilot has its own
--           chat (CopilotChat.nvim, ai.copilot-chat extra).
--   inline: copilot     - "select code, tell it what to change" has no other
--           home in this config (copilot.lua only does ghost-text
--           completions, not instructed edits), so Copilot is the default
--           here. It's a built-in CodeCompanion adapter, reuses the same
--           OAuth session as the completion engine, no extra setup needed.
--
-- To use Gemini for an inline edit instead of the default, temporarily swap
-- strategies.inline.adapter below, or do the edit via chat (<leader>agc)
-- and paste the result back.
--
-- Keymaps:
--   <leader>agc  Toggle Gemini chat
--   <leader>agi  Add visual selection to Gemini chat
--   <leader>aga  Open CodeCompanion actions palette (pick any adapter)

return {
  "olimorris/codecompanion.nvim",
  event = "VeryLazy",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    adapters = {
      http = {
        gemini_api = function()
          return require("codecompanion.adapters").extend("gemini", {
            name = "gemini_api",
            formatted_name = "Gemini (API key)",
            schema = {
              model = {
                default = "gemini-3.7-flash", -- Pro is often too restricted for dev work
              },
            },
            env = {
              api_key = "cmd:security find-generic-password -w -s 'gemini' -a 'nvim' | tr -d '\\n'",
            },
          })
        end,
      },
    },
    strategies = {
      chat = { adapter = "gemini_api" },
      inline = { adapter = "copilot" },
    },
  },
  keys = {
    { "<leader>agc", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "AI: Gemini Chat" },
    { "<leader>agi", "<cmd>CodeCompanionChat Add<cr>", mode = "v", desc = "AI: Add selection to Gemini Chat" },
    { "<leader>aga", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "AI: CodeCompanion Actions" },
  },
  cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
}
