-- ~/.config/nvim/lua/plugins/init.lua

return {
  -- The order here doesn't matter, lazy.nvim handles dependencies.
  require('plugins.ui'),
  require('plugins.editing'),
  require('plugins.lsp'),
  require('plugins.utils'),
  require('plugins.ai'),
}
