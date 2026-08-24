# Neobean — Neovim (LazyVim-based) config

**Leader key:** `Space` (`../neobean/lua/config/options.lua:20`)
**Main file:** [`../neobean/lua/config/keymaps.lua`](../neobean/lua/config/keymaps.lua) (~4,500 lines — the file also contains a lot of commented-out/abandoned experiments; treat those as history, not active config). Plus per-plugin `keys = {}` tables under [`../neobean/lua/plugins/`](../neobean/lua/plugins).

> **Scope note:** neobean is a LazyVim-based config, so LazyVim's own default
> keymaps still apply everywhere they aren't explicitly overridden in
> `keymaps.lua` or a plugin spec. The Defaults section below is a curated
> subset of the most relevant/commonly-needed LazyVim defaults, not the full
> manual — press `<space>` in neobean itself (which-key.nvim) or see
> <https://www.lazyvim.org/keymaps> for the complete, always-current list.

## Defaults

Source: [LazyVim keymaps reference](https://www.lazyvim.org/keymaps) (non-exhaustive).

### General / windows / buffers

| Mode | Key | Description |
|---|---|---|
| n | `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` | Go to left/lower/upper/right window — **overridden** in this repo, see [Cross-window / pane navigation](#cross-window--pane-navigation) below |
| n | `<C-Up>` / `<C-Down>` / `<C-Left>` / `<C-Right>` | Increase/decrease window height/width |
| n | `<S-h>` / `<S-l>` | Prev/next buffer — **`<S-h>` overridden**, see [Buffers / windows](#buffers--windows) below |
| n | `[b` / `]b` | Prev/next buffer |
| n | `<leader>bd` / `<leader>bo` / `<leader>bD` | Delete buffer / delete other buffers / delete buffer and window |
| n, i, x, s | `<C-s>` | Save file |
| n | `<esc>` | Escape and clear search highlight |
| n | `<leader>l` | Open Lazy |
| n | `<leader>fn` | New file |
| n, x | `<leader>cf` | Format |
| n | `<leader>cd` | Line diagnostics |
| n | `]d` / `[d` | Next/prev diagnostic |
| n | `]e` / `[e` / `]w` / `[w` | Next/prev error / warning |
| n | `<leader>uf` / `<leader>uF` | Toggle autoformat (global/buffer) |
| n | `<leader>ul` / `<leader>uL` | Toggle line numbers / relative numbers |
| n | `<leader>ud` | Toggle diagnostics |
| n | `<leader>gb` / `<leader>gl` / `<leader>gB` | Git blame line / git log / git browse (open) |
| n | `<leader>qq` | Quit all |
| n | `<c-/>` | Terminal (root dir) |
| n | `<leader>-` / `<leader>\|` | Split window below / right |
| n | `<leader>wd` | Delete window |
| n | `<leader>uz` | Toggle Zen Mode |

### LSP

| Mode | Key | Description |
|---|---|---|
| n | `gd` / `gr` / `gI` / `gD` | Goto definition / references / implementation / declaration |
| n | `K` | Hover |
| n, x | `<leader>ca` | Code action |
| n | `<leader>cr` — **note:** this repo redefines it, see [Custom bindings](#misc--utility) below | Rename |
| n | `<leader>co` | Organize imports |
| n | `<leader>ss` / `<leader>sS` | LSP symbols / workspace symbols |
| n | `]]` / `[[` | Next/prev reference |

### snacks.nvim (file finding / pickers)

| Mode | Key | Description |
|---|---|---|
| n | `<leader><space>` — **note:** this repo redefines it, see [Files / navigation](#files--navigation) below | Find files (root dir) |
| n | `<leader>ff` / `<leader>fF` | Find files (root dir / cwd) |
| n | `<leader>fg` | Find files (git-files) |
| n | `<leader>e` / `<leader>E` — **overridden**, see below | Explorer (root dir / cwd) |
| n | `<leader>fb` / `<leader>fB` | Buffers / buffers (all) |
| n | `<leader>sg` / `<leader>sG` | Grep (root dir / cwd) |
| n | `<leader>gs` / `<leader>gS` | Git status / stash |
| n | `<leader>sd` / `<leader>sD` | Diagnostics / buffer diagnostics |

### gitsigns.nvim

| Mode | Key | Description |
|---|---|---|
| n | `]h` / `[h` | Next/prev hunk |
| n, x | `<leader>hs` / `<leader>hr` | Stage/reset hunk (this repo remaps these under `<leader>gh…`, see [Git](#git) below) |
| n | `<leader>hp` | Preview hunk |
| n | `<leader>hb` | Blame line |

### persistence.nvim (sessions)

| Mode | Key | Description |
|---|---|---|
| n | `<leader>qs` / `<leader>ql` / `<leader>qd` | Restore session / restore last / don't save current |

## Custom bindings

### Cross-window / pane navigation

| Mode | Key | Action | File |
|---|---|---|---|
| n, v, i | `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` | `KittyNavigateLeft/Down/Up/Right` | `plugins/vim-kitty-navigator.lua` |

The old LazyVim-style in-nvim window-nav mappings for these same keys are **explicitly commented out** (`keymaps.lua:302-305`) in favor of the plugin above — deliberate, not an oversight.

### Buffers / windows

| Mode | Key | Action |
|---|---|---|
| n, v | `<Leader>wl` / `<Leader>wh` | Vertical resize ±5 |
| n | `<S-h>` | Snacks buffer picker (overrides LazyVim default "prev buffer"); `d` inside picker deletes a buffer |
| n | `<S-l>` | **No custom binding** — falls back to Vim/LazyVim default (next buffer). Comments at `keymaps.lua:239-248` say this was meant to move to a `snipe.nvim` plugin file, but `snipe.nvim` was never installed — an asymmetric, incomplete migration vs. its `<S-h>` sibling |
| n | `<Tab>` / `<S-Tab>` | Next / previous buffer (`:bnext`/`:bprevious`) — different mode from blink-cmp's `<Tab>`/`<S-Tab>` (insert-mode, completion popup only), so not a conflict |
| n | `<M-BS>` / `<leader><BS>` | `:e #` (alternate buffer) |
| n | `<leader>br` | Reload buffer |

### AI (leader `a` namespace)

| Mode | Key | Action | File |
|---|---|---|---|
| n, v | `<leader>agc` | Toggle Gemini chat (CodeCompanion) | `plugins/ai-gemini.lua` |
| v | `<leader>agi` | Add visual selection to Gemini chat | `plugins/ai-gemini.lua` |
| n, v | `<leader>aga` | CodeCompanion actions palette | `plugins/ai-gemini.lua` |

Claude Code and GitHub Copilot are wired in as official LazyVim extras (`lazy.lua`) and bring their own default `<leader>a…` keymaps, not redefined in this repo.

### Files / navigation

| Mode | Key | Action | File |
|---|---|---|---|
| n | `<leader>e` | Open **neo-tree**, revealing current file's directory | `plugins/neotree.lua` (moved here from the now-removed `<leader>R`); mini.files' old `<leader>e` is gone (`plugins/mini-files.lua`, disabled) |
| n | `<leader>E` | Open mini.files at cwd — **dead**, mini.files is disabled | `plugins/mini-files.lua` |
| n | `<leader>r` | neo-tree: toggle current file (or cwd if it doesn't exist) | `plugins/neotree.lua` — `<leader>R` no longer exists |
| n | `ff` / `fg` / `fz` / `fc` | Find files / live grep / fuzzy live grep / grep word under cursor | `plugins/fff.lua` — **see conflict below** |
| n | `<leader>fO` / `<M-f>` | Open file in Finder/explorer |
| n | `<leader>fN` | Open in Neovide |
| n | `<leader>fV` | Open PWD in VS Code |
| n | `<leader>fD` | Delete current file |
| n | `<leader>fx` | Toggle executable bit |
| n | `<M-k>` | Keymaps picker (Snacks) |
| n | `<M-b>` | Git branches picker (Snacks) |
| n | `<leader><space>` | Smart picker (Snacks) |

**mini.files buffer-local map** (`enabled = false` in `plugins/mini-files.lua` — kept for reference, currently dead code) — [`../neobean/lua/config/modules/mini-files-km.lua`](../neobean/lua/config/modules/mini-files-km.lua):

| Key | Action |
|---|---|
| `l` / `<CR>` | Go in / go in + open + quit |
| `H` / `h` | Go out (all siblings) / go out (swapped from mini.files' default) |
| `<BS>` | Reset |
| `.` | Reveal cwd |
| `s` | Synchronize |
| `<`/`>` | Trim branch |
| `<esc>` | Close |
| `<M-t>` | Open highlighted directory in a tmux pane |
| `<space>Y` | Copy highlighted entry to Finder clipboard |
| `<space>yz` | Zip + copy |
| `<space>p` | Paste |
| `<M-c>` | Copy relative path |
| `O` | Open with default app |
| `<space>i` | Quick Look preview |
| `<space>fi` | Toggle file info |

### Git

| Mode | Key | Action | File |
|---|---|---|---|
| n | `<leader>gg` | Open Neogit UI | `plugins/neogit.lua` |
| n | `<leader>gl` | Git log (vertical split, Snacks) | `plugins/snacks.lua` |
| n | `]h` / `[h` | Next / prev git hunk | `plugins/gitsigns.lua` (buffer-local, git files only) |
| n | `]H` / `[H` | Last / first hunk | `plugins/gitsigns.lua` |
| n, v | `<leader>ghs` / `<leader>ghr` | Stage / reset hunk | `plugins/gitsigns.lua` |
| n | `<leader>ghS` / `<leader>ghu` / `<leader>ghR` | Stage / undo-stage / reset buffer | `plugins/gitsigns.lua` |
| n | `<leader>ghp` | Preview hunk inline | `plugins/gitsigns.lua` |
| n | `<leader>ghb` / `<leader>ghB` | Blame line / buffer | `plugins/gitsigns.lua` |
| n | `<leader>ghd` / `<leader>ghD` | Diff this / diff vs `~` | `plugins/gitsigns.lua` |
| o, x | `ih` | Hunk textobject | `plugins/gitsigns.lua` |
| n | `<M-C>` / `<leader>gC` / `<M-c>` | Copy GitHub URL / create repo / copy filepath |
| n | `<leader>fG` | Open file's GitHub URL |
| n | `<leader>gP` | Run push script |

### Search & replace

| Mode | Key | Action | File |
|---|---|---|---|
| n | `<leader>s1` | grug-far, current file only | `plugins/grug-far.lua` |
| n, v | `<leader>sv` / `<leader>sr` | grug-far, visual range / current-extension scope | `plugins/grug-far.lua` |
| n | `<leader>su` / `<leader>sU` / `<leader>sL` | Global word replace / UPPER / lower | `keymaps.lua` |
| n | `<leader>sg` | Grep (Snacks) | `plugins/snacks.lua` |

### Markdown / notes (largest section of `keymaps.lua`, ~lines 1790–4300)

| Mode | Key | Action |
|---|---|---|
| n, i | `<M-t>` | Convert to / insert task — **see conflict below**, collides in-spirit with mini.files' `<M-t>` |
| n | `<M-x>` | Toggle task done + move to done section |
| n | `<M-d>` / v `<M-d>` | Strikethrough |
| n | `<leader>md` | Toggle dash bullet |
| n | `gsu` / `gss` | Surround with link / backtick |
| v | `<leader>mx` / `<leader>mb` | Strike / bold selection |
| n | `<leader>msle/msls/mslb/mss/msg/msu/msr` | Spelling-language switches |
| n | `zj/zk/zl/z;/zu/zi` | Fold by heading level |
| n | `<CR>` | Toggle fold |
| n | `vio` | Select inside codeblock |
| n | `<leader>mfA` | Format all repo markdown |
| n | `<leader>mfy` / `<leader>mfY` | YouTube-embed reorg |
| n | `gt`, `<leader>jj/kk/ll/;;/uu/ii` | Daily-note H1–H6 + date helpers |
| n | `<leader>fC` | Create daily note |
| n | `<leader>mA/mW/mD` | Create note for next day / week / N days |
| n, v | `<leader>mhI` / `<leader>mhD` | Heading level +/- |
| n | `<leader>mcw` | Convert to Word doc |
| n | `<leader>mZ` | Delete all marks |
| n, v, i | `<M-;>` / `<M-:>` | Paste GitHub link |
| n, i | `<C-CR>` | Emacs-style heading insert |
| n, v | `gk` / `gj` | **Overrides Vim's "move by display line"** → jump to previous/next markdown/typst heading. The code comments explicitly flag that `hardtime.nvim` interferes with this and must unrestrict it — and `plugins/hardtime.lua` does exactly that. A deliberate, documented cross-plugin dependency. |
| markdown ft | `<leader>mp` | Toggle Markdown Preview | `plugins/markdown-preview.lua` |
| typst ft | `<leader>cpp` | Toggle Typst Preview | `plugins/typst-preview.lua` |

### Images

| Mode | Key | Action |
|---|---|---|
| n, i | `<M-a>` | Paste image next to file (img-clip) |
| n, i | `<M-1>` | Paste into `assets/img/imgs` with format/thumbnail prompts |
| n | `<leader>iR` | Rename image under cursor (+ all references) |
| n | `<leader>io` / `<leader>if` | Open image under cursor in Preview / Finder |
| n | `<leader>id` | Delete image under cursor (via `trash`) |
| n, i | `<M-i>` | Upload image under cursor to Imgur — **see conflict below** |

### Misc / utility

| Mode | Key | Action |
|---|---|---|
| n | `<M-g>` | Lazygit (root dir) |
| n | `<M-2>` | Select current git diff hunk |
| n, v, i | `<M-R>` | Save all, kill tmux right pane, restart Neovim (BetterTouchTool trigger) |
| n, v, i | `<M-r>` | No-op — deliberate typo-guard next to `<M-R>` |
| n | `<C-d>` / `<C-u>` | Scroll 35% of window height, re-center (overrides Vim's default half-page scroll) |
| n, v, i | `<M-q>` | `:q!` |
| n, v, i | `<M-h>` | Noice history (all) |
| n | `<leader>fP` | Inspect a plugin's merged lazy.nvim config |
| n | `<leader>uk` | Toggle kubectl |
| v | `gl` | `$h` (go to end of line, back up 1) |
| n, i | `<M-3>` | Trigger inline `` `expr` `` → `` `expr=result` `` calculator |
| n, v | `y` | Yank to system clipboard (markdown-aware: strips linefeeds via a Prettier pass so paste into Slack/Discord doesn't retain raw `\n`s) |
| n | `<space>Y` | Copy current file to macOS Finder clipboard as a file object |
| v | `<LeftRelease>` / `<2-LeftRelease>` | Mouse-select → auto-yank to system clipboard |
| n | `yd` | Copy current line + its diagnostics |
| n | `Y` | `y$` |
| n | `<leader>fz` | Source `~/.zshrc` |
| n | `<leader>cb` / `<leader>cg` | Run current file as bash script / current `.go` file in a tmux pane |
| n | `<M-z>` | Insert filename/path/go-mod-init boilerplate |
| n | `<M-w>` | Write file |
| all LSP servers | `<leader>cr` | LSP rename that also auto-saves all buffers | `plugins/nvim-lspconfig.lua` |
| n | `<leader>ut` | Toggle sticky treesitter context | `plugins/nvim-treesitter-context.lua` |
| n | `<leader>US` | Toggle stay-centered.nvim | `plugins/stay-centered.lua` |
| n | `<leader>d` | Toggle DBUI | `plugins/dadbod-ui.lua` |
| Trouble window only | `<esc>` | Close | `plugins/trouble.lua` |
| Trouble window only | `<leader>ca` | Code action without losing Trouble focus | `plugins/trouble.lua` |
| completion popup visible | `<Tab>`/`<S-Tab>`, `<C-p>`/`<C-n>`, `<S-k>`/`<S-j>`, `<C-space>`, `<C-e>` | Snippet fwd/back, prev/next item, scroll docs, toggle docs, hide | `plugins/blink-cmp.lua` |
