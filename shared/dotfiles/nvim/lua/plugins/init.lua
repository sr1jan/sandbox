-- ~/.config/nvim/lua/plugins/init.lua

return {
  -- The order here doesn't matter, lazy.nvim handles dependencies.
  require('plugins.ui'),
  require('plugins.editing'),
  require('plugins.lsp'),
  require('plugins.utils'),
  require('plugins.ai'),

  -- Your forked plugins from sources_forked
  { dir = '~/.vim_runtime/sources_forked/peaksea' },
  { dir = '~/.vim_runtime/sources_forked/set_tabline' },
  { dir = '~/.vim_runtime/sources_forked/vim-irblack-forked' },
  { dir = '~/.vim_runtime/sources_forked/vim-peepopen' },

  -- Your custom local plugins from my_plugins
  -- { dir = '~/fun/codepartner.nvim' }, -- Using the absolute path from your tree
}
