-- ~/.config/nvim/init.lua

-- Set mapleader before plugins are loaded
-- NOTE: Your leader key was ',', which is a great choice.
vim.g.mapleader = ','
vim.g.maplocalleader = ','
vim.g.lasttab = 1

-- Load core settings
require('options')
require('keymaps')
require('autocmds')

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Load plugins using lazy.nvim
-- We pass 'plugins' which corresponds to the lua/plugins directory
require('lazy').setup('plugins', {
  -- You can add lazy.nvim options here, e.g., for performance:
  performance = {
    rtp = {
      -- disable some rtp plugins, add more here
      disabled_plugins = {
        'gzip',
        'matchit',
        'matchparen',
        'netrwPlugin',
        'tarPlugin',
        'tohtml',
        'tutor',
        'zipPlugin',
      },
    },
  },
})

-- We will ensure it's loaded via lazy.
vim.cmd.colorscheme('unokai')
vim.g.background = 'light'
