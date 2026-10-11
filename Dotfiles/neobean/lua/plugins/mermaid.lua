-- https://github.com/kevalin/mermaid.nvim
--
-- A feature-rich plugin for working with Mermaid diagrams: live browser
-- preview, formatting, diagnostics (via mermaid-cli) and inline rendering
-- in Kitty/Ghostty or chafa-capable terminals.
--
-- Tree-sitter parser for syntax highlighting is auto-installed via
-- `ensure_installed` in treesitter.lua.
--
-- Linting/diagnostics and `:MermaidRender` need `mermaid-cli` (`mmdc`),
-- `chafa`, `librsvg` (`rsvg-convert`) and `imagemagick` — all in
-- Brewfiles/00_base.brew, under "# graphics".
--
-- mermaid-cli (mmdc) uses puppeteer-core under the hood, which does NOT bundle
-- a headless Chrome build. Point it at the locally installed Google Chrome so
-- `:MermaidRender`/lint don't fail with "Could not find chrome-headless-shell".
local function set_puppeteer_executable_path()
  if vim.env.PUPPETEER_EXECUTABLE_PATH then return end
  local chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if vim.fn.filereadable(chrome) == 1 then
    vim.env.PUPPETEER_EXECUTABLE_PATH = chrome
  end
end

return {
  "kevalin/mermaid.nvim",
  ft = "mermaid",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    set_puppeteer_executable_path()
    require("mermaid").setup()
  end,
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "mermaid",
      callback = function()
        local buf = vim.api.nvim_get_current_buf()
        vim.keymap.set("n", "<leader>mp", "<cmd>MermaidPreview<cr>", { buffer = buf, desc = "Mermaid Preview" })
        vim.keymap.set("n", "<leader>mf", "<cmd>MermaidFormat<cr>", { buffer = buf, desc = "Mermaid Format" })
        vim.keymap.set("n", "<leader>mr", "<cmd>MermaidRender<cr>", { buffer = buf, desc = "Mermaid Render" })
        vim.keymap.set("n", "<leader>mc", "<cmd>MermaidCopyURL<cr>", { buffer = buf, desc = "Mermaid Copy URL" })
        vim.keymap.set(
          "n",
          "<leader>mx",
          "<cmd>MermaidPreviewStop<cr>",
          { buffer = buf, desc = "Mermaid Stop Preview" }
        )
      end,
    })
  end,
}
