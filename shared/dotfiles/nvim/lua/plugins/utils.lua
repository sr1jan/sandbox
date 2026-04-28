-- ~/.config/nvim/lua/plugins/utils.lua

return {
  -- The single, all-powerful finder plugin
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8', -- Pin to a stable version
    dependencies = {
      'nvim-lua/plenary.nvim',
      -- Recommended for better performance
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },
    config = function()
      local telescope = require('telescope')
      local builtin = require('telescope.builtin')

      telescope.setup({
        defaults = {
          -- This is the key setting
          initial_mode = 'normal',
          -- You can add other defaults here, for example:
          layout_strategy = 'horizontal',
          layout_config = {
            width = 0.95,
            height = 0.85,
          }
        }
      })

      -- Load the fzf native extension if it's installed
      pcall(telescope.load_extension, 'fzf')

      -- === Your New Keymaps ===
      -- These maps cover all the functionality of your old plugins
      vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = '[F]ind [F]iles' })
      vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = '[F]ind by [G]rep' })
      vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = '[F]ind [B]uffers' })
      vim.keymap.set('n', '<leader>fo', builtin.oldfiles, { desc = '[F]ind [O]ldfiles' })
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = '[F]ind [H]elp' })
      vim.keymap.set('n', '<leader>o', builtin.buffers, { desc = 'Find open buffers' })
      vim.keymap.set('n', '<leader>co', builtin.colorscheme, { desc = 'Find colorscheme' })

      vim.keymap.set('n', 'gd', builtin.lsp_definitions, { desc = '[G]oto [D]efinition' })
      vim.keymap.set('n', 'gr', builtin.lsp_references, { desc = '[G]oto [R]eferences' })
      vim.keymap.set('n', 'gi', builtin.lsp_implementations, { desc = '[G]oto [I]mplementation' })
      vim.keymap.set('n', '<leader>ld', builtin.diagnostics, { desc = '[L]SP [D]iagnostics' })
      vim.keymap.set('n', '<leader>ls', builtin.lsp_document_symbols, { desc = '[L]SP document [S]ymbols' })

      -- This replaces your old "gv" mapping for searching visually selected text
      vim.keymap.set('v', '<leader>s', function()
        local text = vim.fn.getreg('v')
        builtin.live_grep({ default_text = text })
      end, { desc = '[S]earch visual selection' })
    end,
  },

  -- The modern replacement for NERDTree
  {
    'nvim-tree/nvim-tree.lua',
    version = '*',                   -- Use the latest version
    dependencies = {
      'nvim-tree/nvim-web-devicons', -- For file icons
    },
    config = function()
      require('nvim-tree').setup({
        -- Configuration options for nvim-tree
        sort_by = 'case_sensitive',
        view = {
          width = 35,
        },
        renderer = {
          group_empty = true,
        },
        filters = {
          dotfiles = false, -- Change to true to show dotfiles
        },
      })

      -- Your NERDTree keymap, now for nvim-tree
      vim.keymap.set('n', '<leader>nn', ':NvimTreeToggle<CR>', { desc = 'Toggle file explorer' })
    end,
  },
}
