-- ~/.config/nvim/lua/plugins/ui.lua

return {
  -- Colorschemes from your list
  { 'morhetz/gruvbox' },
  { 'NLKNguyen/papercolor-theme' },
  { 'sainnhe/sonokai' }, -- Palenight is part of this
  { 'folke/tokyonight.nvim' },
  { 'rafi/awesome-vim-colorschemes' }, -- Contains 'sorbet'

  -- Lightline statusline
  {
    'itchyny/lightline.vim',
    config = function()
      -- Using the configuration from your my_configs.vim
      vim.g.lightline = {
        active = {
          left = { { 'mode', 'paste' }, { 'fugitive', 'readonly', 'filename', 'modified' } },
          right = { { 'lineinfo' }, { 'percent' } },
        },
        component = {
          readonly = '%{&filetype=="help"?"":&readonly?"🔒":""}',
          modified = '%{&filetype=="help"?"":&modified?"+":&modifiable?"":"-"}',
          fugitive = '%{exists("*fugitive#head")?fugitive#head():""}',
        },
        separator = { left = ' ', right = ' ' },
        subseparator = { left = ' ', right = ' ' },
      }
    end,
  },

  -- Goyo for distraction-free writing
  {
    'junegunn/goyo.vim',
    config = function()
      vim.g.goyo_width = 100
      vim.g.goyo_margin_top = 2
      vim.g.goyo_margin_bottom = 2
      vim.keymap.set('n', '<leader>z', ':Goyo<CR>', { silent = true, desc = 'Toggle Goyo' })
    end,
  },

  -- Indent Blankline
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    ---@module "ibl"
    ---@type ibl.config
    opts = {},
  },

  -- smooth scrolling
  {
    'karb94/neoscroll.nvim',
    config = function()
      require('neoscroll').setup({
        -- All these keys will be mapped to their corresponding default scrolling animation
        mappings = {
          '<C-u>',
          '<C-d>',
          '<C-b>',
          '<C-f>',
          '<C-y>',
          '<C-e>',
          'zt',
          'zz',
          'zb',
        },
        hide_cursor = true, -- Hide cursor while scrolling
        stop_eof = true, -- Stop scrolling when reaching the end or beginning of the file
        respect_scrolloff = false, -- Stop scrolling when the cursor reaches the scrolloff margin
        cursor_scrolls_alone = true, -- The cursor will keep on the same line when scrolling
        easing_function = 'quadratic', -- "circular", "quadratic", "cubic", "linear"
        pre_hook = nil,
        post_hook = nil,
        performance_options = {
          frame_rendering_latency = 8,
          full_win_line_collection = false,
        },
      })
    end,
  },
}
