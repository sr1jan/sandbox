-- ~/.config/nvim/lua/plugins/editing.lua

return {
  -- Core editing plugins by Tim Pope
  { 'tpope/vim-surround' },
  { 'tpope/vim-commentary' },
  { 'tpope/vim-repeat' },
  { 'tpope/vim-fugitive' },
  { 'tpope/vim-abolish' },

  -- Auto pairs for brackets and quotes
  { 'jiangmiao/auto-pairs' },

  -- Multiple Cursors
  {
    'mg979/vim-visual-multi', -- Modern alternative to vim-multiple-cursors
    init = function()
      vim.g.multi_cursor_use_default_mapping = 0
      vim.g.multi_cursor_start_word_key = '<C-s>'
      vim.g.multi_cursor_next_key = '<C-s>'
      vim.g.multi_cursor_prev_key = '<C-p>'
      vim.g.multi_cursor_skip_key = '<C-x>'
      vim.g.multi_cursor_quit_key = '<Esc>'
    end,
  },

  -- Language-specific plugins
  { 'fatih/vim-go',             config = function() vim.g.go_fmt_command = 'goimports' end },
  { 'rust-lang/rust.vim' },
  { 'vim-python/python-syntax', ft = 'python' },

  {
    'maxbrunsfeld/vim-yankstack',
    init = function()
      vim.g.yankstack_yank_keys = { 'y', 'd' }
    end,
    config = function()
      vim.keymap.set('n', '<c-p>', '<Plug>yankstack_substitute_older_paste')
      vim.keymap.set('n', '<c-n>', '<Plug>yankstack_substitute_newer_paste')
    end,
  },

  {
    'airblade/vim-gitgutter',
    init = function()
      vim.g.gitgutter_enabled = 0 -- Disabled by default as per your config
    end,
    config = function()
      vim.keymap.set('n', '<leader>d', ':GitGutterToggle<CR>', { silent = true, desc = 'Toggle Git Gutter' })
    end,
  },

  {
    'f-person/git-blame.nvim',
    init = function()
      vim.g.gitblame_enabled = 0 -- Disabled by default
      vim.g.gitblame_message_template = '<summary> • <date> • <author> • <sha>'
      vim.g.gitblame_date_format = '%x %r'
      vim.g.gitblame_display_virtual_text = 1
    end,
    config = function()
      vim.keymap.set('n', '<leader>b', ':GitBlameToggle<CR>', { silent = true, desc = 'Toggle Git Blame' })
      vim.keymap.set('n', '<M-o>', ':GitBlameOpenCommitURL<CR>', { desc = 'Open commit URL' })
    end,
  },

  {
    'iamcco/markdown-preview.nvim',
    build = function() vim.fn['mkdp#util#install']() end,
    init = function()
      vim.g.mkdp_filetypes = { 'markdown', 'md' }
    end,
    config = function()
      local map = vim.keymap.set
      map('n', '<leader>p', ':MarkdownPreviewToggle<CR>', { silent = true, desc = 'Toggle Markdown Preview' })
    end,
  },

  {
    'stevearc/conform.nvim',
    opts = {
      -- A list of formatters to use.
      formatters_by_ft = {
        lua = { 'stylua' },
        python = { 'ruff_format', 'isort' },
        javascript = { 'prettier' },
        typescript = { 'prettier' },
        yaml = { 'yamlfix' },
        json = { 'prettier' },
      },
      -- This is the key part: setting up format on save.
      format_on_save = {
        timeout_ms = 500,
        lsp_fallback = true,
      },
    },
  },
}
